begin;

create table if not exists engineering.engine_governance_events (
  id uuid primary key default gen_random_uuid(),
  engine_id uuid references engineering.engines(id) on delete set null,
  actor_id uuid not null references auth.users(id) on delete restrict,
  event_type text not null check (event_type in ('registered','benchmark_case_added','benchmark_result_recorded','certification_changed')),
  reason text not null,
  snapshot jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now()
);

create index if not exists engine_governance_events_engine_idx on engineering.engine_governance_events(engine_id,created_at desc);
create index if not exists engine_governance_events_actor_idx on engineering.engine_governance_events(actor_id,created_at desc);

alter table engineering.engine_governance_events enable row level security;
grant usage on schema engineering to authenticated;
grant select on engineering.engines, engineering.engine_benchmark_cases, engineering.engine_benchmark_results,
  engineering.calculation_runs, engineering.professional_reviews, engineering.mep_systems, engineering.engine_governance_events to authenticated;
grant insert on engineering.engines, engineering.engine_benchmark_cases, engineering.engine_benchmark_results,
  engineering.calculation_runs, engineering.professional_reviews, engineering.mep_systems, engineering.engine_governance_events to authenticated;
grant update(certification_status,maximum_criticality,enabled,updated_at) on engineering.engines to authenticated;

create or replace function engineering.criticality_rank(target text)
returns integer language sql immutable security invoker set search_path=engineering,pg_temp as $$
  select case upper(target) when 'C0' then 0 when 'C1' then 1 when 'C2' then 2 when 'C3' then 3 when 'C4' then 4 else -1 end;
$$;

-- Certified/enabled engine metadata is visible to authenticated project users; all registry states remain visible to platform admins.
drop policy if exists cs_read on engineering.engines;
create policy cs_read on engineering.engines for select to authenticated using (
  core.is_platform_admin() or (enabled and certification_status in ('conditionally_approved','approved'))
);

drop policy if exists engineering_engine_governed_insert on engineering.engines;
create policy engineering_engine_governed_insert on engineering.engines for insert to authenticated with check (
  (select current_setting('conceptspaces.engineering_phase',true))='register_engine'
  and core.is_platform_admin()
  and certification_status='uncertified'
  and enabled=false
);

drop policy if exists engineering_engine_governed_update on engineering.engines;
create policy engineering_engine_governed_update on engineering.engines for update to authenticated using (
  (select current_setting('conceptspaces.engineering_phase',true))='certify_engine' and core.is_platform_admin()
) with check (
  (select current_setting('conceptspaces.engineering_phase',true))='certify_engine' and core.is_platform_admin()
);

drop policy if exists engineering_benchmark_case_governed_insert on engineering.engine_benchmark_cases;
create policy engineering_benchmark_case_governed_insert on engineering.engine_benchmark_cases for insert to authenticated with check (
  (select current_setting('conceptspaces.engineering_phase',true))='add_benchmark' and core.is_platform_admin()
);

drop policy if exists engineering_benchmark_result_governed_insert on engineering.engine_benchmark_results;
create policy engineering_benchmark_result_governed_insert on engineering.engine_benchmark_results for insert to authenticated with check (
  (select current_setting('conceptspaces.engineering_phase',true))='record_benchmark' and core.is_platform_admin()
);

drop policy if exists engineering_mep_governed_insert on engineering.mep_systems;
create policy engineering_mep_governed_insert on engineering.mep_systems for insert to authenticated with check (
  (select current_setting('conceptspaces.engineering_phase',true))='register_mep_system'
  and project.can_manage_project(project_id)
);

drop policy if exists engineering_calculation_governed_insert on engineering.calculation_runs;
create policy engineering_calculation_governed_insert on engineering.calculation_runs for insert to authenticated with check (
  (select current_setting('conceptspaces.engineering_phase',true))='record_calculation'
  and project.can_manage_project(project_id)
  and created_by=(select auth.uid())
  and status='completed'
);

drop policy if exists engineering_review_governed_insert on engineering.professional_reviews;
create policy engineering_review_governed_insert on engineering.professional_reviews for insert to authenticated with check (
  (select current_setting('conceptspaces.engineering_phase',true))='record_review'
  and project.can_access_project(project_id)
  and reviewer_user_id=(select auth.uid())
);

