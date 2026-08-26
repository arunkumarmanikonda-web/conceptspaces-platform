begin;

alter table public.proposals add column if not exists milestones_snapshot jsonb not null default '[]'::jsonb;
alter table public.proposals add column if not exists commercial_hash text;
alter table public.proposals add column if not exists accepted_commercial_hash text;
alter table public.proposals drop constraint if exists proposals_milestones_snapshot_check;
alter table public.proposals add constraint proposals_milestones_snapshot_check check(jsonb_typeof(milestones_snapshot)='array');

create or replace function public.create_scope_bound_proposal(target_opportunity_id uuid,target_intake_session_id uuid,input_payload jsonb)
returns uuid language plpgsql security invoker set search_path='public','engagement','core','audit','extensions','auth','pg_temp' as $$
declare o public.opportunities%rowtype;s engagement.intake_sessions%rowtype;p public.proposals%rowtype;sel record;version_value int;subtotal_value numeric:=0;tax_value numeric:=coalesce(nullif(input_payload->>'tax','')::numeric,0);snapshot jsonb;scope_hash_value text;commercial_hash_value text;source_id uuid:=nullif(input_payload->>'source_proposal_id','')::uuid;milestones jsonb:=coalesce(input_payload->'milestones','[]'::jsonb);
begin
 select * into o from public.opportunities where id=target_opportunity_id;
 select * into s from engagement.intake_sessions where id=target_intake_session_id and opportunity_id=o.id;
 if not found or auth.uid() is null or not core.has_org_role(o.organisation_id,array['super_admin','org_admin','sales','finance']) then raise exception 'proposal_scope_authority_required';end if;
 perform public.assert_scope_dependencies(s.id);
 if not exists(select 1 from engagement.scope_selections x where x.intake_session_id=s.id and x.state='included') then raise exception 'proposal_included_scope_required';end if;
 if exists(select 1 from engagement.scope_selections x where x.intake_session_id=s.id and x.state<>'excluded' and (x.pricing_model is null or x.quoted_amount is null or x.quoted_amount<0)) then raise exception 'PRICE_RECALC_REQUIRED';end if;
 if tax_value<0 then raise exception 'proposal_tax_negative_not_allowed';end if;
 if jsonb_typeof(milestones)<>'array' then raise exception 'proposal_milestones_array_required';end if;
 if exists(select 1 from jsonb_array_elements(milestones) m where nullif(btrim(m->>'code'),'') is null or nullif(btrim(m->>'title'),'') is null) then raise exception 'proposal_milestone_code_title_required';end if;
 snapshot:=jsonb_build_object('intake_session_id',s.id,'catalogue_version',(select coalesce(max(version),1) from engagement.scope_catalogue),'selections',coalesce((select jsonb_agg(jsonb_build_object('module_code',x.module_code::text,'name',c.name,'category',c.category,'state',x.state,'pricing_model',x.pricing_model,'quoted_amount',x.quoted_amount,'currency',x.currency,'notes',x.notes,'dependencies',c.dependencies) order by x.module_code::text) from engagement.scope_selections x join engagement.scope_catalogue c on c.code=x.module_code where x.intake_session_id=s.id),'[]'::jsonb),'approved_dependency_overrides',coalesce((select jsonb_agg(jsonb_build_object('module_code',d.module_code::text,'dependency_code',d.dependency_code::text,'reason',d.reason,'id',d.id) order by d.module_code::text,d.dependency_code::text) from engagement.scope_dependency_overrides d where d.intake_session_id=s.id and d.status='approved'),'[]'::jsonb));
 scope_hash_value:=encode(extensions.digest(snapshot::text,'sha256'),'hex');
 select coalesce(max(version),0)+1 into version_value from public.proposals where opportunity_id=o.id;
 insert into public.proposals(organisation_id,opportunity_id,version,status,currency,subtotal,tax,total,valid_until,commercial_notes,created_by,scope_intake_session_id,scope_snapshot,scope_hash,source_proposal_id,milestones_snapshot) values(o.organisation_id,o.id,version_value,'draft',upper(coalesce(nullif(btrim(input_payload->>'currency'),''),o.currency)),0,tax_value,0,nullif(input_payload->>'valid_until','')::date,coalesce(input_payload->'commercial_notes','[]'::jsonb),auth.uid(),s.id,snapshot,scope_hash_value,source_id,milestones) returning * into p;
 for sel in select x.*,c.name from engagement.scope_selections x join engagement.scope_catalogue c on c.code=x.module_code where x.intake_session_id=s.id and x.state in ('included','optional') order by x.module_code loop
  insert into public.proposal_lines(proposal_id,title,scope_code,pricing_model,quantity,rate,amount,optional,sort_order) values(p.id,sel.name,sel.module_code::text,sel.pricing_model,1,sel.quoted_amount,sel.quoted_amount,sel.state='optional',0);
  if sel.state='included' then subtotal_value:=subtotal_value+coalesce(sel.quoted_amount,0);end if;
 end loop;
 commercial_hash_value:=encode(extensions.digest(jsonb_build_object('scope_hash',scope_hash_value,'currency',p.currency,'subtotal',subtotal_value,'tax',tax_value,'total',subtotal_value+tax_value,'milestones',milestones)::text,'sha256'),'hex');
 update public.proposals set subtotal=subtotal_value,total=subtotal_value+tax_value,milestones_snapshot=milestones,commercial_hash=commercial_hash_value,updated_at=now() where id=p.id returning * into p;
 insert into engagement.proposal_negotiation_events(proposal_id,version,party,event_type,amount,currency,scope_delta,note,actor_user_id) values(p.id,p.version,'Concept Spaces','proposal_created',p.total,p.currency,p.scope_snapshot,'Scope-bound proposal revision created',auth.uid());
 update public.opportunities set stage='proposal',scope_modules=(select coalesce(jsonb_agg(x.module_code::text order by x.module_code::text),'[]'::jsonb) from engagement.scope_selections x where x.intake_session_id=s.id and x.state='included'),updated_at=now() where id=o.id;
 perform audit.append_event(o.organisation_id,s.project_id,'commercial.proposal.created','proposal',p.id,null,to_jsonb(p),commercial_hash_value,gen_random_uuid());return p.id;
