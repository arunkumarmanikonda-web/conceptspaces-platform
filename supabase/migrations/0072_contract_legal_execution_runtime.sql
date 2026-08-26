begin;

create schema if not exists legal;
grant usage on schema legal to authenticated;

alter table public.contracts add column if not exists parent_contract_id uuid references public.contracts(id) on delete set null;
alter table public.contracts add column if not exists contract_type text;
alter table public.contracts add column if not exists jurisdiction text;
alter table public.contracts add column if not exists draft_hash text;
alter table public.contracts add column if not exists execution_hash text;
alter table public.contracts add column if not exists executed_by uuid references auth.users(id);
alter table public.contracts add column if not exists executed_at timestamptz;
alter table public.contracts add column if not exists amendment_reason text;

alter table public.contracts drop constraint if exists contracts_status_check;
alter table public.contracts add constraint contracts_status_check check(status in ('draft','negotiation','signature_pending','active','suspended','completed','terminated','superseded'));

alter table public.contract_obligations add column if not exists clause_ref text;
alter table public.contract_obligations add column if not exists trigger_ref text;
alter table public.contract_obligations add column if not exists owner_ref text;
alter table public.contract_obligations add column if not exists source_hash text;
alter table public.contract_obligations add column if not exists waiver_reason text;
alter table public.contract_obligations add column if not exists waived_by uuid references auth.users(id);
alter table public.contract_obligations add column if not exists waived_at timestamptz;

create table if not exists legal.clauses(
 id uuid primary key default gen_random_uuid(),
 organisation_id uuid not null references core.organisations(id) on delete cascade,
 code text not null,
 category text not null,
 jurisdiction text not null,
 contract_type text not null,
 risk text not null default 'standard' check(risk in ('standard','elevated','high','restricted')),
 owner_role text not null default 'legal',
 active boolean not null default true,
 created_by uuid references auth.users(id),
 created_at timestamptz not null default now(),
 updated_at timestamptz not null default now(),
 unique(organisation_id,code)
);
create table if not exists legal.clause_versions(
 id uuid primary key default gen_random_uuid(),
 clause_id uuid not null references legal.clauses(id) on delete cascade,
 version integer not null,
 approved_text text not null,
 alternative_positions jsonb not null default '[]'::jsonb,
 effective_from date not null,
 effective_until date,
 status text not null default 'draft' check(status in ('draft','approved','superseded','withdrawn')),
 content_hash text not null,
 created_by uuid references auth.users(id),
 approved_by uuid references auth.users(id),
 approved_at timestamptz,
 created_at timestamptz not null default now(),
 unique(clause_id,version)
);
create table if not exists legal.contract_clause_bindings(
 id uuid primary key default gen_random_uuid(),
 contract_id uuid not null references public.contracts(id) on delete cascade,
 clause_version_id uuid not null references legal.clause_versions(id) on delete restrict,
 clause_code text not null,
 clause_hash text not null,
 sort_order integer not null default 0,
 created_at timestamptz not null default now(),
 unique(contract_id,clause_version_id)
);
create table if not exists legal.redlines(
 id uuid primary key default gen_random_uuid(),
 contract_id uuid not null references public.contracts(id) on delete cascade,
 clause_version_id uuid references legal.clause_versions(id) on delete set null,
 party text not null,
 proposed_text text not null,
 note text,
 evidence_refs jsonb not null default '[]'::jsonb,
 status text not null default 'open' check(status in ('open','accepted','rejected','countered','withdrawn')),
 created_by uuid references auth.users(id),
 decided_by uuid references auth.users(id),
 decided_at timestamptz,
 decision_note text,
 created_at timestamptz not null default now()
);
create table if not exists legal.signature_envelopes(
 id uuid primary key default gen_random_uuid(),
 contract_id uuid not null references public.contracts(id) on delete cascade,
 provider text not null,
 provider_envelope_id text,
 signatories jsonb not null,
 signing_order jsonb not null default '[]'::jsonb,
 status text not null default 'draft' check(status in ('draft','sent','completed','failed','cancelled','expired')),
 final_document_hash text,
 evidence_refs jsonb not null default '[]'::jsonb,
 created_by uuid references auth.users(id),
 sent_at timestamptz,
 completed_at timestamptz,
 updated_at timestamptz not null default now(),
 created_at timestamptz not null default now()
);
create table if not exists legal.contract_state_events(
 id uuid primary key default gen_random_uuid(),
 contract_id uuid not null references public.contracts(id) on delete cascade,
 from_status text,
 to_status text not null,
 evidence_reference text,
 actor_id uuid references auth.users(id),
 created_at timestamptz not null default now()
);

alter table legal.clauses enable row level security;
alter table legal.clause_versions enable row level security;
alter table legal.contract_clause_bindings enable row level security;
alter table legal.redlines enable row level security;
alter table legal.signature_envelopes enable row level security;
alter table legal.contract_state_events enable row level security;

