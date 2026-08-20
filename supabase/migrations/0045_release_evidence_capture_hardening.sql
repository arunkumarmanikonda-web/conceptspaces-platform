begin;

create or replace function public.add_release_evidence(
  target_safety_case_id uuid,target_evidence_type text,target_reference text,target_evidence_hash text,target_passed boolean,target_payload jsonb,target_reason text
) returns uuid
language plpgsql security invoker
set search_path=public,governance,project,audit,auth,pg_temp
as $$
declare s governance.release_safety_cases%rowtype; g governance.release_gates%rowtype; ev governance.release_evidence%rowtype; project_org_id uuid; capture_mode text;
begin
  select * into s from governance.release_safety_cases where id=target_safety_case_id; if not found then raise exception 'release_safety_case_not_found'; end if;
  select * into g from governance.release_gates where id=s.gate_id; if not found then raise exception 'release_gate_not_found'; end if;
  if auth.uid() is null or not project.can_manage_project(s.project_id) then raise exception 'project_manage_authority_required'; end if;
  if s.state in ('approved','issued') then raise exception 'approved_or_issued_safety_case_is_frozen'; end if;
  if target_evidence_type not in ('truth_snapshot','regulatory_check','engineering_check','coordination_check','client_approval') then raise exception 'use_specialised_path_for_document_or_professional_evidence'; end if;
  if nullif(btrim(target_reference),'') is null or nullif(btrim(target_evidence_hash),'') is null then raise exception 'evidence_reference_and_hash_required'; end if;
  if jsonb_typeof(coalesce(target_payload,'{}'::jsonb))<>'object' then raise exception 'evidence_payload_must_be_object'; end if;
  if nullif(btrim(target_reason),'') is null then raise exception 'evidence_reason_required'; end if;
  capture_mode:=coalesce(current_setting('conceptspaces.release_capture',true),'');
  if target_passed and capture_mode<>target_evidence_type then raise exception 'passing_release_evidence_requires_platform_source_capture'; end if;
  select organisation_id into project_org_id from project.projects where id=s.project_id;
  perform set_config('conceptspaces.release_phase','add_evidence',true);
  insert into governance.release_evidence(project_id,gate_id,safety_case_id,package_content_hash,evidence_type,reference,evidence_hash,passed,payload,produced_by)
  values(s.project_id,g.id,s.id,s.content_hash,target_evidence_type,btrim(target_reference),btrim(target_evidence_hash),target_passed,coalesce(target_payload,'{}'::jsonb),auth.uid()) returning * into ev;
  if target_passed and not governance.release_evidence_is_current(ev.id) then raise exception 'release_evidence_not_current_or_not_verifiable'; end if;
  perform audit.append_event(project_org_id,s.project_id,'release.evidence_added','release_evidence',ev.id,null,to_jsonb(ev),btrim(target_reason),null);
  return ev.id;
end;$$;

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
  if not exists(select 1 from project.truth_records t where t.project_id=s.project_id and t.status<>'superseded') then raise exception 'project_truth_baseline_required'; end if;
  if exists(select 1 from project.truth_records t where t.project_id=s.project_id and engineering.criticality_rank(t.criticality)>=3 and (t.status<>'verified' or (t.valid_until is not null and t.valid_until<now()))) then raise exception 'critical_project_truth_not_verified'; end if;
  select coalesce(jsonb_agg(jsonb_build_object('id',t.id,'kind',t.kind,'record_key',t.record_key,'value',t.value,'unit',t.unit,'source_type',t.source_type,'source_reference',t.source_reference,'confidence',t.confidence,'status',t.status,'criticality',t.criticality,'valid_from',t.valid_from,'valid_until',t.valid_until,'verified_at',t.verified_at,'updated_at',t.updated_at) order by t.record_key,t.id),'[]'::jsonb)
  into snapshot from project.truth_records t where t.project_id=s.project_id and t.status<>'superseded';
  snapshot_hash:=encode(extensions.digest(snapshot::text,'sha256'),'hex');
  perform set_config('conceptspaces.release_capture','truth_snapshot',true);
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
  perform set_config('conceptspaces.release_capture','coordination_check',true);
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
  perform set_config('conceptspaces.release_capture','regulatory_check',true);
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
  perform set_config('conceptspaces.release_capture','engineering_check',true);
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
  perform set_config('conceptspaces.release_capture','client_approval',true);
  new_id:=public.add_release_evidence(s.id,'client_approval',btrim(target_approval_reference),s.content_hash,true,jsonb_build_object('approved_package_hash',s.content_hash),coalesce(nullif(btrim(target_reason),''),'Captured client approval for exact package hash'));
  return new_id;
end;$$;

commit;
