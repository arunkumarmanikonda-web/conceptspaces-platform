begin;

-- Canonical professional-service catalogue is platform configuration, not tenant/demo data.
insert into engagement.scope_catalogue(code,name,category,description,dependencies,pricing_models,default_state,active,version)
values
 ('FEAS','Feasibility + Development Economics','Pre-design','Development feasibility, site/regulatory synthesis and development economics.','[]'::jsonb,'["fixed","milestone","hybrid"]'::jsonb,'optional',true,1),
 ('ARCH','Architecture','Design','Architecture from brief and concept through configured design/documentation stages.','[]'::jsonb,'["fixed","sqft","percent","milestone","hybrid"]'::jsonb,'included',true,1),
 ('INT','Interior Design','Design','Interior design, Design DNA, room/space packages and configured execution documentation.','[]'::jsonb,'["fixed","sqft","milestone","hybrid"]'::jsonb,'optional',true,1),
 ('STR','Structural Engineering','Engineering','Structural basis, analysis/design interfaces, documentation and governed release.','["ARCH"]'::jsonb,'["fixed","sqft","milestone","hybrid"]'::jsonb,'optional',true,1),
 ('MEPF','MEPF + Fire + ELV','Engineering','Integrated MEPF, fire/life-safety interfaces and configured specialist systems.','["ARCH"]'::jsonb,'["fixed","sqft","milestone","hybrid"]'::jsonb,'optional',true,1),
 ('BIM','BIM / CDE / Coordination','Information','OpenBIM model governance, CDE, coordination, IDS/BCF and information management.','["ARCH"]'::jsonb,'["fixed","retainer","milestone","subscription","hybrid"]'::jsonb,'optional',true,1),
 ('BOQ','QTO / BOQ / Cost Intelligence','Cost','Traceable quantity take-off, BOQ, cost planning and value engineering.','["ARCH"]'::jsonb,'["fixed","milestone","percent","hybrid"]'::jsonb,'optional',true,1),
 ('PROC','Tender + Procurement','Delivery','Tender packaging, vendor qualification, bid evaluation, award and P2P controls.','["BOQ"]'::jsonb,'["fixed","percent","milestone","retainer","hybrid"]'::jsonb,'excluded',true,1),
 ('PMC','PMC + Site Delivery','Delivery','Programme, field, QA/QC, RFI/submittal, commercial and progress controls.','[]'::jsonb,'["fixed","percent","retainer","milestone","hybrid"]'::jsonb,'excluded',true,1),
 ('TWIN','Handover + Digital Twin','Operations','Handover, Building Passport, asset/FM data and digital-twin operations.','["BIM"]'::jsonb,'["fixed","subscription","retainer","hybrid"]'::jsonb,'optional',true,1)
on conflict(code) do update set
 name=excluded.name,category=excluded.category,description=excluded.description,dependencies=excluded.dependencies,
 pricing_models=excluded.pricing_models,default_state=excluded.default_state,active=true,version=greatest(engagement.scope_catalogue.version,excluded.version),updated_at=now();

create table if not exists engagement.scope_dependency_overrides(
 id uuid primary key default gen_random_uuid(),
 intake_session_id uuid not null references engagement.intake_sessions(id) on delete cascade,
 module_code extensions.citext not null references engagement.scope_catalogue(code) on delete restrict,
 dependency_code extensions.citext not null references engagement.scope_catalogue(code) on delete restrict,
 reason text not null,
 evidence_refs jsonb not null default '[]'::jsonb,
 status text not null default 'requested' check(status in ('requested','approved','rejected','withdrawn')),
 requested_by uuid references auth.users(id),
 decided_by uuid references auth.users(id),
 decided_at timestamptz,
 created_at timestamptz not null default now(),
 unique(intake_session_id,module_code,dependency_code,status)
);