create policy legal_clauses_read on legal.clauses for select to authenticated using(core.is_internal_org_member(organisation_id));
create policy legal_clauses_write on legal.clauses for all to authenticated using(core.has_org_role(organisation_id,array['super_admin','org_admin','finance','legal'])) with check(core.has_org_role(organisation_id,array['super_admin','org_admin','finance','legal']) and current_setting('conceptspaces.legal_phase',true)='clause');
create policy clause_versions_read on legal.clause_versions for select to authenticated using(exists(select 1 from legal.clauses c where c.id=clause_id and core.is_internal_org_member(c.organisation_id)));
create policy clause_versions_insert on legal.clause_versions for insert to authenticated with check(current_setting('conceptspaces.legal_phase',true)='clause_version' and exists(select 1 from legal.clauses c where c.id=clause_id and core.has_org_role(c.organisation_id,array['super_admin','org_admin','finance','legal'])));
create policy clause_versions_update on legal.clause_versions for update to authenticated using(exists(select 1 from legal.clauses c where c.id=clause_id and core.has_org_role(c.organisation_id,array['super_admin','org_admin','finance','legal']))) with check(current_setting('conceptspaces.legal_phase',true)='clause_approve');
create policy contract_clause_bindings_read on legal.contract_clause_bindings for select to authenticated using(exists(select 1 from public.contracts c where c.id=contract_id and core.is_internal_org_member(c.organisation_id)));
create policy contract_clause_bindings_insert on legal.contract_clause_bindings for insert to authenticated with check(current_setting('conceptspaces.legal_phase',true)='contract_generate' and exists(select 1 from public.contracts c where c.id=contract_id and core.has_org_role(c.organisation_id,array['super_admin','org_admin','finance','legal'])));
create policy redlines_read on legal.redlines for select to authenticated using(exists(select 1 from public.contracts c where c.id=contract_id and core.is_internal_org_member(c.organisation_id)));
create policy redlines_insert on legal.redlines for insert to authenticated with check(current_setting('conceptspaces.legal_phase',true)='redline' and exists(select 1 from public.contracts c where c.id=contract_id and core.has_org_role(c.organisation_id,array['super_admin','org_admin','finance','legal','sales'])));
create policy redlines_update on legal.redlines for update to authenticated using(exists(select 1 from public.contracts c where c.id=contract_id and core.has_org_role(c.organisation_id,array['super_admin','org_admin','finance','legal']))) with check(current_setting('conceptspaces.legal_phase',true)='redline_decide');
create policy signatures_read on legal.signature_envelopes for select to authenticated using(exists(select 1 from public.contracts c where c.id=contract_id and core.is_internal_org_member(c.organisation_id)));
create policy signatures_write on legal.signature_envelopes for all to authenticated using(exists(select 1 from public.contracts c where c.id=contract_id and core.has_org_role(c.organisation_id,array['super_admin','org_admin','finance','legal']))) with check(current_setting('conceptspaces.legal_phase',true)='signature');
create policy contract_state_events_read on legal.contract_state_events for select to authenticated using(exists(select 1 from public.contracts c where c.id=contract_id and core.is_internal_org_member(c.organisation_id)));
create policy contract_state_events_insert on legal.contract_state_events for insert to authenticated with check(current_setting('conceptspaces.legal_phase',true)='contract_state' and exists(select 1 from public.contracts c where c.id=contract_id and core.has_org_role(c.organisation_id,array['super_admin','org_admin','finance','legal'])));

grant select,insert,update on legal.clauses,legal.clause_versions,legal.redlines,legal.signature_envelopes to authenticated;
grant select,insert on legal.contract_clause_bindings,legal.contract_state_events to authenticated;

create index if not exists clause_versions_effective_idx on legal.clause_versions(clause_id,status,effective_from,effective_until);
create index if not exists redlines_contract_status_idx on legal.redlines(contract_id,status);
create index if not exists signature_envelopes_contract_idx on legal.signature_envelopes(contract_id,created_at desc);
create index if not exists contract_parent_idx on public.contracts(parent_contract_id,version desc);

create or replace function public.create_legal_clause(target_organisation_id uuid,input_payload jsonb)
returns uuid language plpgsql security invoker set search_path=public,legal,core,audit,auth,pg_temp as $$
declare c legal.clauses%rowtype;
begin if auth.uid() is null or not core.has_org_role(target_organisation_id,array['super_admin','org_admin','finance','legal']) then raise exception 'legal_clause_authority_required'; end if; if nullif(btrim(input_payload->>'code'),'') is null or nullif(btrim(input_payload->>'category'),'') is null or nullif(btrim(input_payload->>'jurisdiction'),'') is null or nullif(btrim(input_payload->>'contract_type'),'') is null then raise exception 'clause_identity_required'; end if; perform set_config('conceptspaces.legal_phase','clause',true); insert into legal.clauses(organisation_id,code,category,jurisdiction,contract_type,risk,owner_role,created_by) values(target_organisation_id,upper(btrim(input_payload->>'code')),btrim(input_payload->>'category'),btrim(input_payload->>'jurisdiction'),btrim(input_payload->>'contract_type'),coalesce(nullif(lower(btrim(input_payload->>'risk')),''),'standard'),coalesce(nullif(btrim(input_payload->>'owner_role'),''),'legal'),auth.uid()) returning * into c; perform audit.append_event(target_organisation_id,null,'legal.clause.created','clause',c.id,null,to_jsonb(c),null,gen_random_uuid()); return c.id; end;$$;
revoke all on function public.create_legal_clause(uuid,jsonb) from public,anon; grant execute on function public.create_legal_clause(uuid,jsonb) to authenticated;