drop policy if exists engineering_governance_admin_read on engineering.engine_governance_events;
create policy engineering_governance_admin_read on engineering.engine_governance_events for select to authenticated using (core.is_platform_admin());
drop policy if exists engineering_governance_governed_insert on engineering.engine_governance_events;
create policy engineering_governance_governed_insert on engineering.engine_governance_events for insert to authenticated with check (
  core.is_platform_admin() and actor_id=(select auth.uid())
  and (select current_setting('conceptspaces.engineering_phase',true)) in ('register_engine','add_benchmark','record_benchmark','certify_engine')
);

create or replace function public.register_engine_version(
  target_code text,target_name text,target_discipline text,target_engine_type text,target_vendor text,target_version text,
  target_executable_ref text,target_supported_standards jsonb,target_supported_units jsonb,target_maximum_criticality text,target_checksum text,target_reason text
) returns uuid language plpgsql security invoker set search_path=public,engineering,core,auth,pg_temp as $$
declare new_engine engineering.engines%rowtype;
begin
  if auth.uid() is null or not core.is_platform_admin() then raise exception 'platform_admin_required'; end if;
  if nullif(btrim(target_code),'') is null or nullif(btrim(target_name),'') is null or nullif(btrim(target_discipline),'') is null or nullif(btrim(target_version),'') is null then raise exception 'engine_identity_required'; end if;
  if lower(target_engine_type) not in ('deterministic','parametric','physics_simulation','rules','optimisation','adapter') then raise exception 'invalid_engine_type'; end if;
  if engineering.criticality_rank(target_maximum_criticality)<0 then raise exception 'invalid_maximum_criticality'; end if;
  if jsonb_typeof(coalesce(target_supported_standards,'[]'::jsonb))<>'array' or jsonb_typeof(coalesce(target_supported_units,'[]'::jsonb))<>'array' then raise exception 'standards_and_units_must_be_arrays'; end if;
  if nullif(btrim(target_reason),'') is null then raise exception 'registration_reason_required'; end if;
  perform set_config('conceptspaces.engineering_phase','register_engine',true);
  insert into engineering.engines(code,name,discipline,engine_type,vendor,version,executable_ref,supported_standards,supported_units,certification_status,maximum_criticality,checksum,enabled)
  values(btrim(target_code),btrim(target_name),lower(btrim(target_discipline)),lower(target_engine_type),nullif(btrim(target_vendor),''),btrim(target_version),nullif(btrim(target_executable_ref),''),coalesce(target_supported_standards,'[]'::jsonb),coalesce(target_supported_units,'[]'::jsonb),'uncertified',upper(target_maximum_criticality),nullif(btrim(target_checksum),''),false)
  returning * into new_engine;
  insert into engineering.engine_governance_events(engine_id,actor_id,event_type,reason,snapshot)
  values(new_engine.id,auth.uid(),'registered',btrim(target_reason),to_jsonb(new_engine));
  return new_engine.id;
end;$$;

create or replace function public.add_engine_benchmark_case(
  target_engine_id uuid,target_suite_code text,target_name text,target_standard_reference text,target_input_ref text,
  target_expected_result_ref text,target_tolerance jsonb,target_criticality text,target_reason text
) returns uuid language plpgsql security invoker set search_path=public,engineering,core,auth,pg_temp as $$
declare target_engine engineering.engines%rowtype; new_case engineering.engine_benchmark_cases%rowtype;
begin
  if auth.uid() is null or not core.is_platform_admin() then raise exception 'platform_admin_required'; end if;
  select * into target_engine from engineering.engines where id=target_engine_id; if not found then raise exception 'engine_not_found'; end if;
  if nullif(btrim(target_suite_code),'') is null or nullif(btrim(target_name),'') is null or nullif(btrim(target_input_ref),'') is null or nullif(btrim(target_expected_result_ref),'') is null then raise exception 'benchmark_identity_and_references_required'; end if;
  if engineering.criticality_rank(target_criticality)<0 then raise exception 'invalid_benchmark_criticality'; end if;
  if jsonb_typeof(coalesce(target_tolerance,'{}'::jsonb))<>'object' then raise exception 'tolerance_must_be_object'; end if;
  if nullif(btrim(target_reason),'') is null then raise exception 'benchmark_reason_required'; end if;
  perform set_config('conceptspaces.engineering_phase','add_benchmark',true);
  insert into engineering.engine_benchmark_cases(engine_id,suite_code,name,standard_reference,input_ref,expected_result_ref,tolerance,criticality,active)
  values(target_engine_id,btrim(target_suite_code),btrim(target_name),nullif(btrim(target_standard_reference),''),btrim(target_input_ref),btrim(target_expected_result_ref),coalesce(target_tolerance,'{}'::jsonb),upper(target_criticality),true)
  returning * into new_case;
  insert into engineering.engine_governance_events(engine_id,actor_id,event_type,reason,snapshot)
  values(target_engine_id,auth.uid(),'benchmark_case_added',btrim(target_reason),to_jsonb(new_case));
  return new_case.id;
