begin;

alter table governance.release_safety_cases
  add column if not exists created_by uuid references auth.users(id),
  add column if not exists approved_by uuid references auth.users(id),
  add column if not exists approved_at timestamptz,
  add column if not exists issued_by uuid references auth.users(id),
  add column if not exists issued_at timestamptz,
  add column if not exists last_evaluated_at timestamptz;

alter table governance.release_evidence
  add column if not exists safety_case_id uuid references governance.release_safety_cases(id) on delete cascade,
  add column if not exists package_content_hash text;

alter table governance.exceptions
  add column if not exists gate_id uuid references governance.release_gates(id) on delete cascade,
  add column if not exists safety_case_id uuid references governance.release_safety_cases(id) on delete cascade;

create table if not exists governance.release_package_reviews (
  id uuid primary key default gen_random_uuid(),
  safety_case_id uuid not null references governance.release_safety_cases(id) on delete cascade,
  project_id uuid not null references project.projects(id) on delete cascade,
  content_hash text not null,
  reviewer_user_id uuid not null references auth.users(id) on delete restrict,
  credential_id uuid not null references core.professional_credentials(id) on delete restrict,
  decision text not null check (decision in ('accepted','accepted_with_comments','rejected')),
  comments text,
  reviewed_at timestamptz not null default now()
);

create index if not exists release_evidence_case_hash_idx
  on governance.release_evidence(safety_case_id,package_content_hash,evidence_type,produced_at desc);
create index if not exists release_package_reviews_case_hash_idx
  on governance.release_package_reviews(safety_case_id,content_hash,reviewed_at desc);
create index if not exists release_package_reviews_reviewer_idx
  on governance.release_package_reviews(reviewer_user_id,reviewed_at desc);
create index if not exists release_exceptions_scope_idx
  on governance.exceptions(project_id,gate_id,safety_case_id,status,criticality);
create index if not exists release_safety_cases_gate_idx
  on governance.release_safety_cases(gate_id,created_at desc);

alter table governance.release_package_reviews enable row level security;

grant usage on schema governance to authenticated;
grant select on governance.release_gates,governance.release_evidence,governance.release_safety_cases,governance.exceptions,governance.release_package_reviews to authenticated;
grant insert on governance.release_gates,governance.release_evidence,governance.release_safety_cases,governance.exceptions,governance.release_package_reviews to authenticated;
grant update(state,unresolved_critical_defects,approved_by,approved_at,released_at,updated_at) on governance.release_gates to authenticated;
grant update(state,unresolved_critical_defects,checks,professional_approvals,client_approval_ref,approved_by,approved_at,issued_by,issued_at,last_evaluated_at,updated_at) on governance.release_safety_cases to authenticated;
grant update(status,accepted_by,rationale,resolved_at) on governance.exceptions to authenticated;

drop policy if exists release_gate_governed_insert on governance.release_gates;
create policy release_gate_governed_insert on governance.release_gates
for insert to authenticated with check (
  (select current_setting('conceptspaces.release_phase',true))='create_gate'
  and project.can_manage_project(project_id)
  and state='not_ready'
);

drop policy if exists release_gate_governed_update on governance.release_gates;
create policy release_gate_governed_update on governance.release_gates
for update to authenticated
using ((select current_setting('conceptspaces.release_phase',true)) in ('create_case','evaluate','approve','issue') and project.can_manage_project(project_id))
with check ((select current_setting('conceptspaces.release_phase',true)) in ('create_case','evaluate','approve','issue') and project.can_manage_project(project_id));

drop policy if exists release_case_governed_insert on governance.release_safety_cases;
create policy release_case_governed_insert on governance.release_safety_cases
for insert to authenticated with check (
  (select current_setting('conceptspaces.release_phase',true))='create_case'
  and project.can_manage_project(project_id)
  and created_by=(select auth.uid())
  and state='draft'
);

drop policy if exists release_case_governed_update on governance.release_safety_cases;
create policy release_case_governed_update on governance.release_safety_cases
for update to authenticated
using ((select current_setting('conceptspaces.release_phase',true)) in ('evaluate','approve','issue') and project.can_manage_project(project_id))
with check ((select current_setting('conceptspaces.release_phase',true)) in ('evaluate','approve','issue') and project.can_manage_project(project_id));

drop policy if exists release_evidence_governed_insert on governance.release_evidence;
create policy release_evidence_governed_insert on governance.release_evidence
for insert to authenticated with check (
  (select current_setting('conceptspaces.release_phase',true)) in ('create_case','add_evidence','professional_review')
  and project.can_manage_project(project_id)
  and safety_case_id is not null
  and package_content_hash is not null
  and produced_by=(select auth.uid())
);