create or replace function public.create_legal_clause_version(target_clause_id uuid,input_payload jsonb)
returns uuid language plpgsql security invoker set search_path=public,legal,core,audit,extensions,auth,pg_temp as $$
declare c legal.clauses%rowtype; v legal.clause_versions%rowtype; version_value int; hash_value text;
begin select * into c from legal.clauses where id=target_clause_id; if not found or auth.uid() is null or not core.has_org_role(c.organisation_id,array['super_admin','org_admin','finance','legal']) then raise exception 'legal_clause_authority_required'; end if; if nullif(btrim(input_payload->>'approved_text'),'') is null or nullif(input_payload->>'effective_from','') is null then raise exception 'clause_text_effective_date_required'; end if; select coalesce(max(version),0)+1 into version_value from legal.clause_versions where clause_id=c.id; hash_value:=encode(extensions.digest(jsonb_build_object('clause_id',c.id,'version',version_value,'text',btrim(input_payload->>'approved_text'),'alternatives',coalesce(input_payload->'alternative_positions','[]'::jsonb),'effective_from',input_payload->>'effective_from','effective_until',input_payload->>'effective_until')::text,'sha256'),'hex'); perform set_config('conceptspaces.legal_phase','clause_version',true); insert into legal.clause_versions(clause_id,version,approved_text,alternative_positions,effective_from,effective_until,status,content_hash,created_by) values(c.id,version_value,btrim(input_payload->>'approved_text'),coalesce(input_payload->'alternative_positions','[]'::jsonb),(input_payload->>'effective_from')::date,nullif(input_payload->>'effective_until','')::date,'draft',hash_value,auth.uid()) returning * into v; perform audit.append_event(c.organisation_id,null,'legal.clause.version_created','clause_version',v.id,null,to_jsonb(v),hash_value,gen_random_uuid()); return v.id; end;$$;
revoke all on function public.create_legal_clause_version(uuid,jsonb) from public,anon; grant execute on function public.create_legal_clause_version(uuid,jsonb) to authenticated;

create or replace function public.approve_legal_clause_version(target_version_id uuid,target_reason text)
returns text language plpgsql security invoker set search_path=public,legal,core,audit,auth,pg_temp as $$
declare v legal.clause_versions%rowtype; c legal.clauses%rowtype; before_state jsonb;
begin select * into v from legal.clause_versions where id=target_version_id for update; if not found then raise exception 'clause_version_not_found'; end if; select * into c from legal.clauses where id=v.clause_id; if auth.uid() is null or not core.has_org_role(c.organisation_id,array['super_admin','org_admin','finance','legal']) then raise exception 'clause_approval_authority_required'; end if; if v.status<>'draft' then raise exception 'clause_version_not_draft'; end if; if v.created_by=auth.uid() then raise exception 'clause_maker_cannot_approve_own_version'; end if; if v.effective_until is not null and v.effective_until<v.effective_from then raise exception 'clause_effective_dates_invalid'; end if; before_state:=to_jsonb(v); perform set_config('conceptspaces.legal_phase','clause_approve',true); update legal.clause_versions set status='superseded' where clause_id=v.clause_id and status='approved'; update legal.clause_versions set status='approved',approved_by=auth.uid(),approved_at=now() where id=v.id returning * into v; perform audit.append_event(c.organisation_id,null,'legal.clause.version_approved','clause_version',v.id,before_state,to_jsonb(v),target_reason,gen_random_uuid()); return v.status; end;$$;
revoke all on function public.approve_legal_clause_version(uuid,text) from public,anon; grant execute on function public.approve_legal_clause_version(uuid,text) to authenticated;