end;$$;

create or replace function public.record_engine_benchmark_result(
  target_benchmark_case_id uuid,target_passed boolean,target_deviation jsonb,target_evidence_refs jsonb,target_reason text
) returns uuid language plpgsql security invoker set search_path=public,engineering,core,auth,pg_temp as $$
declare benchmark engineering.engine_benchmark_cases%rowtype; target_engine engineering.engines%rowtype; new_result engineering.engine_benchmark_results%rowtype;
begin
  if auth.uid() is null or not core.is_platform_admin() then raise exception 'platform_admin_required'; end if;
  select * into benchmark from engineering.engine_benchmark_cases where id=target_benchmark_case_id; if not found then raise exception 'benchmark_case_not_found'; end if;
  select * into target_engine from engineering.engines where id=benchmark.engine_id; if not found then raise exception 'engine_not_found'; end if;
  if jsonb_typeof(coalesce(target_deviation,'{}'::jsonb))<>'object' then raise exception 'deviation_must_be_object'; end if;
  if jsonb_typeof(coalesce(target_evidence_refs,'[]'::jsonb))<>'array' or jsonb_array_length(coalesce(target_evidence_refs,'[]'::jsonb))=0 then raise exception 'benchmark_evidence_required'; end if;
  if nullif(btrim(target_reason),'') is null then raise exception 'benchmark_result_reason_required'; end if;
  perform set_config('conceptspaces.engineering_phase','record_benchmark',true);
  insert into engineering.engine_benchmark_results(benchmark_case_id,engine_id,engine_version,passed,deviation,evidence_refs)
  values(benchmark.id,target_engine.id,target_engine.version,target_passed,coalesce(target_deviation,'{}'::jsonb),target_evidence_refs) returning * into new_result;
  insert into engineering.engine_governance_events(engine_id,actor_id,event_type,reason,snapshot)
  values(target_engine.id,auth.uid(),'benchmark_result_recorded',btrim(target_reason),to_jsonb(new_result));
  return new_result.id;
end;$$;

create or replace function public.set_engine_certification(
  target_engine_id uuid,target_certification_status text,target_maximum_criticality text,target_reason text
) returns void language plpgsql security invoker set search_path=public,engineering,core,auth,pg_temp as $$
declare target_engine engineering.engines%rowtype; active_cases integer; missing_or_failed integer; max_benchmark_rank integer; new_max text; next_enabled boolean;
begin
  if auth.uid() is null or not core.is_platform_admin() then raise exception 'platform_admin_required'; end if;
  if lower(target_certification_status) not in ('uncertified','benchmarking','conditionally_approved','approved','suspended','retired') then raise exception 'invalid_certification_status'; end if;
  if nullif(btrim(target_reason),'') is null then raise exception 'certification_reason_required'; end if;
  select * into target_engine from engineering.engines where id=target_engine_id for update; if not found then raise exception 'engine_not_found'; end if;
  new_max:=upper(coalesce(nullif(btrim(target_maximum_criticality),''),target_engine.maximum_criticality));
  if engineering.criticality_rank(new_max)<0 then raise exception 'invalid_maximum_criticality'; end if;
  if lower(target_certification_status) in ('conditionally_approved','approved') then
    if nullif(btrim(target_engine.checksum),'') is null then raise exception 'engine_checksum_required_for_certification'; end if;
    if jsonb_array_length(target_engine.supported_standards)=0 or jsonb_array_length(target_engine.supported_units)=0 then raise exception 'supported_standards_and_units_required_for_certification'; end if;
    select count(*),coalesce(max(engineering.criticality_rank(c.criticality)),-1) into active_cases,max_benchmark_rank from engineering.engine_benchmark_cases c where c.engine_id=target_engine.id and c.active;
    if active_cases=0 then raise exception 'active_benchmark_suite_required'; end if;
    select count(*) into missing_or_failed from engineering.engine_benchmark_cases c where c.engine_id=target_engine.id and c.active and not exists (
      select 1 from engineering.engine_benchmark_results r where r.benchmark_case_id=c.id and r.engine_id=target_engine.id and r.engine_version=target_engine.version and r.passed=true and r.executed_at=(select max(r2.executed_at) from engineering.engine_benchmark_results r2 where r2.benchmark_case_id=c.id and r2.engine_id=target_engine.id and r2.engine_version=target_engine.version)
    );
    if missing_or_failed>0 then raise exception 'all_active_benchmarks_must_have_latest_passing_result'; end if;
    if max_benchmark_rank<engineering.criticality_rank(new_max) then raise exception 'benchmark_criticality_does_not_cover_requested_maximum'; end if;
    if lower(target_certification_status)='conditionally_approved' and engineering.criticality_rank(new_max)>2 then raise exception 'conditional_approval_cannot_exceed_C2'; end if;
  end if;
  next_enabled:=lower(target_certification_status) in ('conditionally_approved','approved');
  perform set_config('conceptspaces.engineering_phase','certify_engine',true);
  update engineering.engines set certification_status=lower(target_certification_status),maximum_criticality=new_max,enabled=next_enabled,updated_at=now() where id=target_engine.id;
  insert into engineering.engine_governance_events(engine_id,actor_id,event_type,reason,snapshot)
  values(target_engine.id,auth.uid(),'certification_changed',btrim(target_reason),jsonb_build_object('from_status',target_engine.certification_status,'to_status',lower(target_certification_status),'maximum_criticality',new_max,'enabled',next_enabled));