drop policy if exists release_exception_governed_insert on governance.exceptions;
create policy release_exception_governed_insert on governance.exceptions
for insert to authenticated with check (
  (select current_setting('conceptspaces.release_phase',true))='raise_exception'
  and project.can_manage_project(project_id)
  and raised_by=(select auth.uid())
  and status='open'
);

drop policy if exists release_exception_governed_update on governance.exceptions;
create policy release_exception_governed_update on governance.exceptions
for update to authenticated
using ((select current_setting('conceptspaces.release_phase',true))='resolve_exception' and project.can_manage_project(project_id))
with check ((select current_setting('conceptspaces.release_phase',true))='resolve_exception' and project.can_manage_project(project_id));

drop policy if exists release_package_reviews_read on governance.release_package_reviews;
create policy release_package_reviews_read on governance.release_package_reviews
for select to authenticated using (project.can_access_project(project_id));

drop policy if exists release_package_reviews_governed_insert on governance.release_package_reviews;
create policy release_package_reviews_governed_insert on governance.release_package_reviews
for insert to authenticated with check (
  (select current_setting('conceptspaces.release_phase',true))='professional_review'
  and project.can_access_project(project_id)
  and reviewer_user_id=(select auth.uid())
);

create or replace function governance.credential_is_current_for_release(
  target_credential_id uuid,
  target_reviewer_user_id uuid,
  target_discipline text
) returns boolean
language sql
stable
security definer
set search_path=governance,core,auth,public,pg_temp
as $$
  select auth.uid() is not null and exists(
    select 1 from core.professional_credentials c
    where c.id=target_credential_id
      and c.user_id=target_reviewer_user_id
      and c.verification_status='verified'
      and (c.valid_from is null or c.valid_from<=current_date)
      and (c.valid_until is null or c.valid_until>=current_date)
      and (
        c.discipline is null
        or lower(c.discipline)=lower(target_discipline)
        or lower(c.discipline) in ('multidiscipline','multi_discipline','multi-discipline')
      )
  );
$$;
revoke all on function governance.credential_is_current_for_release(uuid,uuid,text) from public,anon;
grant execute on function governance.credential_is_current_for_release(uuid,uuid,text) to authenticated;

create or replace function governance.release_evidence_is_current(target_evidence_id uuid)
returns boolean
language plpgsql
stable
security invoker
set search_path=governance,project,regula,engineering,core,auth,public,pg_temp
as $$
declare
  e governance.release_evidence%rowtype;
  s governance.release_safety_cases%rowtype;
  g governance.release_gates%rowtype;
  ref_uuid uuid;