create or replace function public.create_contract_from_proposal(target_proposal_id uuid,target_project_id uuid default null,contract_snapshot jsonb default '{}'::jsonb)
returns uuid language plpgsql security invoker set search_path=public,legal,core,project,audit,extensions,auth,pg_temp as $$
declare p public.proposals%rowtype; c public.contracts%rowtype; clause_id_value uuid; v legal.clause_versions%rowtype; clause_payload jsonb:='[]'::jsonb; obligations_value jsonb:=coalesce(contract_snapshot->'obligations','[]'::jsonb); obligation jsonb; snapshot_value jsonb; hash_value text; version_value int;
begin select * into p from public.proposals where id=target_proposal_id; if not found or p.status<>'accepted' or p.accepted_scope_hash is distinct from p.scope_hash then raise exception 'proposal_must_be_client_accepted'; end if; if auth.uid() is null or not core.has_org_role(p.organisation_id,array['super_admin','org_admin','finance','legal']) then raise exception 'contract_creation_authority_required'; end if; if target_project_id is not null and not project.can_access_project(target_project_id) then raise exception 'project_access_required'; end if; if nullif(btrim(contract_snapshot->>'contract_type'),'') is null or nullif(btrim(contract_snapshot->>'jurisdiction'),'') is null then raise exception 'contract_type_and_jurisdiction_required'; end if; if jsonb_typeof(coalesce(contract_snapshot->'clause_version_ids','[]'::jsonb))<>'array' or jsonb_array_length(coalesce(contract_snapshot->'clause_version_ids','[]'::jsonb))=0 then raise exception 'approved_clause_set_required'; end if; if jsonb_typeof(obligations_value)<>'array' or jsonb_array_length(obligations_value)=0 then raise exception 'contract_obligations_required'; end if;
 for clause_id_value in select value::uuid from jsonb_array_elements_text(contract_snapshot->'clause_version_ids') loop select cv.* into v from legal.clause_versions cv join legal.clauses lc on lc.id=cv.clause_id where cv.id=clause_id_value and lc.organisation_id=p.organisation_id and lc.contract_type=btrim(contract_snapshot->>'contract_type') and lower(lc.jurisdiction)=lower(btrim(contract_snapshot->>'jurisdiction')) and cv.status='approved' and cv.effective_from<=current_date and (cv.effective_until is null or cv.effective_until>=current_date); if not found then raise exception 'CLAUSE_VERSION_INVALID:%',clause_id_value; end if; clause_payload:=clause_payload||jsonb_build_array(jsonb_build_object('clause_version_id',v.id,'content_hash',v.content_hash,'version',v.version,'text',v.approved_text)); end loop;
 snapshot_value:=jsonb_build_object('proposal_id',p.id,'proposal_version',p.version,'scope_hash',p.scope_hash,'scope_snapshot',p.scope_snapshot,'proposal_lines',(select coalesce(jsonb_agg(to_jsonb(l) order by l.sort_order,l.scope_code),'[]'::jsonb) from public.proposal_lines l where l.proposal_id=p.id),'fees',jsonb_build_object('currency',p.currency,'subtotal',p.subtotal,'tax_estimate',p.tax,'total',p.total),'contract_type',btrim(contract_snapshot->>'contract_type'),'jurisdiction',btrim(contract_snapshot->>'jurisdiction'),'parties',coalesce(contract_snapshot->'parties','[]'::jsonb),'milestones',coalesce(contract_snapshot->'milestones','[]'::jsonb),'clauses',clause_payload,'commercial_terms',coalesce(contract_snapshot->'commercial_terms','{}'::jsonb)); hash_value:=encode(extensions.digest(snapshot_value::text,'sha256'),'hex'); select coalesce(max(version),0)+1 into version_value from public.contracts where organisation_id=p.organisation_id and proposal_id=p.id; perform set_config('conceptspaces.legal_phase','contract_generate',true); insert into public.contracts(organisation_id,proposal_id,project_id,version,status,contract_snapshot,created_by,contract_type,jurisdiction,draft_hash) values(p.organisation_id,p.id,target_project_id,version_value,'draft',snapshot_value,auth.uid(),btrim(contract_snapshot->>'contract_type'),btrim(contract_snapshot->>'jurisdiction'),hash_value) returning * into c;
 for clause_id_value in select value::uuid from jsonb_array_elements_text(contract_snapshot->'clause_version_ids') loop select cv.* into v from legal.clause_versions cv where cv.id=clause_id_value; insert into legal.contract_clause_bindings(contract_id,clause_version_id,clause_code,clause_hash,sort_order) select c.id,v.id,lc.code,v.content_hash,0 from legal.clauses lc where lc.id=v.clause_id; end loop;
 for obligation in select value from jsonb_array_elements(obligations_value) loop if nullif(btrim(obligation->>'party'),'') is null or nullif(btrim(obligation->>'obligation'),'') is null or nullif(btrim(obligation->>'clause_ref'),'') is null or nullif(btrim(obligation->>'owner_ref'),'') is null then raise exception 'obligation_party_text_clause_owner_required'; end if; insert into public.contract_obligations(contract_id,party,obligation,due_at,evidence_required,status,clause_ref,trigger_ref,owner_ref,source_hash) values(c.id,btrim(obligation->>'party'),btrim(obligation->>'obligation'),nullif(obligation->>'due_at','')::timestamptz,nullif(btrim(obligation->>'evidence_required'),''),'open',btrim(obligation->>'clause_ref'),nullif(btrim(obligation->>'trigger_ref'),''),btrim(obligation->>'owner_ref'),encode(extensions.digest(obligation::text,'sha256'),'hex')); end loop;
 perform audit.append_event(p.organisation_id,target_project_id,'commercial.contract.created','contract',c.id,null,to_jsonb(c),hash_value,gen_random_uuid()); return c.id; end;$$;

