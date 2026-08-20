begin;

create or replace function public.capture_release_truth_snapshot(target_safety_case_id uuid,target_reason text)
returns uuid
language plpgsql security invoker
set search_path=public,governance,project,engineering,extensions,auth,pg_temp
as $$
declare s governance.release_safety_cases%rowtype; snapshot jsonb; snapshot_hash text; new_id uuid;
begin
  select * into s from governance.release_safety_cases where id=target_safety_case_id;
  if not found then raise exception 'release_safety_case_not_found'; end if;
  if auth.uid() is null or not project.can_manage_project(s.project_id) then raise exception 'project_manage_authority_required'; end if;
  if exists(select 1 from project.truth_records t where t.project_id=s.project_id and engineering.criticality_rank(t.criticality)>=3 and (t.status<>'verified' or (t.valid_until is not null and t.valid_until<now()))) then raise exception 'critical_project_truth_not_verified'; end if;
  select coalesce(jsonb_agg(jsonb_build_object('id',t.id,'kind',t.kind,'record_key',t.record_key,'value',t.value,'unit',t.unit,'source_type',t.source_type,'source_reference',t.source_reference,'confidence',t.confidence,'status',t.status,'criticality',t.criticality,'valid_from',t.valid_from,'valid_until',t.valid_until,'verified_at',t.verified_at,'updated_at',t.updated_at) order by t.record_key,t.id),'[]'::jsonb)
  into snapshot from project.truth_records t where t.project_id=s.project_id and t.status<>'superseded';
  snapshot_hash:=encode(extensions.digest(snapshot::text,'sha256'),'hex');
  new_id:=public.add_release_evidence(s.id,'truth_snapshot','project_truth:'||s.project_id::text,snapshot_hash,true,jsonb_build_object('record_count',jsonb_array_length(snapshot),'snapshot_hash',snapshot_hash),coalesce(nullif(btrim(target_reason),''),'Captured current Project Truth snapshot'));
  return new_id;
end;$$;

create or replace function public.capture_release_coordination_check(target_safety_case_id uuid,target_reason text)
returns uuid
language plpgsql security invoker
set search_path=public,governance,project,engineering,extensions,auth,pg_temp
as $$
declare s governance.release_safety_cases%rowtype; snapshot jsonb; snapshot_hash text; new_id uuid;
begin
  select * into s from governance.release_safety_cases where id=target_safety_case_id;
  if not found then raise exception 'release_safety_case_not_found'; end if;
  if auth.uid() is null or not project.can_manage_project(s.project_id) then raise exception 'project_manage_authority_required'; end if;
  if exists(select 1 from engineering.coordination_matrix c where c.project_id=s.project_id and c.state in ('open','coordinating')) then raise exception 'open_coordination_items_block_release'; end if;
  select coalesce(jsonb_agg(jsonb_build_object('id',c.id,'source_discipline',c.source_discipline,'target_discipline',c.target_discipline,'subject',c.subject,'requirement_ref',c.requirement_ref,'issue_ref',c.issue_ref,'state',c.state,'updated_at',c.updated_at) order by c.source_discipline,c.target_discipline,c.id),'[]'::jsonb)
  into snapshot from engineering.coordination_matrix c where c.project_id=s.project_id;
  snapshot_hash:=encode(extensions.digest(snapshot::text,'sha256'),'hex');
  new_id:=public.add_release_evidence(s.id,'coordination_check','coordination_matrix:'||s.project_id::text,snapshot_hash,true,jsonb_build_object('item_count',jsonb_array_length(snapshot),'snapshot_hash',snapshot_hash),coalesce(nullif(btrim(target_reason),''),'Captured resolved coordination state'));
  return new_id;
end;$$;

create or replace function public.capture_release_regulatory_check(target_safety_case_id uuid,target_evaluation_run_id uuid,target_reason text)
returns uuid
language plpgsql security invoker
set search_path=public,governance,project,regula,auth,pg_temp
as $$
declare s governance.release_safety_cases%rowtype; r regula.evaluation_runs%rowtype; new_id uuid;
begin
  select * into s from governance.release_safety_cases where id=target_safety_case_id;
  if not found then raise exception 'release_safety_case_not_found'; end if;
  if auth.uid() is null or not project.can_manage_project(s.project_id) then raise exception 'project_manage_authority_required'; end if;
  select * into r from regula.evaluation_runs where id=target_evaluation_run_id and project_id=s.project_id;
  if not found then raise exception 'regulatory_run_not_found_for_project'; end if;
  if r.status<>'completed' or r.result_hash is null or r.deterministic_failures<>0 or r.interpretation_required<>0 or r.not_verified<>0 then raise exception 'regulatory_run_not_release_clean'; end if;
  if r.id<>(select r2.id from regula.evaluation_runs r2 where r2.project_id=s.project_id and r2.status='completed' order by coalesce(r2.completed_at,r2.created_at) desc,r2.created_at desc limit 1) then raise exception 'latest_regulatory_run_required'; end if;
  new_id:=public.add_release_evidence(s.id,'regulatory_check',r.id::text,r.result_hash,true,jsonb_build_object('engine',r.engine,'engine_version',r.engine_version,'as_of',r.as_of,'rules_evaluated',r.rules_evaluated),coalesce(nullif(btrim(target_reason),''),'Captured latest clean REGULA evaluation'));
  return new_id;