end;$$;

create or replace function public.register_mep_system(
  target_project_id uuid,target_discipline text,target_system_code text,target_name text,target_design_criteria jsonb,target_reason text
) returns uuid language plpgsql security invoker set search_path=public,engineering,project,audit,auth,pg_temp as $$
declare project_org_id uuid; new_system engineering.mep_systems%rowtype;
begin
  if auth.uid() is null or not project.can_manage_project(target_project_id) then raise exception 'project_manage_authority_required'; end if;
  if lower(target_discipline) not in ('mechanical','electrical','plumbing','fire','elv','bms','vertical_transport') then raise exception 'invalid_mep_discipline'; end if;
  if nullif(btrim(target_system_code),'') is null or nullif(btrim(target_name),'') is null then raise exception 'system_identity_required'; end if;
  if jsonb_typeof(coalesce(target_design_criteria,'{}'::jsonb))<>'object' then raise exception 'design_criteria_must_be_object'; end if;
  select organisation_id into project_org_id from project.projects where id=target_project_id; if project_org_id is null then raise exception 'project_not_found'; end if;
  perform set_config('conceptspaces.engineering_phase','register_mep_system',true);
  insert into engineering.mep_systems(project_id,discipline,system_code,name,design_criteria,status,created_by)
  values(target_project_id,lower(target_discipline),btrim(target_system_code),btrim(target_name),coalesce(target_design_criteria,'{}'::jsonb),'criteria',auth.uid()) returning * into new_system;
  perform audit.append_event(project_org_id,target_project_id,'engineering.mep_system_registered','mep_system',new_system.id,null,to_jsonb(new_system),coalesce(nullif(btrim(target_reason),''),'MEP system registered'),null);
  return new_system.id;
end;$$;