create or replace function public.record_contract_redline(target_contract_id uuid,input_payload jsonb)
returns uuid language plpgsql security invoker set search_path=public,legal,core,audit,auth,pg_temp as $$
declare c public.contracts%rowtype; r legal.redlines%rowtype; clause_version uuid:=nullif(input_payload->>'clause_version_id','')::uuid;
begin select * into c from public.contracts where id=target_contract_id; if not found or auth.uid() is null or not core.has_org_role(c.organisation_id,array['super_admin','org_admin','finance','legal','sales']) then raise exception 'redline_authority_required'; end if; if c.status not in ('draft','negotiation') then raise exception 'contract_not_redlineable'; end if; if clause_version is not null and not exists(select 1 from legal.contract_clause_bindings b where b.contract_id=c.id and b.clause_version_id=clause_version) then raise exception 'redline_clause_not_in_contract'; end if; if nullif(btrim(input_payload->>'party'),'') is null or nullif(btrim(input_payload->>'proposed_text'),'') is null then raise exception 'redline_party_text_required'; end if; perform set_config('conceptspaces.legal_phase','redline',true); insert into legal.redlines(contract_id,clause_version_id,party,proposed_text,note,evidence_refs,status,created_by) values(c.id,clause_version,btrim(input_payload->>'party'),btrim(input_payload->>'proposed_text'),nullif(btrim(input_payload->>'note'),''),coalesce(input_payload->'evidence_refs','[]'::jsonb),'open',auth.uid()) returning * into r; perform audit.append_event(c.organisation_id,c.project_id,'legal.redline.created','redline',r.id,null,to_jsonb(r),null,gen_random_uuid()); return r.id; end;$$;
revoke all on function public.record_contract_redline(uuid,jsonb) from public,anon; grant execute on function public.record_contract_redline(uuid,jsonb) to authenticated;

create or replace function public.decide_contract_redline(target_redline_id uuid,target_decision text,target_note text)
returns text language plpgsql security invoker set search_path=public,legal,core,audit,auth,pg_temp as $$
declare r legal.redlines%rowtype; c public.contracts%rowtype; decision_value text:=lower(btrim(target_decision)); before_state jsonb;
begin select * into r from legal.redlines where id=target_redline_id for update; if not found then raise exception 'redline_not_found'; end if; select * into c from public.contracts where id=r.contract_id; if auth.uid() is null or not core.has_org_role(c.organisation_id,array['super_admin','org_admin','finance','legal']) then raise exception 'redline_decision_authority_required'; end if; if r.status<>'open' or decision_value not in ('accepted','rejected','countered','withdrawn') then raise exception 'redline_decision_invalid'; end if; if nullif(btrim(target_note),'') is null then raise exception 'redline_decision_note_required'; end if; before_state:=to_jsonb(r); perform set_config('conceptspaces.legal_phase','redline_decide',true); update legal.redlines set status=decision_value,decided_by=auth.uid(),decided_at=now(),decision_note=btrim(target_note) where id=r.id returning * into r; perform audit.append_event(c.organisation_id,c.project_id,'legal.redline.'||decision_value,'redline',r.id,before_state,to_jsonb(r),target_note,gen_random_uuid()); return r.status; end;$$;
revoke all on function public.decide_contract_redline(uuid,text,text) from public,anon; grant execute on function public.decide_contract_redline(uuid,text,text) to authenticated;

create or replace function public.prepare_signature_envelope(target_contract_id uuid,input_payload jsonb)
returns uuid language plpgsql security invoker set search_path=public,legal,core,audit,auth,pg_temp as $$
declare c public.contracts%rowtype; e legal.signature_envelopes%rowtype;
begin select * into c from public.contracts where id=target_contract_id for update; if not found or auth.uid() is null or not core.has_org_role(c.organisation_id,array['super_admin','org_admin','finance','legal']) then raise exception 'signature_authority_required'; end if; if c.status not in ('draft','negotiation','signature_pending') then raise exception 'contract_not_signature_eligible'; end if; if exists(select 1 from legal.redlines r where r.contract_id=c.id and r.status in ('open','countered')) then raise exception 'unresolved_redlines_block_signature'; end if; if jsonb_typeof(coalesce(input_payload->'signatories','[]'::jsonb))<>'array' or jsonb_array_length(coalesce(input_payload->'signatories','[]'::jsonb))=0 then raise exception 'signature_signatories_required'; end if; if nullif(btrim(input_payload->>'provider'),'') is null then raise exception 'signature_provider_required'; end if; perform set_config('conceptspaces.legal_phase','signature',true); insert into legal.signature_envelopes(contract_id,provider,provider_envelope_id,signatories,signing_order,status,evidence_refs,created_by) values(c.id,btrim(input_payload->>'provider'),nullif(btrim(input_payload->>'provider_envelope_id'),''),input_payload->'signatories',coalesce(input_payload->'signing_order','[]'::jsonb),'draft',coalesce(input_payload->'evidence_refs','[]'::jsonb),auth.uid()) returning * into e; perform set_config('conceptspaces.legal_phase','contract_state',true); if c.status<>'signature_pending' then update public.contracts set status='signature_pending',updated_at=now() where id=c.id; insert into legal.contract_state_events(contract_id,from_status,to_status,evidence_reference,actor_id) values(c.id,c.status,'signature_pending','Signature envelope prepared',auth.uid()); end if; perform audit.append_event(c.organisation_id,c.project_id,'legal.signature.prepared','signature_envelope',e.id,null,to_jsonb(e),null,gen_random_uuid()); return e.id; end;$$;
revoke all on function public.prepare_signature_envelope(uuid,jsonb) from public,anon; grant execute on function public.prepare_signature_envelope(uuid,jsonb) to authenticated;