end;$$;
revoke all on function public.create_scope_bound_proposal(uuid,uuid,jsonb) from public,anon;grant execute on function public.create_scope_bound_proposal(uuid,uuid,jsonb) to authenticated;

create or replace function public.create_commercial_proposal(target_opportunity_id uuid,input_payload jsonb)
returns uuid language plpgsql security invoker set search_path='public','core','audit','extensions','auth','pg_temp' as $$
declare o public.opportunities%rowtype;proposal_id uuid;proposal_version integer;line jsonb;q numeric;r numeric;line_amount numeric;proposal_subtotal numeric:=0;proposal_tax numeric:=coalesce(nullif(input_payload->>'tax','')::numeric,0);proposal_row public.proposals%rowtype;pricing_value text;milestones jsonb:=coalesce(input_payload->'milestones','[]'::jsonb);commercial_hash_value text;
begin
 select * into o from public.opportunities where id=target_opportunity_id;if not found then raise exception 'opportunity_not_found';end if;
 if not core.has_org_role(o.organisation_id,array['super_admin','org_admin','sales','finance']) then raise exception 'commercial_write_authority_required';end if;
 if jsonb_typeof(coalesce(input_payload->'lines','[]'::jsonb))<>'array' or jsonb_array_length(coalesce(input_payload->'lines','[]'::jsonb))=0 then raise exception 'proposal_line_required';end if;
 if jsonb_typeof(milestones)<>'array' then raise exception 'proposal_milestones_array_required';end if;
 if exists(select 1 from jsonb_array_elements(milestones) m where nullif(btrim(m->>'code'),'') is null or nullif(btrim(m->>'title'),'') is null) then raise exception 'proposal_milestone_code_title_required';end if;
 if proposal_tax<0 then raise exception 'proposal_tax_negative_not_allowed';end if;
 select coalesce(max(version),0)+1 into proposal_version from public.proposals where opportunity_id=o.id;
 insert into public.proposals(organisation_id,opportunity_id,version,status,currency,subtotal,tax,total,valid_until,commercial_notes,created_by,milestones_snapshot) values(o.organisation_id,o.id,proposal_version,'draft',coalesce(nullif(upper(btrim(input_payload->>'currency')),''),o.currency),0,0,0,nullif(input_payload->>'valid_until','')::date,coalesce(input_payload->'commercial_notes','[]'::jsonb),auth.uid(),milestones) returning id into proposal_id;
 for line in select value from jsonb_array_elements(input_payload->'lines') loop
  if nullif(btrim(line->>'title'),'') is null or nullif(btrim(line->>'scope_code'),'') is null then raise exception 'proposal_line_title_and_scope_required';end if;
  q:=coalesce(nullif(line->>'quantity','')::numeric,1);r:=coalesce(nullif(line->>'rate','')::numeric,0);pricing_value:=lower(coalesce(nullif(btrim(line->>'pricing_model'),''),'fixed'));if q<0 or r<0 then raise exception 'proposal_line_negative_value_not_allowed';end if;if pricing_value not in ('fixed','percent','sqft','per_key','hourly','retainer','milestone','subscription','hybrid') then raise exception 'unsupported_pricing_model';end if;line_amount:=round(q*r,2);proposal_subtotal:=proposal_subtotal+line_amount;insert into public.proposal_lines(proposal_id,title,scope_code,pricing_model,quantity,rate,tax_code,amount,optional,sort_order) values(proposal_id,btrim(line->>'title'),upper(btrim(line->>'scope_code')),pricing_value,q,r,nullif(btrim(line->>'tax_code'),''),line_amount,coalesce((line->>'optional')::boolean,false),coalesce(nullif(line->>'sort_order','')::integer,0));
 end loop;
 commercial_hash_value:=encode(extensions.digest(jsonb_build_object('proposal_lines',(select jsonb_agg(to_jsonb(l) order by l.sort_order,l.scope_code) from public.proposal_lines l where l.proposal_id=proposal_id),'currency',coalesce(nullif(upper(btrim(input_payload->>'currency')),''),o.currency),'subtotal',proposal_subtotal,'tax',proposal_tax,'total',proposal_subtotal+proposal_tax,'milestones',milestones)::text,'sha256'),'hex');
 update public.proposals set subtotal=proposal_subtotal,tax=proposal_tax,total=proposal_subtotal+proposal_tax,milestones_snapshot=milestones,commercial_hash=commercial_hash_value,updated_at=now() where id=proposal_id returning * into proposal_row;
 update public.opportunities set stage='proposal',updated_at=now() where id=o.id and stage in ('discovery','briefing');
 perform audit.append_event(o.organisation_id,null,'commercial.proposal.created','proposal',proposal_id,null,to_jsonb(proposal_row),commercial_hash_value,gen_random_uuid());return proposal_id;