begin
  if auth.uid() is null then return false; end if;
  select * into e from governance.release_evidence where id=target_evidence_id;
  if not found or not e.passed or e.safety_case_id is null then return false; end if;
  select * into s from governance.release_safety_cases where id=e.safety_case_id;
  if not found or s.content_hash is null or e.package_content_hash is distinct from s.content_hash then return false; end if;
  select * into g from governance.release_gates where id=s.gate_id;
  if not found or g.project_id<>s.project_id or e.project_id<>s.project_id or e.gate_id<>g.id then return false; end if;

  if e.evidence_type='document_hash' then
    return e.evidence_hash=s.content_hash;
  elsif e.evidence_type='client_approval' then
    return e.evidence_hash=s.content_hash and nullif(btrim(e.reference),'') is not null;
  elsif e.evidence_type='truth_snapshot' then
    if nullif(btrim(e.evidence_hash),'') is null then return false; end if;
    if exists(select 1 from project.truth_records t where t.project_id=s.project_id and t.updated_at>e.produced_at) then return false; end if;
    return not exists(
      select 1 from project.truth_records t
      where t.project_id=s.project_id
        and engineering.criticality_rank(t.criticality)>=3
        and (t.status<>'verified' or (t.valid_until is not null and t.valid_until<now()))
    );
  elsif e.evidence_type='coordination_check' then
    if nullif(btrim(e.evidence_hash),'') is null then return false; end if;
    if exists(select 1 from engineering.coordination_matrix c where c.project_id=s.project_id and c.updated_at>e.produced_at) then return false; end if;
    return not exists(select 1 from engineering.coordination_matrix c where c.project_id=s.project_id and c.state in ('open','coordinating'));
  elsif e.evidence_type='regulatory_check' then
    if e.reference !~* '^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$' then return false; end if;
    ref_uuid:=e.reference::uuid;
    return exists(
      select 1 from regula.evaluation_runs r
      where r.id=ref_uuid and r.project_id=s.project_id and r.status='completed'
        and r.result_hash=e.evidence_hash
        and r.deterministic_failures=0 and r.interpretation_required=0 and r.not_verified=0
        and r.id=(select r2.id from regula.evaluation_runs r2 where r2.project_id=s.project_id and r2.status='completed' order by coalesce(r2.completed_at,r2.created_at) desc,r2.created_at desc limit 1)
    );
  elsif e.evidence_type='engineering_check' then
    if e.reference !~* '^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$' then return false; end if;
    ref_uuid:=e.reference::uuid;
    return exists(
      select 1
      from engineering.calculation_runs r
      join engineering.engines en on en.id=r.engine_id
      where r.id=ref_uuid and r.project_id=s.project_id and r.status='completed'
        and r.output_hash=e.evidence_hash and r.engine_version=en.version
        and en.enabled and en.certification_status in ('conditionally_approved','approved')
        and engineering.criticality_rank((select p.criticality from project.projects p where p.id=s.project_id))<=engineering.criticality_rank(en.maximum_criticality)
        and exists(
          select 1 from engineering.professional_reviews pr
          where pr.resource_type='calculation' and pr.resource_id=r.id and pr.resource_hash=r.output_hash
            and pr.decision in ('accepted','accepted_with_comments')
            and governance.credential_is_current_for_release(pr.credential_id,pr.reviewer_user_id,r.discipline)
        )
    );
  elsif e.evidence_type='professional_approval' then
    if e.reference !~* '^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$' then return false; end if;
    ref_uuid:=e.reference::uuid;
    return exists(
      select 1 from governance.release_package_reviews pr
      where pr.id=ref_uuid and pr.safety_case_id=s.id and pr.project_id=s.project_id
        and pr.content_hash=s.content_hash and pr.decision in ('accepted','accepted_with_comments')
        and governance.credential_is_current_for_release(pr.credential_id,pr.reviewer_user_id,g.discipline)
        and (engineering.criticality_rank(g.criticality)<3 or s.created_by is null or pr.reviewer_user_id<>s.created_by)
    );
  end if;
  return false;
end;
$$;
revoke all on function governance.release_evidence_is_current(uuid) from public,anon;
grant execute on function governance.release_evidence_is_current(uuid) to authenticated;

create or replace function public.create_release_gate(
  target_project_id uuid,target_gate_code text,target_name text,target_discipline text,target_criticality text,
  target_required_evidence_types jsonb,target_reason text
) returns uuid
language plpgsql security invoker
set search_path=public,governance,project,engineering,audit,auth,pg_temp
as $$
declare new_gate governance.release_gates%rowtype; project_org_id uuid; duplicate_count integer;
begin
  if auth.uid() is null or not project.can_manage_project(target_project_id) then raise exception 'project_manage_authority_required'; end if;
  if nullif(btrim(target_gate_code),'') is null or nullif(btrim(target_name),'') is null or nullif(btrim(target_discipline),'') is null then raise exception 'gate_identity_required'; end if;
  if engineering.criticality_rank(target_criticality)<0 then raise exception 'invalid_gate_criticality'; end if;
  if jsonb_typeof(target_required_evidence_types)<>'array' or jsonb_array_length(target_required_evidence_types)=0 then raise exception 'required_evidence_types_must_be_nonempty_array'; end if;
  if exists(select 1 from jsonb_array_elements_text(target_required_evidence_types) x(value) where value not in ('truth_snapshot','regulatory_check','engineering_check','coordination_check','professional_approval','client_approval','document_hash')) then raise exception 'invalid_release_evidence_type'; end if;
  select count(*)-count(distinct value) into duplicate_count from jsonb_array_elements_text(target_required_evidence_types); if duplicate_count>0 then raise exception 'duplicate_required_evidence_type'; end if;
  if not (target_required_evidence_types ? 'document_hash') then raise exception 'document_hash_required_for_every_release_gate'; end if;
  if engineering.criticality_rank(target_criticality)>=3 and not (target_required_evidence_types ? 'professional_approval') then raise exception 'professional_approval_required_for_C3_C4_gate'; end if;
  if nullif(btrim(target_reason),'') is null then raise exception 'gate_reason_required'; end if;
  select organisation_id into project_org_id from project.projects where id=target_project_id; if project_org_id is null then raise exception 'project_not_found'; end if;
  perform set_config('conceptspaces.release_phase','create_gate',true);
  insert into governance.release_gates(project_id,gate_code,name,discipline,criticality,state,required_evidence_types,unresolved_critical_defects)
  values(target_project_id,btrim(target_gate_code),btrim(target_name),lower(btrim(target_discipline)),upper(target_criticality),'not_ready',target_required_evidence_types,0)
  returning * into new_gate;
  perform audit.append_event(project_org_id,target_project_id,'release.gate_created','release_gate',new_gate.id,null,to_jsonb(new_gate),btrim(target_reason),null);
  return new_gate.id;