alter table engagement.scope_dependency_overrides enable row level security;
create policy scope_dependency_overrides_read on engagement.scope_dependency_overrides for select to authenticated using(
 exists(select 1 from engagement.intake_sessions s where s.id=intake_session_id and ((s.project_id is not null and project.can_access_project(s.project_id)) or core.is_internal_org_member(s.organisation_id)))
);
create policy scope_dependency_overrides_insert on engagement.scope_dependency_overrides for insert to authenticated with check(
 requested_by=auth.uid() and current_setting('conceptspaces.commercial_phase',true)='scope_override_request'
 and exists(select 1 from engagement.intake_sessions s where s.id=intake_session_id and core.has_org_role(s.organisation_id,array['super_admin','org_admin','sales','finance','project_manager']))
);
create policy scope_dependency_overrides_update on engagement.scope_dependency_overrides for update to authenticated using(
 exists(select 1 from engagement.intake_sessions s where s.id=intake_session_id and core.has_org_role(s.organisation_id,array['super_admin','org_admin','finance']))
) with check(current_setting('conceptspaces.commercial_phase',true)='scope_override_decide');
grant select,insert,update on engagement.scope_dependency_overrides to authenticated;

alter table public.proposals add column if not exists scope_intake_session_id uuid references engagement.intake_sessions(id) on delete set null;
alter table public.proposals add column if not exists scope_snapshot jsonb not null default '{}'::jsonb;
alter table public.proposals add column if not exists scope_hash text;
alter table public.proposals add column if not exists accepted_scope_hash text;
alter table public.proposals add column if not exists source_proposal_id uuid references public.proposals(id) on delete set null;
create index if not exists proposals_scope_intake_idx on public.proposals(scope_intake_session_id,version desc);
create index if not exists scope_overrides_session_idx on engagement.scope_dependency_overrides(intake_session_id,status);

create or replace function public.assert_scope_dependencies(target_intake_session_id uuid)
returns void
language plpgsql stable security invoker
set search_path=public,engagement,pg_temp
as $$
declare sel record; dep text;
begin
 for sel in
   select s.module_code::text as module_code,c.dependencies
   from engagement.scope_selections s join engagement.scope_catalogue c on c.code=s.module_code
   where s.intake_session_id=target_intake_session_id and s.state='included'
 loop
   for dep in select jsonb_array_elements_text(coalesce(sel.dependencies,'[]'::jsonb)) loop
     if not exists(select 1 from engagement.scope_selections x where x.intake_session_id=target_intake_session_id and upper(x.module_code::text)=upper(dep) and x.state='included')
        and not exists(select 1 from engagement.scope_dependency_overrides o where o.intake_session_id=target_intake_session_id and upper(o.module_code::text)=upper(sel.module_code) and upper(o.dependency_code::text)=upper(dep) and o.status='approved') then
       raise exception 'SCOPE_DEPENDENCY_MISSING:% requires %',sel.module_code,dep;
     end if;
   end loop;
 end loop;
end;$$;
revoke all on function public.assert_scope_dependencies(uuid) from public,anon;
grant execute on function public.assert_scope_dependencies(uuid) to authenticated;

create or replace function engagement.guard_scope_dependencies_deferred()
returns trigger language plpgsql security invoker set search_path=public,engagement,pg_temp as $$
begin perform public.assert_scope_dependencies(new.intake_session_id); return null; end;$$;
drop trigger if exists scope_dependencies_deferred on engagement.scope_selections;
create constraint trigger scope_dependencies_deferred after insert or update on engagement.scope_selections deferrable initially deferred for each row execute function engagement.guard_scope_dependencies_deferred();

create or replace function public.ensure_opportunity_scope_session(target_opportunity_id uuid)
returns uuid
language plpgsql security invoker
set search_path=public,engagement,core,audit,auth,pg_temp
as $$
declare o public.opportunities%rowtype; s engagement.intake_sessions%rowtype; module record;
begin
 select * into o from public.opportunities where id=target_opportunity_id;
 if not found or auth.uid() is null or not core.has_org_role(o.organisation_id,array['super_admin','org_admin','sales','finance','project_manager']) then raise exception 'opportunity_scope_authority_required'; end if;
 select * into s from engagement.intake_sessions where opportunity_id=o.id order by created_at desc limit 1;
 if found then return s.id; end if;
 insert into engagement.intake_sessions(organisation_id,opportunity_id,current_step,status,client_payload,source_channel,created_by)
 values(o.organisation_id,o.id,'scope','draft',jsonb_build_object('project_name',o.project_name),'commercial',auth.uid()) returning * into s;
 perform set_config('conceptspaces.commercial_phase','scope_selection',true);
 for module in select code,default_state from engagement.scope_catalogue where active order by code loop
   insert into engagement.scope_selections(intake_session_id,module_code,state,currency)
   values(s.id,module.code,module.default_state,o.currency) on conflict(intake_session_id,module_code) do nothing;
 end loop;
 perform audit.append_event(o.organisation_id,null,'commercial.scope.session_created','intake_session',s.id,null,to_jsonb(s),null,gen_random_uuid());
 return s.id;