create or replace function public.record_engineering_calculation(
  target_project_id uuid,target_discipline text,target_calculation_type text,target_engine_id uuid,target_input_snapshot_ref text,target_input_hash text,
  target_assumptions jsonb,target_standard_references jsonb,target_unit_system text,target_output_ref text,target_output_hash text,target_result_summary jsonb,target_evidence_refs jsonb,target_reason text
) returns uuid language plpgsql security invoker set search_path=public,engineering,project,audit,auth,pg_temp as $$
declare project_row project.projects%rowtype; target_engine engineering.engines%rowtype; new_run engineering.calculation_runs%rowtype;
begin
  if auth.uid() is null or not project.can_manage_project(target_project_id) then raise exception 'project_manage_authority_required'; end if;
  select * into project_row from project.projects where id=target_project_id; if not found then raise exception 'project_not_found'; end if;
  select * into target_engine from engineering.engines where id=target_engine_id; if not found then raise exception 'eligible_engine_not_found'; end if;
  if not target_engine.enabled or target_engine.certification_status not in ('conditionally_approved','approved') then raise exception 'engine_not_certified_and_enabled'; end if;
  if engineering.criticality_rank(project_row.criticality)>engineering.criticality_rank(target_engine.maximum_criticality) then raise exception 'engine_not_certified_for_project_criticality'; end if;
  if lower(target_engine.discipline) not in (lower(target_discipline),'mep','mepf','multidiscipline') then raise exception 'engine_discipline_mismatch'; end if;
  if nullif(btrim(target_calculation_type),'') is null or nullif(btrim(target_input_snapshot_ref),'') is null or nullif(btrim(target_input_hash),'') is null or nullif(btrim(target_output_ref),'') is null or nullif(btrim(target_output_hash),'') is null then raise exception 'calculation_provenance_references_required'; end if;
  if jsonb_typeof(coalesce(target_assumptions,'[]'::jsonb))<>'array' or jsonb_typeof(coalesce(target_standard_references,'[]'::jsonb))<>'array' or jsonb_typeof(coalesce(target_evidence_refs,'[]'::jsonb))<>'array' or jsonb_typeof(coalesce(target_result_summary,'{}'::jsonb))<>'object' then raise exception 'invalid_calculation_json_shape'; end if;
  if jsonb_array_length(coalesce(target_standard_references,'[]'::jsonb))=0 or jsonb_array_length(coalesce(target_evidence_refs,'[]'::jsonb))=0 then raise exception 'standards_and_execution_evidence_required'; end if;
  if not (coalesce(target_standard_references,'[]'::jsonb) <@ target_engine.supported_standards) then raise exception 'calculation_standard_not_supported_by_engine'; end if;
  if not (target_engine.supported_units ? btrim(target_unit_system)) then raise exception 'unit_system_not_supported_by_engine'; end if;
  if nullif(btrim(target_reason),'') is null then raise exception 'calculation_reason_required'; end if;
  perform set_config('conceptspaces.engineering_phase','record_calculation',true);
  insert into engineering.calculation_runs(project_id,discipline,calculation_type,engine_id,engine_version,status,input_snapshot_ref,assumptions,standard_references,unit_system,output_ref,result_summary,evidence_refs,input_hash,output_hash,created_by,started_at,finished_at)
  values(target_project_id,lower(target_discipline),btrim(target_calculation_type),target_engine.id,target_engine.version,'completed',btrim(target_input_snapshot_ref),coalesce(target_assumptions,'[]'::jsonb),target_standard_references,btrim(target_unit_system),btrim(target_output_ref),coalesce(target_result_summary,'{}'::jsonb),target_evidence_refs,btrim(target_input_hash),btrim(target_output_hash),auth.uid(),now(),now()) returning * into new_run;
  perform audit.append_event(project_row.organisation_id,target_project_id,'engineering.calculation_recorded','calculation',new_run.id,null,to_jsonb(new_run),btrim(target_reason),null);
  return new_run.id;
end;$$;