end;$$;

create or replace function public.create_release_safety_case(
  target_gate_id uuid,target_package_type text,target_package_reference text,target_content_hash text,target_client_approval_ref text,target_reason text
) returns uuid
language plpgsql security invoker
set search_path=public,governance,project,audit,auth,pg_temp
as $$
declare g governance.release_gates%rowtype; s governance.release_safety_cases%rowtype; project_org_id uuid;
begin
  select * into g from governance.release_gates where id=target_gate_id; if not found then raise exception 'release_gate_not_found'; end if;
  if auth.uid() is null or not project.can_manage_project(g.project_id) then raise exception 'project_manage_authority_required'; end if;
  if nullif(btrim(target_package_type),'') is null or nullif(btrim(target_package_reference),'') is null or nullif(btrim(target_content_hash),'') is null then raise exception 'package_identity_and_hash_required'; end if;
  if nullif(btrim(target_reason),'') is null then raise exception 'safety_case_reason_required'; end if;
  select organisation_id into project_org_id from project.projects where id=g.project_id;
  perform set_config('conceptspaces.release_phase','create_case',true);
  insert into governance.release_safety_cases(project_id,gate_id,package_type,package_reference,content_hash,state,unresolved_critical_defects,checks,professional_approvals,client_approval_ref,created_by)
  values(g.project_id,g.id,btrim(target_package_type),btrim(target_package_reference),btrim(target_content_hash),'draft',0,'[]'::jsonb,'[]'::jsonb,nullif(btrim(target_client_approval_ref),''),auth.uid()) returning * into s;
  insert into governance.release_evidence(project_id,gate_id,safety_case_id,package_content_hash,evidence_type,reference,evidence_hash,passed,payload,produced_by)
  values(g.project_id,g.id,s.id,s.content_hash,'document_hash',s.package_reference,s.content_hash,true,jsonb_build_object('package_type',s.package_type,'package_reference',s.package_reference),auth.uid());
  update governance.release_gates set state='not_ready',unresolved_critical_defects=0,approved_by=null,approved_at=null,released_at=null,updated_at=now() where id=g.id;
  perform audit.append_event(project_org_id,g.project_id,'release.safety_case_created','release_safety_case',s.id,null,to_jsonb(s),btrim(target_reason),null);
  return s.id;
end;$$;

create or replace function public.add_release_evidence(
  target_safety_case_id uuid,target_evidence_type text,target_reference text,target_evidence_hash text,target_passed boolean,target_payload jsonb,target_reason text
) returns uuid
language plpgsql security invoker
set search_path=public,governance,project,audit,auth,pg_temp
as $$
declare s governance.release_safety_cases%rowtype; g governance.release_gates%rowtype; ev governance.release_evidence%rowtype; project_org_id uuid;
begin
  select * into s from governance.release_safety_cases where id=target_safety_case_id; if not found then raise exception 'release_safety_case_not_found'; end if;
  select * into g from governance.release_gates where id=s.gate_id; if not found then raise exception 'release_gate_not_found'; end if;
  if auth.uid() is null or not project.can_manage_project(s.project_id) then raise exception 'project_manage_authority_required'; end if;
  if s.state in ('approved','issued') then raise exception 'approved_or_issued_safety_case_is_frozen'; end if;
  if target_evidence_type not in ('truth_snapshot','regulatory_check','engineering_check','coordination_check','client_approval') then raise exception 'use_specialised_path_for_document_or_professional_evidence'; end if;
  if nullif(btrim(target_reference),'') is null or nullif(btrim(target_evidence_hash),'') is null then raise exception 'evidence_reference_and_hash_required'; end if;
  if jsonb_typeof(coalesce(target_payload,'{}'::jsonb))<>'object' then raise exception 'evidence_payload_must_be_object'; end if;
  if nullif(btrim(target_reason),'') is null then raise exception 'evidence_reason_required'; end if;
  select organisation_id into project_org_id from project.projects where id=s.project_id;
  perform set_config('conceptspaces.release_phase','add_evidence',true);
  insert into governance.release_evidence(project_id,gate_id,safety_case_id,package_content_hash,evidence_type,reference,evidence_hash,passed,payload,produced_by)
  values(s.project_id,g.id,s.id,s.content_hash,target_evidence_type,btrim(target_reference),btrim(target_evidence_hash),target_passed,coalesce(target_payload,'{}'::jsonb),auth.uid()) returning * into ev;
  if target_passed and not governance.release_evidence_is_current(ev.id) then raise exception 'release_evidence_not_current_or_not_verifiable'; end if;
  perform audit.append_event(project_org_id,s.project_id,'release.evidence_added','release_evidence',ev.id,null,to_jsonb(ev),btrim(target_reason),null);
  return ev.id;