end;$$;
revoke all on function public.create_commercial_proposal(uuid,jsonb) from public,anon;grant execute on function public.create_commercial_proposal(uuid,jsonb) to authenticated;

create or replace function public.record_proposal_client_decision(target_proposal_id uuid,decision text,evidence_reference text,client_counter_offer numeric default null)
returns void language plpgsql security invoker set search_path='public','engagement','core','audit','auth','pg_temp' as $$
declare p public.proposals%rowtype;before_state jsonb;status_value text:=lower(btrim(decision));counter_value numeric:=client_counter_offer;
begin
 select * into p from public.proposals where id=target_proposal_id for update;if not found then raise exception 'proposal_not_found';end if;
 if not core.has_org_role(p.organisation_id,array['super_admin','org_admin','sales']) then raise exception 'client_decision_recording_authority_required';end if;
 if nullif(btrim(evidence_reference),'') is null then raise exception 'client_decision_evidence_required';end if;
 if status_value not in ('accepted','countered','rejected') then raise exception 'unsupported_client_decision';end if;
 if p.status not in ('sent','countered') then raise exception 'proposal_not_client_decision_eligible';end if;
 if p.valid_until is not null and current_date>p.valid_until then raise exception 'PROPOSAL_EXPIRED';end if;
 if status_value='countered' and (counter_value is null or counter_value<0) then raise exception 'counter_offer_required';end if;
 if status_value='accepted' and (p.commercial_hash is null or jsonb_typeof(p.milestones_snapshot)<>'array') then raise exception 'proposal_commercial_snapshot_incomplete_create_new_revision';end if;
 before_state:=to_jsonb(p);
 update public.proposals set status=status_value,client_counter_offer=case when status_value='countered' then counter_value else null end,accepted_scope_hash=case when status_value='accepted' then scope_hash else accepted_scope_hash end,accepted_commercial_hash=case when status_value='accepted' then commercial_hash else accepted_commercial_hash end,commercial_notes=commercial_notes||jsonb_build_array(jsonb_build_object('type','client_decision','decision',status_value,'evidence_reference',evidence_reference,'recorded_by',auth.uid(),'at',now())),updated_at=now() where id=p.id returning * into p;
 insert into engagement.proposal_negotiation_events(proposal_id,version,party,event_type,amount,currency,scope_delta,note,actor_user_id) values(p.id,p.version,'Client',case when status_value='countered' then 'counter_offer' else status_value end,case when status_value='countered' then counter_value else p.total end,p.currency,p.scope_snapshot,evidence_reference,auth.uid());
 if status_value='rejected' then perform public.mark_opportunity_lost(p.opportunity_id,'proposal_rejected',evidence_reference,null);else update public.opportunities set stage=case when status_value='accepted' then 'contracting' else 'negotiation' end,updated_at=now() where id=p.opportunity_id;end if;
 perform audit.append_event(p.organisation_id,null,'commercial.proposal.client_decision','proposal',p.id,before_state,to_jsonb(p),evidence_reference,gen_random_uuid());