create or replace function public.transition_signature_envelope(target_envelope_id uuid,target_status text,input_payload jsonb default '{}'::jsonb)
returns text language plpgsql security invoker set search_path=public,legal,core,audit,auth,pg_temp as $$
declare e legal.signature_envelopes%rowtype; c public.contracts%rowtype; status_value text:=lower(btrim(target_status)); before_state jsonb; hash_value text:=lower(coalesce(input_payload->>'final_document_hash',''));
begin select * into e from legal.signature_envelopes where id=target_envelope_id for update; if not found then raise exception 'signature_envelope_not_found'; end if; select * into c from public.contracts where id=e.contract_id; if auth.uid() is null or not core.has_org_role(c.organisation_id,array['super_admin','org_admin','finance','legal']) then raise exception 'signature_authority_required'; end if; if status_value not in ('sent','completed','failed','cancelled','expired') then raise exception 'signature_status_invalid'; end if; if e.status in ('completed','cancelled','expired') then raise exception 'terminal_signature_envelope'; end if; if status_value='completed' then if hash_value !~ '^[0-9a-f]{64}$' then raise exception 'final_signed_document_hash_required'; end if; if jsonb_typeof(coalesce(input_payload->'evidence_refs','[]'::jsonb))<>'array' or jsonb_array_length(coalesce(input_payload->'evidence_refs','[]'::jsonb))=0 then raise exception 'signature_completion_evidence_required'; end if; if nullif(coalesce(input_payload->>'provider_envelope_id',e.provider_envelope_id),'') is null then raise exception 'signature_provider_envelope_id_required'; end if; end if; before_state:=to_jsonb(e); perform set_config('conceptspaces.legal_phase','signature',true); update legal.signature_envelopes set status=status_value,provider_envelope_id=coalesce(nullif(input_payload->>'provider_envelope_id',''),provider_envelope_id),final_document_hash=case when status_value='completed' then hash_value else final_document_hash end,evidence_refs=case when input_payload ? 'evidence_refs' then input_payload->'evidence_refs' else evidence_refs end,sent_at=case when status_value='sent' then now() else sent_at end,completed_at=case when status_value='completed' then now() else completed_at end,updated_at=now() where id=e.id returning * into e; perform audit.append_event(c.organisation_id,c.project_id,'legal.signature.'||status_value,'signature_envelope',e.id,before_state,to_jsonb(e),coalesce(input_payload->>'provider_envelope_id',status_value),gen_random_uuid()); return e.status; end;$$;
revoke all on function public.transition_signature_envelope(uuid,text,jsonb) from public,anon; grant execute on function public.transition_signature_envelope(uuid,text,jsonb) to authenticated;

create or replace function public.execute_contract_from_signature(target_contract_id uuid,target_envelope_id uuid,target_reason text)
returns text language plpgsql security invoker set search_path=public,legal,core,audit,extensions,auth,pg_temp as $$
declare c public.contracts%rowtype; e legal.signature_envelopes%rowtype; before_state jsonb; execution_hash_value text;
begin select * into c from public.contracts where id=target_contract_id for update; if not found or auth.uid() is null or not core.has_org_role(c.organisation_id,array['super_admin','org_admin','finance','legal']) then raise exception 'contract_execution_authority_required'; end if; if c.status<>'signature_pending' then raise exception 'contract_not_signature_pending'; end if; select * into e from legal.signature_envelopes where id=target_envelope_id and contract_id=c.id; if not found or e.status<>'completed' or e.final_document_hash is null then raise exception 'SIGNATURE_PROVIDER_FAILED'; end if; if nullif(btrim(target_reason),'') is null then raise exception 'contract_execution_reason_required'; end if; execution_hash_value:=encode(extensions.digest(jsonb_build_object('draft_hash',c.draft_hash,'contract_snapshot',c.contract_snapshot,'signed_document_hash',e.final_document_hash,'provider',e.provider,'provider_envelope_id',e.provider_envelope_id)::text,'sha256'),'hex'); before_state:=to_jsonb(c); perform set_config('conceptspaces.legal_phase','contract_state',true); update public.contracts set status='active',execution_hash=execution_hash_value,executed_by=auth.uid(),executed_at=now(),effective_at=coalesce(effective_at,now()),signature_provider=e.provider,signature_envelope_id=e.provider_envelope_id,updated_at=now() where id=c.id returning * into c; insert into legal.contract_state_events(contract_id,from_status,to_status,evidence_reference,actor_id) values(c.id,'signature_pending','active',target_reason,auth.uid()); if c.parent_contract_id is not null then update public.contracts set status='superseded',updated_at=now() where id=c.parent_contract_id and status in ('active','suspended'); end if; perform audit.append_event(c.organisation_id,c.project_id,'commercial.contract.executed','contract',c.id,before_state,to_jsonb(c),execution_hash_value,gen_random_uuid()); return c.status; end;$$;
revoke all on function public.execute_contract_from_signature(uuid,uuid,text) from public,anon; grant execute on function public.execute_contract_from_signature(uuid,uuid,text) to authenticated;