create or replace function public.review_engineering_calculation(
  target_calculation_run_id uuid,target_credential_id uuid,target_decision text,target_comments text
) returns uuid language plpgsql security invoker set search_path=public,engineering,project,core,audit,auth,pg_temp as $$
declare run_row engineering.calculation_runs%rowtype; project_row project.projects%rowtype; credential core.professional_credentials%rowtype; new_review engineering.professional_reviews%rowtype;
begin
  if auth.uid() is null then raise exception 'authentication_required'; end if;
  select * into run_row from engineering.calculation_runs where id=target_calculation_run_id; if not found then raise exception 'calculation_run_not_found_or_inaccessible'; end if;
  if not project.can_access_project(run_row.project_id) then raise exception 'project_access_required'; end if;
  if run_row.status<>'completed' or nullif(btrim(run_row.output_hash),'') is null then raise exception 'completed_hashed_output_required'; end if;
  select * into project_row from project.projects where id=run_row.project_id;
  select * into credential from core.professional_credentials where id=target_credential_id and user_id=auth.uid(); if not found then raise exception 'credential_not_owned_by_reviewer'; end if;
  if credential.verification_status<>'verified' then raise exception 'verified_professional_credential_required'; end if;
  if credential.valid_from is not null and credential.valid_from>current_date then raise exception 'credential_not_yet_valid'; end if;
  if credential.valid_until is not null and credential.valid_until<current_date then raise exception 'credential_expired'; end if;
  if credential.discipline is not null and lower(credential.discipline) not in (lower(run_row.discipline),'mep','mepf','multidiscipline') then raise exception 'credential_discipline_mismatch'; end if;
  if lower(target_decision) not in ('accepted','accepted_with_comments','rejected') then raise exception 'invalid_review_decision'; end if;
  if lower(target_decision)='accepted_with_comments' and nullif(btrim(target_comments),'') is null then raise exception 'comments_required'; end if;
  if engineering.criticality_rank(project_row.criticality)>=3 and run_row.created_by=auth.uid() then raise exception 'independent_professional_review_required_for_C3_C4'; end if;
  if exists(select 1 from engineering.professional_reviews r where r.resource_type='calculation' and r.resource_id=run_row.id and r.resource_hash=run_row.output_hash and r.reviewer_user_id=auth.uid() and r.credential_id=credential.id and r.decision<>'pending') then raise exception 'review_already_recorded_for_exact_hash'; end if;
  perform set_config('conceptspaces.engineering_phase','record_review',true);
  insert into engineering.professional_reviews(project_id,resource_type,resource_id,resource_hash,discipline,reviewer_user_id,credential_id,decision,comments,reviewed_at)
  values(run_row.project_id,'calculation',run_row.id,run_row.output_hash,run_row.discipline,auth.uid(),credential.id,lower(target_decision),nullif(btrim(target_comments),''),now()) returning * into new_review;
  perform audit.append_event(project_row.organisation_id,run_row.project_id,'engineering.calculation_reviewed','professional_review',new_review.id,null,to_jsonb(new_review),coalesce(nullif(btrim(target_comments),''),'Professional engineering review recorded'),null);
  return new_review.id;
end;$$;