end;$$;

create or replace function public.review_release_package(
  target_safety_case_id uuid,target_credential_id uuid,target_decision text,target_comments text
) returns uuid
language plpgsql security invoker
set search_path=public,governance,project,core,engineering,audit,auth,pg_temp
as $$
declare s governance.release_safety_cases%rowtype; g governance.release_gates%rowtype; c core.professional_credentials%rowtype; r governance.release_package_reviews%rowtype; ev governance.release_evidence%rowtype; project_org_id uuid; passed_state boolean;
begin
  if auth.uid() is null then raise exception 'authentication_required'; end if;
  select * into s from governance.release_safety_cases where id=target_safety_case_id; if not found then raise exception 'release_safety_case_not_found'; end if;
  select * into g from governance.release_gates where id=s.gate_id; if not found then raise exception 'release_gate_not_found'; end if;
  if not project.can_access_project(s.project_id) then raise exception 'project_access_required'; end if;
  if s.state in ('approved','issued') then raise exception 'approved_or_issued_safety_case_is_frozen'; end if;
  select * into c from core.professional_credentials where id=target_credential_id and user_id=auth.uid(); if not found then raise exception 'credential_not_owned_by_reviewer'; end if;
  if not governance.credential_is_current_for_release(c.id,auth.uid(),g.discipline) then raise exception 'current_verified_discipline_credential_required'; end if;
  if lower(target_decision) not in ('accepted','accepted_with_comments','rejected') then raise exception 'invalid_review_decision'; end if;
  if lower(target_decision)='accepted_with_comments' and nullif(btrim(target_comments),'') is null then raise exception 'review_comments_required'; end if;
  if engineering.criticality_rank(g.criticality)>=3 and s.created_by=auth.uid() then raise exception 'independent_professional_review_required_for_C3_C4'; end if;
  select organisation_id into project_org_id from project.projects where id=s.project_id;
  perform set_config('conceptspaces.release_phase','professional_review',true);
  insert into governance.release_package_reviews(safety_case_id,project_id,content_hash,reviewer_user_id,credential_id,decision,comments)
  values(s.id,s.project_id,s.content_hash,auth.uid(),c.id,lower(target_decision),nullif(btrim(target_comments),'')) returning * into r;
  passed_state:=r.decision in ('accepted','accepted_with_comments');
  insert into governance.release_evidence(project_id,gate_id,safety_case_id,package_content_hash,evidence_type,reference,evidence_hash,passed,payload,produced_by)
  values(s.project_id,g.id,s.id,s.content_hash,'professional_approval',r.id::text,s.content_hash,passed_state,jsonb_build_object('decision',r.decision,'credential_id',r.credential_id),auth.uid()) returning * into ev;
  perform audit.append_event(project_org_id,s.project_id,'release.package_professional_reviewed','release_package_review',r.id,null,to_jsonb(r),coalesce(nullif(btrim(target_comments),''),'Professional package review recorded'),null);
  return r.id;
end;$$;

create or replace function public.raise_release_exception(
  target_project_id uuid,target_gate_id uuid,target_safety_case_id uuid,target_exception_type text,target_description text,target_criticality text,target_reason text
) returns uuid
language plpgsql security invoker
set search_path=public,governance,project,engineering,audit,auth,pg_temp
as $$
declare ex governance.exceptions%rowtype; project_org_id uuid;
begin
  if auth.uid() is null or not project.can_manage_project(target_project_id) then raise exception 'project_manage_authority_required'; end if;
  if engineering.criticality_rank(target_criticality)<0 then raise exception 'invalid_exception_criticality'; end if;
  if target_gate_id is not null and not exists(select 1 from governance.release_gates g where g.id=target_gate_id and g.project_id=target_project_id) then raise exception 'gate_project_mismatch'; end if;
  if target_safety_case_id is not null and not exists(select 1 from governance.release_safety_cases s where s.id=target_safety_case_id and s.project_id=target_project_id and (target_gate_id is null or s.gate_id=target_gate_id)) then raise exception 'safety_case_project_or_gate_mismatch'; end if;
  if nullif(btrim(target_exception_type),'') is null or nullif(btrim(target_description),'') is null or nullif(btrim(target_reason),'') is null then raise exception 'exception_type_description_and_reason_required'; end if;
  select organisation_id into project_org_id from project.projects where id=target_project_id;
  perform set_config('conceptspaces.release_phase','raise_exception',true);
  insert into governance.exceptions(project_id,gate_id,safety_case_id,exception_type,description,criticality,status,raised_by,rationale)
  values(target_project_id,target_gate_id,target_safety_case_id,btrim(target_exception_type),btrim(target_description),upper(target_criticality),'open',auth.uid(),btrim(target_reason)) returning * into ex;
  perform audit.append_event(project_org_id,target_project_id,'release.exception_raised','release_exception',ex.id,null,to_jsonb(ex),btrim(target_reason),null);
  return ex.id;