end;$$;
revoke all on function public.ensure_opportunity_scope_session(uuid) from public,anon;
grant execute on function public.ensure_opportunity_scope_session(uuid) to authenticated;

-- Add a phase-guarded path for pre-project commercial scope selections.
create policy scope_selection_commercial_insert on engagement.scope_selections for insert to authenticated with check(
 current_setting('conceptspaces.commercial_phase',true)='scope_selection' and exists(select 1 from engagement.intake_sessions s where s.id=intake_session_id and core.has_org_role(s.organisation_id,array['super_admin','org_admin','sales','finance','project_manager']))
);
create policy scope_selection_commercial_update on engagement.scope_selections for update to authenticated using(
 exists(select 1 from engagement.intake_sessions s where s.id=intake_session_id and core.has_org_role(s.organisation_id,array['super_admin','org_admin','sales','finance','project_manager']))
) with check(current_setting('conceptspaces.commercial_phase',true)='scope_selection');
grant update on engagement.scope_selections to authenticated;

create or replace function public.set_scope_selection(target_intake_session_id uuid,target_module_code text,input_payload jsonb)
returns uuid
language plpgsql security invoker
set search_path=public,engagement,core,audit,auth,pg_temp
as $$
declare s engagement.intake_sessions%rowtype; c engagement.scope_catalogue%rowtype; selection engagement.scope_selections%rowtype; state_value text:=lower(btrim(input_payload->>'state')); pricing_value text:=lower(nullif(btrim(input_payload->>'pricing_model'),'')); amount_value numeric:=nullif(input_payload->>'quoted_amount','')::numeric; before_state jsonb;
begin
 select * into s from engagement.intake_sessions where id=target_intake_session_id;
 if not found or auth.uid() is null or not core.has_org_role(s.organisation_id,array['super_admin','org_admin','sales','finance','project_manager']) then raise exception 'scope_write_authority_required'; end if;
 if exists(select 1 from public.proposals p where p.scope_intake_session_id=s.id and p.status='accepted') then raise exception 'accepted_scope_is_immutable_create_new_commercial_revision'; end if;
 select * into c from engagement.scope_catalogue where upper(code::text)=upper(btrim(target_module_code)) and active;
 if not found then raise exception 'scope_module_not_found'; end if;
 if state_value not in ('included','optional','excluded') then raise exception 'scope_state_invalid'; end if;
 if state_value<>'excluded' then
   if pricing_value is null or not (c.pricing_models ? pricing_value) then raise exception 'scope_pricing_model_invalid'; end if;
   if amount_value is null or amount_value<0 then raise exception 'scope_price_required'; end if;
 else pricing_value:=null; amount_value:=null; end if;
 select to_jsonb(x) into before_state from engagement.scope_selections x where x.intake_session_id=s.id and x.module_code=c.code;
 perform set_config('conceptspaces.commercial_phase','scope_selection',true);
 insert into engagement.scope_selections(intake_session_id,module_code,state,pricing_model,quoted_amount,currency,notes)
 values(s.id,c.code,state_value,pricing_value,amount_value,upper(coalesce(nullif(btrim(input_payload->>'currency'),''),'INR')),nullif(btrim(input_payload->>'notes'),''))
 on conflict(intake_session_id,module_code) do update set state=excluded.state,pricing_model=excluded.pricing_model,quoted_amount=excluded.quoted_amount,currency=excluded.currency,notes=excluded.notes,updated_at=now()
 returning * into selection;
 perform public.assert_scope_dependencies(s.id);
 perform audit.append_event(s.organisation_id,s.project_id,'commercial.scope.selection_changed','scope_selection',selection.id,before_state,to_jsonb(selection),input_payload->>'notes',gen_random_uuid());
 return selection.id;
end;$$;
revoke all on function public.set_scope_selection(uuid,text,jsonb) from public,anon;
grant execute on function public.set_scope_selection(uuid,text,jsonb) to authenticated;