end;$$;

create or replace function public.capture_release_engineering_check(target_safety_case_id uuid,target_calculation_run_id uuid,target_reason text)
returns uuid
language plpgsql security invoker
set search_path=public,governance,project,engineering,auth,pg_temp
as $$
declare s governance.release_safety_cases%rowtype; r engineering.calculation_runs%rowtype; en engineering.engines%rowtype; project_criticality text; new_id uuid;
begin
  select * into s from governance.release_safety_cases where id=target_safety_case_id;
  if not found then raise exception 'release_safety_case_not_found'; end if;
  if auth.uid() is null or not project.can_manage_project(s.project_id) then raise exception 'project_manage_authority_required'; end if;
  select * into r from engineering.calculation_runs where id=target_calculation_run_id and project_id=s.project_id;
  if not found then raise exception 'engineering_calculation_not_found_for_project'; end if;
  select * into en from engineering.engines where id=r.engine_id;
  select criticality into project_criticality from project.projects where id=s.project_id;
  if r.status<>'completed' or r.output_hash is null or en.id is null or not en.enabled or en.certification_status not in ('conditionally_approved','approved') or r.engine_version<>en.version or engineering.criticality_rank(project_criticality)>engineering.criticality_rank(en.maximum_criticality) then raise exception 'engineering_calculation_not_release_eligible'; end if;
  if not exists(select 1 from engineering.professional_reviews pr where pr.resource_type='calculation' and pr.resource_id=r.id and pr.resource_hash=r.output_hash and pr.decision in ('accepted','accepted_with_comments') and governance.credential_is_current_for_release(pr.credential_id,pr.reviewer_user_id,r.discipline)) then raise exception 'current_exact_hash_engineering_review_required'; end if;
  new_id:=public.add_release_evidence(s.id,'engineering_check',r.id::text,r.output_hash,true,jsonb_build_object('discipline',r.discipline,'calculation_type',r.calculation_type,'engine_id',r.engine_id,'engine_version',r.engine_version,'unit_system',r.unit_system,'output_ref',r.output_ref),coalesce(nullif(btrim(target_reason),''),'Captured professionally reviewed engineering calculation'));
  return new_id;
end;$$;

create or replace function public.capture_release_client_approval(target_safety_case_id uuid,target_approval_reference text,target_reason text)
returns uuid
language plpgsql security invoker
set search_path=public,governance,project,auth,pg_temp
as $$
declare s governance.release_safety_cases%rowtype; new_id uuid;
begin
  select * into s from governance.release_safety_cases where id=target_safety_case_id;
  if not found then raise exception 'release_safety_case_not_found'; end if;
  if auth.uid() is null or not project.can_manage_project(s.project_id) then raise exception 'project_manage_authority_required'; end if;
  if nullif(btrim(target_approval_reference),'') is null then raise exception 'client_approval_reference_required'; end if;
  new_id:=public.add_release_evidence(s.id,'client_approval',btrim(target_approval_reference),s.content_hash,true,jsonb_build_object('approved_package_hash',s.content_hash),coalesce(nullif(btrim(target_reason),''),'Captured client approval for exact package hash'));
  return new_id;
end;$$;