end;$$;
revoke all on function public.record_proposal_client_decision(uuid,text,text,numeric) from public,anon;grant execute on function public.record_proposal_client_decision(uuid,text,text,numeric) to authenticated;

create or replace function public.create_contract_from_proposal(target_proposal_id uuid,target_project_id uuid default null,contract_snapshot jsonb default '{}'::jsonb)
returns uuid language plpgsql security invoker set search_path='public','legal','core','project','audit','extensions','auth','pg_temp' as $$
declare p public.proposals%rowtype;c public.contracts%rowtype;clause_id_value uuid;v legal.clause_versions%rowtype;clause_payload jsonb:='[]'::jsonb;obligations_value jsonb:=coalesce(contract_snapshot->'obligations','[]'::jsonb);obligation jsonb;snapshot_value jsonb;hash_value text;version_value int;
begin
 select * into p from public.proposals where id=target_proposal_id;
 if not found or p.status<>'accepted' or p.accepted_scope_hash is distinct from p.scope_hash or p.commercial_hash is null or p.accepted_commercial_hash is distinct from p.commercial_hash then raise exception 'proposal_must_be_client_accepted_with_exact_commercial_snapshot';end if;
 if auth.uid() is null or not core.has_org_role(p.organisation_id,array['super_admin','org_admin','finance','legal']) then raise exception 'contract_creation_authority_required';end if;
 if target_project_id is not null and not project.can_access_project(target_project_id) then raise exception 'project_access_required';end if;
 if nullif(btrim(contract_snapshot->>'contract_type'),'') is null or nullif(btrim(contract_snapshot->>'jurisdiction'),'') is null then raise exception 'contract_type_and_jurisdiction_required';end if;
 if jsonb_typeof(coalesce(contract_snapshot->'clause_version_ids','[]'::jsonb))<>'array' or jsonb_array_length(coalesce(contract_snapshot->'clause_version_ids','[]'::jsonb))=0 then raise exception 'approved_clause_set_required';end if;
 if jsonb_typeof(obligations_value)<>'array' or jsonb_array_length(obligations_value)=0 then raise exception 'contract_obligations_required';end if;
 for clause_id_value in select value::uuid from jsonb_array_elements_text(contract_snapshot->'clause_version_ids') loop select cv.* into v from legal.clause_versions cv join legal.clauses lc on lc.id=cv.clause_id where cv.id=clause_id_value and lc.organisation_id=p.organisation_id and lc.contract_type=btrim(contract_snapshot->>'contract_type') and lower(lc.jurisdiction)=lower(btrim(contract_snapshot->>'jurisdiction')) and cv.status='approved' and cv.effective_from<=current_date and (cv.effective_until is null or cv.effective_until>=current_date);if not found then raise exception 'CLAUSE_VERSION_INVALID:%',clause_id_value;end if;clause_payload:=clause_payload||jsonb_build_array(jsonb_build_object('clause_version_id',v.id,'content_hash',v.content_hash,'version',v.version,'text',v.approved_text));end loop;
 snapshot_value:=jsonb_build_object('proposal_id',p.id,'proposal_version',p.version,'scope_hash',p.scope_hash,'commercial_hash',p.commercial_hash,'scope_snapshot',p.scope_snapshot,'proposal_lines',(select coalesce(jsonb_agg(to_jsonb(l) order by l.sort_order,l.scope_code),'[]'::jsonb) from public.proposal_lines l where l.proposal_id=p.id),'fees',jsonb_build_object('currency',p.currency,'subtotal',p.subtotal,'tax_estimate',p.tax,'total',p.total),'milestones',p.milestones_snapshot,'contract_type',btrim(contract_snapshot->>'contract_type'),'jurisdiction',btrim(contract_snapshot->>'jurisdiction'),'parties',coalesce(contract_snapshot->'parties','[]'::jsonb),'clauses',clause_payload,'commercial_terms',coalesce(contract_snapshot->'commercial_terms','{}'::jsonb));
 hash_value:=encode(extensions.digest(snapshot_value::text,'sha256'),'hex');select coalesce(max(version),0)+1 into version_value from public.contracts where organisation_id=p.organisation_id and proposal_id=p.id;
 perform set_config('conceptspaces.legal_phase','contract_generate',true);insert into public.contracts(organisation_id,proposal_id,project_id,version,status,contract_snapshot,created_by,contract_type,jurisdiction,draft_hash) values(p.organisation_id,p.id,target_project_id,version_value,'draft',snapshot_value,auth.uid(),btrim(contract_snapshot->>'contract_type'),btrim(contract_snapshot->>'jurisdiction'),hash_value) returning * into c;
 for clause_id_value in select value::uuid from jsonb_array_elements_text(contract_snapshot->'clause_version_ids') loop select cv.* into v from legal.clause_versions cv where cv.id=clause_id_value;insert into legal.contract_clause_bindings(contract_id,clause_version_id,clause_code,clause_hash,sort_order) select c.id,v.id,lc.code,v.content_hash,0 from legal.clauses lc where lc.id=v.clause_id;end loop;
 for obligation in select value from jsonb_array_elements(obligations_value) loop if nullif(btrim(obligation->>'party'),'') is null or nullif(btrim(obligation->>'obligation'),'') is null or nullif(btrim(obligation->>'clause_ref'),'') is null or nullif(btrim(obligation->>'owner_ref'),'') is null then raise exception 'obligation_party_text_clause_owner_required';end if;insert into public.contract_obligations(contract_id,party,obligation,due_at,evidence_required,status,clause_ref,trigger_ref,owner_ref,source_hash) values(c.id,btrim(obligation->>'party'),btrim(obligation->>'obligation'),nullif(obligation->>'due_at','')::timestamptz,nullif(btrim(obligation->>'evidence_required'),''),'open',btrim(obligation->>'clause_ref'),nullif(btrim(obligation->>'trigger_ref'),''),btrim(obligation->>'owner_ref'),encode(extensions.digest(obligation::text,'sha256'),'hex'));end loop;
 perform audit.append_event(p.organisation_id,target_project_id,'commercial.contract.created','contract',c.id,null,to_jsonb(c),hash_value,gen_random_uuid());return c.id;
end;$$;
revoke all on function public.create_contract_from_proposal(uuid,uuid,jsonb) from public,anon;grant execute on function public.create_contract_from_proposal(uuid,uuid,jsonb) to authenticated;

commit;