create or replace function public.request_scope_dependency_override(target_intake_session_id uuid,target_module_code text,target_dependency_code text,target_reason text,target_evidence_refs jsonb default '[]'::jsonb)
returns uuid language plpgsql security invoker set search_path=public,engagement,core,audit,auth,pg_temp as $$
declare s engagement.intake_sessions%rowtype; o engagement.scope_dependency_overrides%rowtype;
begin
 select * into s from engagement.intake_sessions where id=target_intake_session_id;
 if not found or auth.uid() is null or not core.has_org_role(s.organisation_id,array['super_admin','org_admin','sales','finance','project_manager']) then raise exception 'scope_override_authority_required'; end if;
 if nullif(btrim(target_reason),'') is null or jsonb_typeof(coalesce(target_evidence_refs,'[]'::jsonb))<>'array' or jsonb_array_length(coalesce(target_evidence_refs,'[]'::jsonb))=0 then raise exception 'scope_override_reason_evidence_required'; end if;
 if not exists(select 1 from engagement.scope_catalogue c where upper(c.code::text)=upper(btrim(target_module_code)) and c.dependencies ? upper(btrim(target_dependency_code))) then raise exception 'scope_dependency_pair_invalid'; end if;
 perform set_config('conceptspaces.commercial_phase','scope_override_request',true);
 insert into engagement.scope_dependency_overrides(intake_session_id,module_code,dependency_code,reason,evidence_refs,status,requested_by)
 values(s.id,upper(btrim(target_module_code)),upper(btrim(target_dependency_code)),btrim(target_reason),target_evidence_refs,'requested',auth.uid()) returning * into o;
 perform audit.append_event(s.organisation_id,s.project_id,'commercial.scope.override_requested','scope_dependency_override',o.id,null,to_jsonb(o),target_reason,gen_random_uuid()); return o.id;
end;$$;
revoke all on function public.request_scope_dependency_override(uuid,text,text,text,jsonb) from public,anon; grant execute on function public.request_scope_dependency_override(uuid,text,text,text,jsonb) to authenticated;

create or replace function public.decide_scope_dependency_override(target_override_id uuid,target_decision text,target_reason text)
returns text language plpgsql security invoker set search_path=public,engagement,core,audit,auth,pg_temp as $$
declare o engagement.scope_dependency_overrides%rowtype; s engagement.intake_sessions%rowtype; decision_value text:=lower(btrim(target_decision)); before_state jsonb;
begin
 select * into o from engagement.scope_dependency_overrides where id=target_override_id for update; if not found then raise exception 'scope_override_not_found'; end if;
 select * into s from engagement.intake_sessions where id=o.intake_session_id;
 if auth.uid() is null or not core.has_org_role(s.organisation_id,array['super_admin','org_admin','finance']) then raise exception 'scope_override_decision_authority_required'; end if;
 if o.status<>'requested' or decision_value not in ('approved','rejected','withdrawn') then raise exception 'scope_override_decision_invalid'; end if;
 if decision_value='approved' and o.requested_by=auth.uid() then raise exception 'scope_override_independent_approval_required'; end if;
 if nullif(btrim(target_reason),'') is null then raise exception 'scope_override_decision_reason_required'; end if;
 before_state:=to_jsonb(o); perform set_config('conceptspaces.commercial_phase','scope_override_decide',true);
 update engagement.scope_dependency_overrides set status=decision_value,decided_by=auth.uid(),decided_at=now() where id=o.id returning * into o;
 perform audit.append_event(s.organisation_id,s.project_id,'commercial.scope.override_'||decision_value,'scope_dependency_override',o.id,before_state,to_jsonb(o),target_reason,gen_random_uuid()); return o.status;
end;$$;
revoke all on function public.decide_scope_dependency_override(uuid,text,text) from public,anon; grant execute on function public.decide_scope_dependency_override(uuid,text,text) to authenticated;