create or replace function public.guard_executed_contract_content()
returns trigger language plpgsql security invoker set search_path=public,pg_temp as $$
begin if old.executed_at is not null and (new.contract_snapshot is distinct from old.contract_snapshot or new.proposal_id is distinct from old.proposal_id or new.contract_type is distinct from old.contract_type or new.jurisdiction is distinct from old.jurisdiction or new.draft_hash is distinct from old.draft_hash or new.execution_hash is distinct from old.execution_hash) then raise exception 'executed_contract_content_immutable_use_amendment'; end if; return new; end;$$;
drop trigger if exists executed_contract_content_immutable on public.contracts; create trigger executed_contract_content_immutable before update on public.contracts for each row execute function public.guard_executed_contract_content();

create or replace function public.create_contract_amendment(target_contract_id uuid,target_proposal_id uuid,input_payload jsonb)
returns uuid language plpgsql security invoker set search_path=public,core,audit,auth,pg_temp as $$
declare source_contract public.contracts%rowtype; new_contract_id uuid; new_contract public.contracts%rowtype;
begin select * into source_contract from public.contracts where id=target_contract_id; if not found or source_contract.status not in ('active','suspended') or auth.uid() is null or not core.has_org_role(source_contract.organisation_id,array['super_admin','org_admin','finance','legal']) then raise exception 'contract_amendment_authority_required'; end if; if nullif(btrim(input_payload->>'reason'),'') is null then raise exception 'contract_amendment_reason_required'; end if; new_contract_id:=public.create_contract_from_proposal(target_proposal_id,source_contract.project_id,input_payload); update public.contracts set parent_contract_id=source_contract.id,version=source_contract.version+1,amendment_reason=btrim(input_payload->>'reason') where id=new_contract_id returning * into new_contract; perform audit.append_event(source_contract.organisation_id,source_contract.project_id,'commercial.contract.amendment_created','contract',new_contract.id,to_jsonb(source_contract),to_jsonb(new_contract),input_payload->>'reason',gen_random_uuid()); return new_contract.id; end;$$;
revoke all on function public.create_contract_amendment(uuid,uuid,jsonb) from public,anon; grant execute on function public.create_contract_amendment(uuid,uuid,jsonb) to authenticated;

create or replace function public.transition_contract_state(target_contract_id uuid,new_status text,evidence_reference text default null)
returns void language plpgsql security invoker set search_path=public,legal,core,audit,auth,pg_temp as $$
declare c public.contracts%rowtype; before_state jsonb; next_status text:=lower(btrim(new_status));
begin select * into c from public.contracts where id=target_contract_id for update; if not found or auth.uid() is null or not core.has_org_role(c.organisation_id,array['super_admin','org_admin','finance','legal']) then raise exception 'contract_transition_authority_required'; end if; if next_status not in ('negotiation','signature_pending','suspended','completed','terminated') then raise exception 'unsupported_contract_status'; end if; if c.status='draft' and next_status<>'negotiation' then raise exception 'draft_contract_must_enter_negotiation'; end if; if c.status='negotiation' and next_status not in ('signature_pending','terminated') then raise exception 'invalid_contract_transition'; end if; if next_status='signature_pending' then if exists(select 1 from legal.redlines r where r.contract_id=c.id and r.status in ('open','countered')) then raise exception 'unresolved_redlines_block_signature'; end if; if not exists(select 1 from legal.contract_clause_bindings b where b.contract_id=c.id) then raise exception 'approved_clause_set_required'; end if; end if; if c.status='active' and next_status not in ('suspended','completed','terminated') then raise exception 'invalid_contract_transition'; end if; if c.status='suspended' and next_status not in ('completed','terminated') then raise exception 'contract_reactivation_requires_amendment_or_authorised_execution_path'; end if; if c.status in ('completed','terminated','superseded') then raise exception 'terminal_contract_state'; end if; if next_status in ('signature_pending','suspended','completed','terminated') and nullif(btrim(evidence_reference),'') is null then raise exception 'contract_state_evidence_required'; end if; before_state:=to_jsonb(c); perform set_config('conceptspaces.legal_phase','contract_state',true); update public.contracts set status=next_status,updated_at=now() where id=c.id returning * into c; insert into legal.contract_state_events(contract_id,from_status,to_status,evidence_reference,actor_id) values(c.id,before_state->>'status',next_status,evidence_reference,auth.uid()); perform audit.append_event(c.organisation_id,c.project_id,'commercial.contract.'||next_status,'contract',c.id,before_state,to_jsonb(c),evidence_reference,gen_random_uuid()); end;$$;