create or replace function public.list_engineering_validation_workspace()
returns jsonb language plpgsql stable security invoker set search_path=public,engineering,project,core,auth,pg_temp as $$
declare admin_mode boolean;
begin
  if auth.uid() is null then raise exception 'authentication_required'; end if;
  admin_mode:=core.is_platform_admin();
  return jsonb_build_object(
    'is_platform_admin',admin_mode,
    'engines',coalesce((select jsonb_agg(to_jsonb(e) order by e.code,e.version) from engineering.engines e),'[]'::jsonb),
    'benchmark_cases',case when admin_mode then coalesce((select jsonb_agg(to_jsonb(c) order by c.created_at desc) from engineering.engine_benchmark_cases c),'[]'::jsonb) else '[]'::jsonb end,
    'benchmark_results',case when admin_mode then coalesce((select jsonb_agg(to_jsonb(r) order by r.executed_at desc) from engineering.engine_benchmark_results r),'[]'::jsonb) else '[]'::jsonb end,
    'engine_events',case when admin_mode then coalesce((select jsonb_agg(to_jsonb(g) order by g.created_at desc) from engineering.engine_governance_events g),'[]'::jsonb) else '[]'::jsonb end,
    'systems',coalesce((select jsonb_agg(jsonb_build_object('id',s.id,'project_id',s.project_id,'project_code',p.code::text,'project_name',p.name,'discipline',s.discipline,'system_code',s.system_code::text,'name',s.name,'design_criteria',s.design_criteria,'status',s.status,'created_at',s.created_at) order by s.created_at desc) from engineering.mep_systems s join project.projects p on p.id=s.project_id where project.can_access_project(s.project_id)),'[]'::jsonb),
    'calculation_runs',coalesce((select jsonb_agg(jsonb_build_object(
      'id',r.id,'project_id',r.project_id,'project_code',p.code::text,'project_name',p.name,'project_criticality',p.criticality,'discipline',r.discipline,'calculation_type',r.calculation_type,
      'engine_id',r.engine_id,'engine_code',e.code::text,'engine_name',e.name,'engine_version',r.engine_version,'engine_certification',e.certification_status,'engine_maximum_criticality',e.maximum_criticality,
      'status',r.status,'input_snapshot_ref',r.input_snapshot_ref,'input_hash',r.input_hash,'output_ref',r.output_ref,'output_hash',r.output_hash,'standard_references',r.standard_references,'unit_system',r.unit_system,'result_summary',r.result_summary,'evidence_refs',r.evidence_refs,'created_by',r.created_by,'finished_at',r.finished_at,
      'verification_state',case when r.status<>'completed' or e.enabled=false or e.certification_status not in ('conditionally_approved','approved') or r.engine_version<>e.version or engineering.criticality_rank(p.criticality)>engineering.criticality_rank(e.maximum_criticality) or r.output_hash is null then 'NOT_VERIFIED' when exists(select 1 from engineering.professional_reviews pr join core.professional_credentials pc on pc.id=pr.credential_id where pr.resource_type='calculation' and pr.resource_id=r.id and pr.resource_hash=r.output_hash and pr.decision in ('accepted','accepted_with_comments') and pc.verification_status='verified' and (pc.valid_from is null or pc.valid_from<=current_date) and (pc.valid_until is null or pc.valid_until>=current_date)) then 'PROFESSIONALLY_REVIEWED' else 'AUTOMATED_VALIDATED' end,
      'release_state',case when exists(select 1 from engineering.professional_reviews pr join core.professional_credentials pc on pc.id=pr.credential_id where pr.resource_type='calculation' and pr.resource_id=r.id and pr.resource_hash=r.output_hash and pr.decision in ('accepted','accepted_with_comments') and pc.verification_status='verified' and (pc.valid_from is null or pc.valid_from<=current_date) and (pc.valid_until is null or pc.valid_until>=current_date)) and r.status='completed' and e.enabled and e.certification_status in ('conditionally_approved','approved') and r.engine_version=e.version and engineering.criticality_rank(p.criticality)<=engineering.criticality_rank(e.maximum_criticality) then 'ELIGIBLE_FOR_RELEASE_GATE' else 'BLOCKED' end
    ) order by r.created_at desc) from engineering.calculation_runs r join project.projects p on p.id=r.project_id join engineering.engines e on e.id=r.engine_id where project.can_access_project(r.project_id)),'[]'::jsonb),
    'reviews',coalesce((select jsonb_agg(to_jsonb(pr) order by pr.created_at desc) from engineering.professional_reviews pr where project.can_access_project(pr.project_id)),'[]'::jsonb),
    'credentials',coalesce((select jsonb_agg(jsonb_build_object('id',c.id,'credential_type',c.credential_type,'issuing_body',c.issuing_body,'registration_number',c.registration_number,'discipline',c.discipline,'valid_from',c.valid_from,'valid_until',c.valid_until,'verification_status',c.verification_status) order by c.created_at desc) from core.professional_credentials c where c.user_id=auth.uid()),'[]'::jsonb)
  );
end;$$;

revoke all on function public.register_engine_version(text,text,text,text,text,text,text,jsonb,jsonb,text,text,text) from public,anon;
grant execute on function public.register_engine_version(text,text,text,text,text,text,text,jsonb,jsonb,text,text,text) to authenticated;
revoke all on function public.add_engine_benchmark_case(uuid,text,text,text,text,text,jsonb,text,text) from public,anon;
grant execute on function public.add_engine_benchmark_case(uuid,text,text,text,text,text,jsonb,text,text) to authenticated;
revoke all on function public.record_engine_benchmark_result(uuid,boolean,jsonb,jsonb,text) from public,anon;
grant execute on function public.record_engine_benchmark_result(uuid,boolean,jsonb,jsonb,text) to authenticated;
revoke all on function public.set_engine_certification(uuid,text,text,text) from public,anon;
grant execute on function public.set_engine_certification(uuid,text,text,text) to authenticated;
revoke all on function public.register_mep_system(uuid,text,text,text,jsonb,text) from public,anon;
grant execute on function public.register_mep_system(uuid,text,text,text,jsonb,text) to authenticated;
revoke all on function public.record_engineering_calculation(uuid,text,text,uuid,text,text,jsonb,jsonb,text,text,text,jsonb,jsonb,text) from public,anon;
grant execute on function public.record_engineering_calculation(uuid,text,text,uuid,text,text,jsonb,jsonb,text,text,text,jsonb,jsonb,text) to authenticated;
revoke all on function public.review_engineering_calculation(uuid,uuid,text,text) from public,anon;
grant execute on function public.review_engineering_calculation(uuid,uuid,text,text) to authenticated;
revoke all on function public.list_engineering_validation_workspace() from public,anon;
grant execute on function public.list_engineering_validation_workspace() to authenticated;

commit;