create or replace function public.create_scope_bound_proposal(target_opportunity_id uuid,target_intake_session_id uuid,input_payload jsonb)
returns uuid
language plpgsql security invoker
set search_path=public,engagement,core,audit,extensions,auth,pg_temp
as $$
declare o public.opportunities%rowtype; s engagement.intake_sessions%rowtype; p public.proposals%rowtype; sel record; version_value int; subtotal_value numeric:=0; tax_value numeric:=coalesce(nullif(input_payload->>'tax','')::numeric,0); snapshot jsonb; scope_hash_value text; source_id uuid:=nullif(input_payload->>'source_proposal_id','')::uuid;
begin
 select * into o from public.opportunities where id=target_opportunity_id;
 select * into s from engagement.intake_sessions where id=target_intake_session_id and opportunity_id=o.id;
 if not found or auth.uid() is null or not core.has_org_role(o.organisation_id,array['super_admin','org_admin','sales','finance']) then raise exception 'proposal_scope_authority_required'; end if;
 perform public.assert_scope_dependencies(s.id);
 if not exists(select 1 from engagement.scope_selections x where x.intake_session_id=s.id and x.state='included') then raise exception 'proposal_included_scope_required'; end if;
 if exists(select 1 from engagement.scope_selections x where x.intake_session_id=s.id and x.state<>'excluded' and (x.pricing_model is null or x.quoted_amount is null or x.quoted_amount<0)) then raise exception 'PRICE_RECALC_REQUIRED'; end if;
 if tax_value<0 then raise exception 'proposal_tax_negative_not_allowed'; end if;
 snapshot:=jsonb_build_object('intake_session_id',s.id,'catalogue_version',(select coalesce(max(version),1) from engagement.scope_catalogue),'selections',coalesce((select jsonb_agg(jsonb_build_object('module_code',x.module_code::text,'name',c.name,'category',c.category,'state',x.state,'pricing_model',x.pricing_model,'quoted_amount',x.quoted_amount,'currency',x.currency,'notes',x.notes,'dependencies',c.dependencies) order by x.module_code::text) from engagement.scope_selections x join engagement.scope_catalogue c on c.code=x.module_code where x.intake_session_id=s.id),'[]'::jsonb),'approved_dependency_overrides',coalesce((select jsonb_agg(jsonb_build_object('module_code',d.module_code::text,'dependency_code',d.dependency_code::text,'reason',d.reason,'id',d.id) order by d.module_code::text,d.dependency_code::text) from engagement.scope_dependency_overrides d where d.intake_session_id=s.id and d.status='approved'),'[]'::jsonb));
 scope_hash_value:=encode(extensions.digest(snapshot::text,'sha256'),'hex');
 select coalesce(max(version),0)+1 into version_value from public.proposals where opportunity_id=o.id;
 insert into public.proposals(organisation_id,opportunity_id,version,status,currency,subtotal,tax,total,valid_until,commercial_notes,created_by,scope_intake_session_id,scope_snapshot,scope_hash,source_proposal_id)
 values(o.organisation_id,o.id,version_value,'draft',upper(coalesce(nullif(btrim(input_payload->>'currency'),''),o.currency)),0,tax_value,0,nullif(input_payload->>'valid_until','')::date,coalesce(input_payload->'commercial_notes','[]'::jsonb),auth.uid(),s.id,snapshot,scope_hash_value,source_id) returning * into p;
 for sel in select x.*,c.name from engagement.scope_selections x join engagement.scope_catalogue c on c.code=x.module_code where x.intake_session_id=s.id and x.state in ('included','optional') order by x.module_code loop
   insert into public.proposal_lines(proposal_id,title,scope_code,pricing_model,quantity,rate,amount,optional,sort_order)
   values(p.id,sel.name,sel.module_code::text,sel.pricing_model,1,sel.quoted_amount,sel.quoted_amount,sel.state='optional',0);
   if sel.state='included' then subtotal_value:=subtotal_value+coalesce(sel.quoted_amount,0); end if;
 end loop;
 update public.proposals set subtotal=subtotal_value,total=subtotal_value+tax_value,updated_at=now() where id=p.id returning * into p;
 insert into engagement.proposal_negotiation_events(proposal_id,version,party,event_type,amount,currency,scope_delta,note,actor_user_id) values(p.id,p.version,'Concept Spaces','proposal_created',p.total,p.currency,p.scope_snapshot,'Scope-bound proposal revision created',auth.uid());
 update public.opportunities set stage='proposal',scope_modules=(select coalesce(jsonb_agg(x.module_code::text order by x.module_code::text),'[]'::jsonb) from engagement.scope_selections x where x.intake_session_id=s.id and x.state='included'),updated_at=now() where id=o.id;
 perform audit.append_event(o.organisation_id,s.project_id,'commercial.proposal.created','proposal',p.id,null,to_jsonb(p),scope_hash_value,gen_random_uuid()); return p.id;