create or replace function public.list_release_assurance_workspace()
returns jsonb
language plpgsql stable security invoker
set search_path=public,governance,project,core,regula,engineering,auth,pg_temp
as $$
begin
  if auth.uid() is null then raise exception 'authentication_required'; end if;
  return jsonb_build_object(
    'gates',coalesce((select jsonb_agg(jsonb_build_object('id',g.id,'project_id',g.project_id,'project_code',p.code::text,'project_name',p.name,'gate_code',g.gate_code::text,'name',g.name,'discipline',g.discipline,'criticality',g.criticality,'state',g.state,'required_evidence_types',g.required_evidence_types,'unresolved_critical_defects',g.unresolved_critical_defects,'approved_by',g.approved_by,'approved_at',g.approved_at,'released_at',g.released_at,'created_at',g.created_at,'updated_at',g.updated_at) order by g.updated_at desc) from governance.release_gates g join project.projects p on p.id=g.project_id where project.can_access_project(g.project_id)),'[]'::jsonb),
    'safety_cases',coalesce((select jsonb_agg(to_jsonb(s) order by s.created_at desc) from governance.release_safety_cases s where project.can_access_project(s.project_id)),'[]'::jsonb),
    'evidence',coalesce((select jsonb_agg(jsonb_build_object('id',e.id,'project_id',e.project_id,'gate_id',e.gate_id,'safety_case_id',e.safety_case_id,'package_content_hash',e.package_content_hash,'evidence_type',e.evidence_type,'reference',e.reference,'evidence_hash',e.evidence_hash,'passed',e.passed,'current',governance.release_evidence_is_current(e.id),'payload',e.payload,'produced_by',e.produced_by,'produced_at',e.produced_at) order by e.produced_at desc) from governance.release_evidence e where project.can_access_project(e.project_id)),'[]'::jsonb),
    'exceptions',coalesce((select jsonb_agg(to_jsonb(ex) order by ex.created_at desc) from governance.exceptions ex where project.can_access_project(ex.project_id)),'[]'::jsonb),
    'package_reviews',coalesce((select jsonb_agg(to_jsonb(r) order by r.reviewed_at desc) from governance.release_package_reviews r where project.can_access_project(r.project_id)),'[]'::jsonb),
    'credentials',coalesce((select jsonb_agg(jsonb_build_object('id',c.id,'credential_type',c.credential_type,'issuing_body',c.issuing_body,'registration_number',c.registration_number,'discipline',c.discipline,'valid_from',c.valid_from,'valid_until',c.valid_until,'verification_status',c.verification_status) order by c.created_at desc) from core.professional_credentials c where c.user_id=auth.uid()),'[]'::jsonb),
    'regulatory_runs',coalesce((select jsonb_agg(jsonb_build_object('id',r.id,'project_id',r.project_id,'as_of',r.as_of,'engine',r.engine,'engine_version',r.engine_version,'result_hash',r.result_hash,'status',r.status,'rules_evaluated',r.rules_evaluated,'deterministic_failures',r.deterministic_failures,'interpretation_required',r.interpretation_required,'not_verified',r.not_verified,'completed_at',r.completed_at,'created_at',r.created_at,'is_latest_completed',r.id=(select r2.id from regula.evaluation_runs r2 where r2.project_id=r.project_id and r2.status='completed' order by coalesce(r2.completed_at,r2.created_at) desc,r2.created_at desc limit 1)) order by coalesce(r.completed_at,r.created_at) desc) from regula.evaluation_runs r where project.can_access_project(r.project_id)),'[]'::jsonb),
    'engineering_runs',coalesce((select jsonb_agg(jsonb_build_object('id',r.id,'project_id',r.project_id,'discipline',r.discipline,'calculation_type',r.calculation_type,'engine_id',r.engine_id,'engine_version',r.engine_version,'status',r.status,'output_ref',r.output_ref,'output_hash',r.output_hash,'unit_system',r.unit_system,'finished_at',r.finished_at,'release_eligible',r.status='completed' and r.output_hash is not null and en.enabled and en.certification_status in ('conditionally_approved','approved') and r.engine_version=en.version and engineering.criticality_rank(p.criticality)<=engineering.criticality_rank(en.maximum_criticality) and exists(select 1 from engineering.professional_reviews pr where pr.resource_type='calculation' and pr.resource_id=r.id and pr.resource_hash=r.output_hash and pr.decision in ('accepted','accepted_with_comments') and governance.credential_is_current_for_release(pr.credential_id,pr.reviewer_user_id,r.discipline))) order by coalesce(r.finished_at,r.created_at) desc) from engineering.calculation_runs r join engineering.engines en on en.id=r.engine_id join project.projects p on p.id=r.project_id where project.can_access_project(r.project_id)),'[]'::jsonb)
  );
end;$$;

revoke all on function public.capture_release_truth_snapshot(uuid,text) from public,anon;
grant execute on function public.capture_release_truth_snapshot(uuid,text) to authenticated;
revoke all on function public.capture_release_coordination_check(uuid,text) from public,anon;
grant execute on function public.capture_release_coordination_check(uuid,text) to authenticated;
revoke all on function public.capture_release_regulatory_check(uuid,uuid,text) from public,anon;
grant execute on function public.capture_release_regulatory_check(uuid,uuid,text) to authenticated;
revoke all on function public.capture_release_engineering_check(uuid,uuid,text) from public,anon;
grant execute on function public.capture_release_engineering_check(uuid,uuid,text) to authenticated;
revoke all on function public.capture_release_client_approval(uuid,text,text) from public,anon;
grant execute on function public.capture_release_client_approval(uuid,text,text) to authenticated;

commit;
