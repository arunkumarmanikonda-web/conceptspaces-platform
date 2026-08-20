begin;

create index if not exists engine_benchmark_results_current_idx
  on engineering.engine_benchmark_results(benchmark_case_id,engine_id,engine_version,executed_at desc,passed);
create index if not exists engineering_reviews_exact_hash_idx
  on engineering.professional_reviews(resource_type,resource_id,resource_hash,decision);
create index if not exists engineering_runs_engine_version_idx
  on engineering.calculation_runs(engine_id,engine_version,created_at desc);

-- Avoid repeated zero-argument authority evaluation where the planner can cache it.
drop policy if exists cs_read on engineering.engines;
create policy cs_read on engineering.engines for select to authenticated using (
  (select core.is_platform_admin()) or (enabled and certification_status in ('conditionally_approved','approved'))
);

drop policy if exists engineering_engine_governed_insert on engineering.engines;
create policy engineering_engine_governed_insert on engineering.engines for insert to authenticated with check (
  (select current_setting('conceptspaces.engineering_phase',true))='register_engine'
  and (select core.is_platform_admin())
  and certification_status='uncertified'
  and enabled=false
);

drop policy if exists engineering_engine_governed_update on engineering.engines;
create policy engineering_engine_governed_update on engineering.engines for update to authenticated using (
  (select current_setting('conceptspaces.engineering_phase',true))='certify_engine'
  and (select core.is_platform_admin())
) with check (
  (select current_setting('conceptspaces.engineering_phase',true))='certify_engine'
  and (select core.is_platform_admin())
);

drop policy if exists engineering_benchmark_case_governed_insert on engineering.engine_benchmark_cases;
create policy engineering_benchmark_case_governed_insert on engineering.engine_benchmark_cases for insert to authenticated with check (
  (select current_setting('conceptspaces.engineering_phase',true))='add_benchmark'
  and (select core.is_platform_admin())
);

drop policy if exists engineering_benchmark_result_governed_insert on engineering.engine_benchmark_results;
create policy engineering_benchmark_result_governed_insert on engineering.engine_benchmark_results for insert to authenticated with check (
  (select current_setting('conceptspaces.engineering_phase',true))='record_benchmark'
  and (select core.is_platform_admin())
);

drop policy if exists engineering_governance_admin_read on engineering.engine_governance_events;
create policy engineering_governance_admin_read on engineering.engine_governance_events for select to authenticated using ((select core.is_platform_admin()));

drop policy if exists engineering_governance_governed_insert on engineering.engine_governance_events;
create policy engineering_governance_governed_insert on engineering.engine_governance_events for insert to authenticated with check (
  (select core.is_platform_admin())
  and actor_id=(select auth.uid())
  and (select current_setting('conceptspaces.engineering_phase',true)) in ('register_engine','add_benchmark','record_benchmark','certify_engine')
);

create or replace function public.record_engineering_calculation(
  target_project_id uuid,target_discipline text,target_calculation_type text,target_engine_id uuid,target_input_snapshot_ref text,target_input_hash text,
  target_assumptions jsonb,target_standard_references jsonb,target_unit_system text,target_output_ref text,target_output_hash text,target_result_summary jsonb,target_evidence_refs jsonb,target_reason text
) returns uuid language plpgsql security invoker set search_path=public,engineering,project,audit,auth,pg_temp as $$
declare project_row project.projects%rowtype; target_engine engineering.engines%rowtype; new_run engineering.calculation_runs%rowtype;
begin
  if auth.uid() is null or not project.can_manage_project(target_project_id) then raise exception 'project_manage_authority_required'; end if;
  if nullif(btrim(target_discipline),'') is null then raise exception 'calculation_discipline_required'; end if;
  if nullif(btrim(target_unit_system),'') is null then raise exception 'unit_system_required'; end if;
  select * into project_row from project.projects where id=target_project_id; if not found then raise exception 'project_not_found'; end if;
  select * into target_engine from engineering.engines where id=target_engine_id; if not found then raise exception 'eligible_engine_not_found'; end if;
  if not target_engine.enabled or target_engine.certification_status not in ('conditionally_approved','approved') then raise exception 'engine_not_certified_and_enabled'; end if;
  if engineering.criticality_rank(project_row.criticality)>engineering.criticality_rank(target_engine.maximum_criticality) then raise exception 'engine_not_certified_for_project_criticality'; end if;
  if lower(target_engine.discipline) not in (lower(btrim(target_discipline)),'mep','mepf','multidiscipline') then raise exception 'engine_discipline_mismatch'; end if;
  if nullif(btrim(target_calculation_type),'') is null or nullif(btrim(target_input_snapshot_ref),'') is null or nullif(btrim(target_input_hash),'') is null or nullif(btrim(target_output_ref),'') is null or nullif(btrim(target_output_hash),'') is null then raise exception 'calculation_provenance_references_required'; end if;
  if jsonb_typeof(coalesce(target_assumptions,'[]'::jsonb))<>'array' or jsonb_typeof(coalesce(target_standard_references,'[]'::jsonb))<>'array' or jsonb_typeof(coalesce(target_evidence_refs,'[]'::jsonb))<>'array' or jsonb_typeof(coalesce(target_result_summary,'{}'::jsonb))<>'object' then raise exception 'invalid_calculation_json_shape'; end if;
  if jsonb_array_length(coalesce(target_standard_references,'[]'::jsonb))=0 or jsonb_array_length(coalesce(target_evidence_refs,'[]'::jsonb))=0 then raise exception 'standards_and_execution_evidence_required'; end if;
  if not (coalesce(target_standard_references,'[]'::jsonb) <@ target_engine.supported_standards) then raise exception 'calculation_standard_not_supported_by_engine'; end if;
  if not (target_engine.supported_units ? btrim(target_unit_system)) then raise exception 'unit_system_not_supported_by_engine'; end if;
  if nullif(btrim(target_reason),'') is null then raise exception 'calculation_reason_required'; end if;
  perform set_config('conceptspaces.engineering_phase','record_calculation',true);
  insert into engineering.calculation_runs(project_id,discipline,calculation_type,engine_id,engine_version,status,input_snapshot_ref,assumptions,standard_references,unit_system,output_ref,result_summary,evidence_refs,input_hash,output_hash,created_by,started_at,finished_at)
  values(target_project_id,lower(btrim(target_discipline)),btrim(target_calculation_type),target_engine.id,target_engine.version,'completed',btrim(target_input_snapshot_ref),coalesce(target_assumptions,'[]'::jsonb),target_standard_references,btrim(target_unit_system),btrim(target_output_ref),coalesce(target_result_summary,'{}'::jsonb),target_evidence_refs,btrim(target_input_hash),btrim(target_output_hash),auth.uid(),now(),now()) returning * into new_run;
  perform audit.append_event(project_row.organisation_id,target_project_id,'engineering.calculation_recorded','calculation',new_run.id,null,to_jsonb(new_run),btrim(target_reason),null);
  return new_run.id;
end;$$;

commit;