end;$$;
revoke all on function public.create_scope_bound_proposal(uuid,uuid,jsonb) from public,anon; grant execute on function public.create_scope_bound_proposal(uuid,uuid,jsonb) to authenticated;

create or replace function public.guard_accepted_proposal_immutable()
returns trigger language plpgsql security invoker set search_path=public,pg_temp as $$
begin if old.status='accepted' then raise exception 'accepted_proposal_immutable_create_new_revision'; end if; return new; end;$$;
drop trigger if exists accepted_proposal_immutable on public.proposals;
create trigger accepted_proposal_immutable before update on public.proposals for each row execute function public.guard_accepted_proposal_immutable();

create or replace function public.submit_proposal_for_review(target_proposal_id uuid)
returns void language plpgsql security invoker set search_path=public,engagement,core,audit,auth,pg_temp as $$
declare p public.proposals%rowtype; before_state jsonb;
begin select * into p from public.proposals where id=target_proposal_id for update; if not found then raise exception 'proposal_not_found'; end if; if p.created_by<>auth.uid() and not core.has_org_role(p.organisation_id,array['super_admin','org_admin','sales','finance']) then raise exception 'commercial_write_authority_required'; end if; if p.status<>'draft' then raise exception 'proposal_not_draft'; end if; if p.scope_hash is null or p.scope_snapshot='{}'::jsonb then raise exception 'scope_bound_proposal_required'; end if; before_state:=to_jsonb(p); update public.proposals set status='internal_review',submitted_at=now(),updated_at=now() where id=p.id returning * into p; insert into engagement.proposal_negotiation_events(proposal_id,version,party,event_type,amount,currency,note,actor_user_id) values(p.id,p.version,'Concept Spaces','internal_review',p.total,p.currency,'Submitted for independent commercial review',auth.uid()); perform audit.append_event(p.organisation_id,null,'commercial.proposal.submitted','proposal',p.id,before_state,to_jsonb(p),p.scope_hash,gen_random_uuid()); end;$$;

create or replace function public.approve_and_send_proposal(target_proposal_id uuid,review_note text default null)
returns void language plpgsql security invoker set search_path=public,engagement,core,audit,auth,pg_temp as $$
declare p public.proposals%rowtype; before_state jsonb;
begin select * into p from public.proposals where id=target_proposal_id for update; if not found then raise exception 'proposal_not_found'; end if; if not core.has_org_role(p.organisation_id,array['super_admin','org_admin','finance']) then raise exception 'commercial_checker_authority_required'; end if; if p.created_by=auth.uid() then raise exception 'maker_cannot_check_own_proposal'; end if; if p.status<>'internal_review' then raise exception 'proposal_not_awaiting_internal_review'; end if; before_state:=to_jsonb(p); update public.proposals set status='sent',approved_by=auth.uid(),approved_at=now(),updated_at=now(),commercial_notes=commercial_notes||jsonb_build_array(jsonb_build_object('type','internal_review','note',review_note,'by',auth.uid(),'at',now())) where id=p.id returning * into p; insert into engagement.proposal_negotiation_events(proposal_id,version,party,event_type,amount,currency,note,actor_user_id) values(p.id,p.version,'Concept Spaces','proposal_sent',p.total,p.currency,review_note,auth.uid()); perform audit.append_event(p.organisation_id,null,'commercial.proposal.approved_sent','proposal',p.id,before_state,to_jsonb(p),review_note,gen_random_uuid()); end;$$;