end;$$;

create or replace function public.resolve_release_exception(target_exception_id uuid,target_status text,target_rationale text)
returns void
language plpgsql security invoker
set search_path=public,governance,project,audit,auth,pg_temp
as $$
declare before_ex governance.exceptions%rowtype; after_ex governance.exceptions%rowtype; project_org_id uuid;
begin
  select * into before_ex from governance.exceptions where id=target_exception_id for update; if not found then raise exception 'release_exception_not_found'; end if;
  if auth.uid() is null or not project.can_manage_project(before_ex.project_id) then raise exception 'project_manage_authority_required'; end if;
  if lower(target_status) not in ('accepted','resolved','rejected') then raise exception 'invalid_exception_resolution_status'; end if;
  if nullif(btrim(target_rationale),'') is null then raise exception 'exception_resolution_rationale_required'; end if;
  select organisation_id into project_org_id from project.projects where id=before_ex.project_id;
  perform set_config('conceptspaces.release_phase','resolve_exception',true);
  update governance.exceptions set status=lower(target_status),accepted_by=auth.uid(),rationale=btrim(target_rationale),resolved_at=case when lower(target_status) in ('resolved','rejected') then now() else null end where id=before_ex.id returning * into after_ex;
  perform audit.append_event(project_org_id,before_ex.project_id,'release.exception_updated','release_exception',before_ex.id,to_jsonb(before_ex),to_jsonb(after_ex),btrim(target_rationale),null);
end;$$;

create or replace function public.evaluate_release_safety_case(target_safety_case_id uuid)
returns jsonb
language plpgsql security invoker
set search_path=public,governance,project,engineering,audit,auth,pg_temp
as $$
declare s governance.release_safety_cases%rowtype; g governance.release_gates%rowtype; project_org_id uuid; missing_count integer:=0; stale_or_failed_count integer:=0; critical_exception_count integer:=0; next_state text; check_payload jsonb;
begin
  select * into s from governance.release_safety_cases where id=target_safety_case_id for update; if not found then raise exception 'release_safety_case_not_found'; end if;
  select * into g from governance.release_gates where id=s.gate_id for update; if not found then raise exception 'release_gate_not_found'; end if;
  if auth.uid() is null or not project.can_manage_project(s.project_id) then raise exception 'project_manage_authority_required'; end if;
  if s.state='issued' then return jsonb_build_object('state','issued','release_state','released','immutable',true); end if;
  select count(*) into missing_count
  from jsonb_array_elements_text(g.required_evidence_types) req(value)
  where not exists(select 1 from governance.release_evidence e where e.safety_case_id=s.id and e.package_content_hash=s.content_hash and e.evidence_type=req.value);
  select count(*) into stale_or_failed_count
  from jsonb_array_elements_text(g.required_evidence_types) req(value)
  join lateral (
    select e.id from governance.release_evidence e
    where e.safety_case_id=s.id and e.package_content_hash=s.content_hash and e.evidence_type=req.value
    order by e.produced_at desc,e.id desc limit 1
  ) latest on true
  where not governance.release_evidence_is_current(latest.id);
  select count(*) into critical_exception_count
  from governance.exceptions ex
  where ex.project_id=s.project_id and ex.criticality in ('C3','C4') and ex.status in ('open','accepted')
    and ((ex.safety_case_id=s.id) or (ex.safety_case_id is null and ex.gate_id=g.id) or (ex.safety_case_id is null and ex.gate_id is null));
  next_state:=case when missing_count=0 and stale_or_failed_count=0 and critical_exception_count=0 then 'ready_for_review' else 'blocked' end;
  if s.state='approved' and next_state='ready_for_review' then next_state:='approved'; end if;
  check_payload:=jsonb_build_object('evaluated_at',now(),'package_content_hash',s.content_hash,'required_evidence_types',g.required_evidence_types,'missing_required_evidence',missing_count,'stale_or_failed_required_evidence',stale_or_failed_count,'unresolved_C3_C4_exceptions',critical_exception_count,'zero_critical_escape',critical_exception_count=0,'ready',missing_count=0 and stale_or_failed_count=0 and critical_exception_count=0);
  select organisation_id into project_org_id from project.projects where id=s.project_id;
  perform set_config('conceptspaces.release_phase','evaluate',true);
  update governance.release_safety_cases
  set state=next_state,unresolved_critical_defects=critical_exception_count,checks=jsonb_build_array(check_payload),last_evaluated_at=now(),approved_by=case when next_state='blocked' then null else approved_by end,approved_at=case when next_state='blocked' then null else approved_at end,updated_at=now()
  where id=s.id;
  update governance.release_gates
  set state=case when next_state='approved' then 'approved' when next_state='ready_for_review' then 'ready_for_review' else 'blocked' end,unresolved_critical_defects=critical_exception_count,approved_by=case when next_state='blocked' then null else approved_by end,approved_at=case when next_state='blocked' then null else approved_at end,updated_at=now()
  where id=g.id;
  perform audit.append_event(project_org_id,s.project_id,'release.safety_case_evaluated','release_safety_case',s.id,to_jsonb(s),check_payload,'Fresh release evidence evaluation',null);
  return check_payload||jsonb_build_object('state',next_state);