create or replace function public.transition_contract_obligation(target_obligation_id uuid,target_status text,input_payload jsonb default '{}'::jsonb)
returns text language plpgsql security invoker set search_path=public,core,audit,extensions,auth,pg_temp as $$
declare o public.contract_obligations%rowtype; c public.contracts%rowtype; status_value text:=lower(btrim(target_status)); before_state jsonb;
begin select * into o from public.contract_obligations where id=target_obligation_id for update; if not found then raise exception 'obligation_not_found'; end if; select * into c from public.contracts where id=o.contract_id; if auth.uid() is null or not core.has_org_role(c.organisation_id,array['super_admin','org_admin','finance','legal','project_manager']) then raise exception 'obligation_authority_required'; end if; if status_value not in ('open','completed','waived') then raise exception 'obligation_status_invalid'; end if; if status_value='completed' and nullif(btrim(input_payload->>'evidence_reference'),'') is null then raise exception 'obligation_completion_evidence_required'; end if; if status_value='waived' and nullif(btrim(input_payload->>'reason'),'') is null then raise exception 'obligation_waiver_reason_required'; end if; before_state:=to_jsonb(o); update public.contract_obligations set status=status_value,completed_at=case when status_value='completed' then now() else completed_at end,waiver_reason=case when status_value='waived' then btrim(input_payload->>'reason') else waiver_reason end,waived_by=case when status_value='waived' then auth.uid() else waived_by end,waived_at=case when status_value='waived' then now() else waived_at end where id=o.id returning * into o; perform audit.append_event(c.organisation_id,c.project_id,'commercial.obligation.'||status_value,'contract_obligation',o.id,before_state,to_jsonb(o),coalesce(input_payload->>'evidence_reference',input_payload->>'reason'),gen_random_uuid()); return o.status; end;$$;
revoke all on function public.transition_contract_obligation(uuid,text,jsonb) from public,anon; grant execute on function public.transition_contract_obligation(uuid,text,jsonb) to authenticated;

create or replace function public.list_contract_legal_workspace(target_organisation_id uuid)
returns jsonb language plpgsql stable security invoker set search_path=public,legal,core,auth,pg_temp as $$
begin if auth.uid() is null or not core.is_internal_org_member(target_organisation_id) then raise exception 'organisation_access_required'; end if; return jsonb_build_object('clauses',coalesce((select jsonb_agg(to_jsonb(c) order by c.code) from legal.clauses c where c.organisation_id=target_organisation_id),'[]'::jsonb),'clause_versions',coalesce((select jsonb_agg(to_jsonb(v) order by v.created_at desc) from legal.clause_versions v join legal.clauses c on c.id=v.clause_id where c.organisation_id=target_organisation_id),'[]'::jsonb),'contracts',coalesce((select jsonb_agg(to_jsonb(c) order by c.created_at desc) from public.contracts c where c.organisation_id=target_organisation_id),'[]'::jsonb),'bindings',coalesce((select jsonb_agg(to_jsonb(b) order by b.created_at) from legal.contract_clause_bindings b join public.contracts c on c.id=b.contract_id where c.organisation_id=target_organisation_id),'[]'::jsonb),'redlines',coalesce((select jsonb_agg(to_jsonb(r) order by r.created_at desc) from legal.redlines r join public.contracts c on c.id=r.contract_id where c.organisation_id=target_organisation_id),'[]'::jsonb),'signatures',coalesce((select jsonb_agg(to_jsonb(e) order by e.created_at desc) from legal.signature_envelopes e join public.contracts c on c.id=e.contract_id where c.organisation_id=target_organisation_id),'[]'::jsonb),'obligations',coalesce((select jsonb_agg(to_jsonb(o) order by o.due_at nulls last,o.id) from public.contract_obligations o join public.contracts c on c.id=o.contract_id where c.organisation_id=target_organisation_id),'[]'::jsonb),'state_events',coalesce((select jsonb_agg(to_jsonb(e) order by e.created_at desc) from legal.contract_state_events e join public.contracts c on c.id=e.contract_id where c.organisation_id=target_organisation_id),'[]'::jsonb)); end;$$;
revoke all on function public.list_contract_legal_workspace(uuid) from public,anon; grant execute on function public.list_contract_legal_workspace(uuid) to authenticated;

commit;