create or replace function public.record_proposal_client_decision(target_proposal_id uuid,decision text,evidence_reference text,client_counter_offer numeric default null)
returns void language plpgsql security invoker set search_path=public,engagement,core,audit,auth,pg_temp as $$
declare p public.proposals%rowtype; before_state jsonb; status_value text:=lower(btrim(decision)); counter_value numeric:=client_counter_offer;
begin select * into p from public.proposals where id=target_proposal_id for update; if not found then raise exception 'proposal_not_found'; end if; if not core.has_org_role(p.organisation_id,array['super_admin','org_admin','sales']) then raise exception 'client_decision_recording_authority_required'; end if; if nullif(btrim(evidence_reference),'') is null then raise exception 'client_decision_evidence_required'; end if; if status_value not in ('accepted','countered','rejected') then raise exception 'unsupported_client_decision'; end if; if p.status not in ('sent','countered') then raise exception 'proposal_not_client_decision_eligible'; end if; if p.valid_until is not null and current_date>p.valid_until then raise exception 'PROPOSAL_EXPIRED'; end if; if status_value='countered' and (counter_value is null or counter_value<0) then raise exception 'counter_offer_required'; end if; before_state:=to_jsonb(p); update public.proposals set status=status_value,client_counter_offer=case when status_value='countered' then counter_value else null end,accepted_scope_hash=case when status_value='accepted' then scope_hash else accepted_scope_hash end,commercial_notes=commercial_notes||jsonb_build_array(jsonb_build_object('type','client_decision','decision',status_value,'evidence_reference',evidence_reference,'recorded_by',auth.uid(),'at',now())),updated_at=now() where id=p.id returning * into p; insert into engagement.proposal_negotiation_events(proposal_id,version,party,event_type,amount,currency,scope_delta,note,actor_user_id) values(p.id,p.version,'Client',case when status_value='countered' then 'counter_offer' else status_value end,case when status_value='countered' then counter_value else p.total end,p.currency,p.scope_snapshot,evidence_reference,auth.uid()); update public.opportunities set stage=case when status_value='accepted' then 'contracting' when status_value='rejected' then 'lost' else 'negotiation' end,updated_at=now() where id=p.opportunity_id; perform audit.append_event(p.organisation_id,null,'commercial.proposal.client_decision','proposal',p.id,before_state,to_jsonb(p),evidence_reference,gen_random_uuid()); end;$$;

create or replace function public.list_scope_commercial_workspace(target_organisation_id uuid)
returns jsonb language plpgsql stable security invoker set search_path=public,engagement,project,core,auth,pg_temp as $$
begin
 if auth.uid() is null or not core.is_internal_org_member(target_organisation_id) then raise exception 'organisation_access_required'; end if;
 return jsonb_build_object(
  'catalogue',coalesce((select jsonb_agg(to_jsonb(c) order by c.category,c.code::text) from engagement.scope_catalogue c where c.active),'[]'::jsonb),
  'opportunities',coalesce((select jsonb_agg(to_jsonb(o) order by o.created_at desc) from public.opportunities o where o.organisation_id=target_organisation_id),'[]'::jsonb),
  'intake_sessions',coalesce((select jsonb_agg(to_jsonb(s) order by s.created_at desc) from engagement.intake_sessions s where s.organisation_id=target_organisation_id and s.opportunity_id is not null),'[]'::jsonb),
  'selections',coalesce((select jsonb_agg(to_jsonb(x) order by x.intake_session_id,x.module_code::text) from engagement.scope_selections x join engagement.intake_sessions s on s.id=x.intake_session_id where s.organisation_id=target_organisation_id),'[]'::jsonb),
  'overrides',coalesce((select jsonb_agg(to_jsonb(d) order by d.created_at desc) from engagement.scope_dependency_overrides d join engagement.intake_sessions s on s.id=d.intake_session_id where s.organisation_id=target_organisation_id),'[]'::jsonb),
  'proposals',coalesce((select jsonb_agg(to_jsonb(p) order by p.opportunity_id,p.version desc) from public.proposals p where p.organisation_id=target_organisation_id),'[]'::jsonb),
  'proposal_lines',coalesce((select jsonb_agg(to_jsonb(l) order by l.proposal_id,l.sort_order,l.scope_code) from public.proposal_lines l join public.proposals p on p.id=l.proposal_id where p.organisation_id=target_organisation_id),'[]'::jsonb),
  'negotiation_events',coalesce((select jsonb_agg(to_jsonb(e) order by e.created_at desc) from engagement.proposal_negotiation_events e join public.proposals p on p.id=e.proposal_id where p.organisation_id=target_organisation_id),'[]'::jsonb),
  'projects',coalesce((select jsonb_agg(jsonb_build_object('id',p.id,'code',p.code::text,'name',p.name,'stage',p.stage,'status',p.status) order by p.created_at desc) from project.projects p where p.organisation_id=target_organisation_id),'[]'::jsonb)
 );
end;$$;
revoke all on function public.list_scope_commercial_workspace(uuid) from public,anon; grant execute on function public.list_scope_commercial_workspace(uuid) to authenticated;

commit;