end;$$;

create or replace function public.approve_release_safety_case(target_safety_case_id uuid,target_reason text)
returns void
language plpgsql security invoker
set search_path=public,governance,project,audit,auth,pg_temp
as $$
declare s governance.release_safety_cases%rowtype; g governance.release_gates%rowtype; project_org_id uuid; evaluation jsonb;
begin
  if nullif(btrim(target_reason),'') is null then raise exception 'approval_reason_required'; end if;
  evaluation:=public.evaluate_release_safety_case(target_safety_case_id);
  select * into s from governance.release_safety_cases where id=target_safety_case_id for update;
  select * into g from governance.release_gates where id=s.gate_id for update;
  if auth.uid() is null or not project.can_manage_project(s.project_id) then raise exception 'project_manage_authority_required'; end if;
  if s.state<>'ready_for_review' then raise exception 'safety_case_not_ready_for_approval'; end if;
  select organisation_id into project_org_id from project.projects where id=s.project_id;
  perform set_config('conceptspaces.release_phase','approve',true);
  update governance.release_safety_cases set state='approved',approved_by=auth.uid(),approved_at=now(),updated_at=now() where id=s.id;
  update governance.release_gates set state='approved',approved_by=auth.uid(),approved_at=now(),updated_at=now() where id=g.id;
  perform audit.append_event(project_org_id,s.project_id,'release.safety_case_approved','release_safety_case',s.id,to_jsonb(s),jsonb_build_object('state','approved','approved_by',auth.uid(),'content_hash',s.content_hash),btrim(target_reason),null);
end;$$;

create or replace function public.issue_release_safety_case(target_safety_case_id uuid,target_reason text)
returns void
language plpgsql security invoker
set search_path=public,governance,project,audit,auth,pg_temp
as $$
declare s governance.release_safety_cases%rowtype; g governance.release_gates%rowtype; project_org_id uuid; evaluation jsonb;
begin
  if nullif(btrim(target_reason),'') is null then raise exception 'issue_reason_required'; end if;
  select * into s from governance.release_safety_cases where id=target_safety_case_id; if not found then raise exception 'release_safety_case_not_found'; end if;
  if s.state<>'approved' then raise exception 'safety_case_must_be_approved_before_issue'; end if;
  evaluation:=public.evaluate_release_safety_case(target_safety_case_id);
  select * into s from governance.release_safety_cases where id=target_safety_case_id for update;
  select * into g from governance.release_gates where id=s.gate_id for update;
  if s.state<>'approved' or coalesce((s.checks->0->>'ready')::boolean,false)=false then raise exception 'fresh_release_evaluation_failed'; end if;
  if s.unresolved_critical_defects<>0 or g.unresolved_critical_defects<>0 then raise exception 'zero_critical_escape_required'; end if;
  if auth.uid() is null or not project.can_manage_project(s.project_id) then raise exception 'project_manage_authority_required'; end if;
  select organisation_id into project_org_id from project.projects where id=s.project_id;
  perform set_config('conceptspaces.release_phase','issue',true);
  update governance.release_safety_cases set state='issued',issued_by=auth.uid(),issued_at=now(),updated_at=now() where id=s.id;
  update governance.release_gates set state='released',released_at=now(),updated_at=now() where id=g.id;
  perform audit.append_event(project_org_id,s.project_id,'release.package_issued','release_safety_case',s.id,to_jsonb(s),jsonb_build_object('state','issued','content_hash',s.content_hash,'gate_id',g.id,'issued_by',auth.uid()),btrim(target_reason),null);
end;$$;

create or replace function public.list_release_assurance_workspace()
returns jsonb
language plpgsql stable security invoker
set search_path=public,governance,project,core,auth,pg_temp
as $$
begin
  if auth.uid() is null then raise exception 'authentication_required'; end if;
  return jsonb_build_object(
    'gates',coalesce((select jsonb_agg(jsonb_build_object('id',g.id,'project_id',g.project_id,'project_code',p.code::text,'project_name',p.name,'gate_code',g.gate_code::text,'name',g.name,'discipline',g.discipline,'criticality',g.criticality,'state',g.state,'required_evidence_types',g.required_evidence_types,'unresolved_critical_defects',g.unresolved_critical_defects,'approved_by',g.approved_by,'approved_at',g.approved_at,'released_at',g.released_at,'created_at',g.created_at,'updated_at',g.updated_at) order by g.updated_at desc) from governance.release_gates g join project.projects p on p.id=g.project_id where project.can_access_project(g.project_id)),'[]'::jsonb),
    'safety_cases',coalesce((select jsonb_agg(to_jsonb(s) order by s.created_at desc) from governance.release_safety_cases s where project.can_access_project(s.project_id)),'[]'::jsonb),
    'evidence',coalesce((select jsonb_agg(jsonb_build_object('id',e.id,'project_id',e.project_id,'gate_id',e.gate_id,'safety_case_id',e.safety_case_id,'package_content_hash',e.package_content_hash,'evidence_type',e.evidence_type,'reference',e.reference,'evidence_hash',e.evidence_hash,'passed',e.passed,'current',governance.release_evidence_is_current(e.id),'payload',e.payload,'produced_by',e.produced_by,'produced_at',e.produced_at) order by e.produced_at desc) from governance.release_evidence e where project.can_access_project(e.project_id)),'[]'::jsonb),
    'exceptions',coalesce((select jsonb_agg(to_jsonb(ex) order by ex.created_at desc) from governance.exceptions ex where project.can_access_project(ex.project_id)),'[]'::jsonb),
    'package_reviews',coalesce((select jsonb_agg(to_jsonb(r) order by r.reviewed_at desc) from governance.release_package_reviews r where project.can_access_project(r.project_id)),'[]'::jsonb),
    'credentials',coalesce((select jsonb_agg(jsonb_build_object('id',c.id,'credential_type',c.credential_type,'issuing_body',c.issuing_body,'registration_number',c.registration_number,'discipline',c.discipline,'valid_from',c.valid_from,'valid_until',c.valid_until,'verification_status',c.verification_status) order by c.created_at desc) from core.professional_credentials c where c.user_id=auth.uid()),'[]'::jsonb)
  );
end;$$;

revoke all on function public.create_release_gate(uuid,text,text,text,text,jsonb,text) from public,anon;
grant execute on function public.create_release_gate(uuid,text,text,text,text,jsonb,text) to authenticated;
revoke all on function public.create_release_safety_case(uuid,text,text,text,text,text) from public,anon;
grant execute on function public.create_release_safety_case(uuid,text,text,text,text,text) to authenticated;
revoke all on function public.add_release_evidence(uuid,text,text,text,boolean,jsonb,text) from public,anon;
grant execute on function public.add_release_evidence(uuid,text,text,text,boolean,jsonb,text) to authenticated;
revoke all on function public.review_release_package(uuid,uuid,text,text) from public,anon;
grant execute on function public.review_release_package(uuid,uuid,text,text) to authenticated;
revoke all on function public.raise_release_exception(uuid,uuid,uuid,text,text,text,text) from public,anon;
grant execute on function public.raise_release_exception(uuid,uuid,uuid,text,text,text,text) to authenticated;
revoke all on function public.resolve_release_exception(uuid,text,text) from public,anon;
grant execute on function public.resolve_release_exception(uuid,text,text) to authenticated;
revoke all on function public.evaluate_release_safety_case(uuid) from public,anon;
grant execute on function public.evaluate_release_safety_case(uuid) to authenticated;
revoke all on function public.approve_release_safety_case(uuid,text) from public,anon;
grant execute on function public.approve_release_safety_case(uuid,text) to authenticated;
revoke all on function public.issue_release_safety_case(uuid,text) from public,anon;
grant execute on function public.issue_release_safety_case(uuid,text) to authenticated;
revoke all on function public.list_release_assurance_workspace() from public,anon;
grant execute on function public.list_release_assurance_workspace() to authenticated;

commit;
