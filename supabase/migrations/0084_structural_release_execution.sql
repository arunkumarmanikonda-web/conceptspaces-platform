begin;

create or replace function public.create_structural_scheme(target_project_id uuid,input_payload jsonb)
returns uuid language plpgsql security invoker set search_path='public','engineering','project','audit','extensions','auth','pg_temp' as $$
declare p project.projects%rowtype; arch engineering.architecture_packages%rowtype; scheme engineering.structural_schemes%rowtype; version_value int; run_id text; hash_value text; criticality_value text:=coalesce(nullif(upper(btrim(input_payload->>'criticality')),''),'C3');
begin
  select * into p from project.projects where id=target_project_id;
  if not found or auth.uid() is null or not project.can_manage_project(target_project_id) then raise exception 'structural_authority_required'; end if;
  select * into arch from engineering.architecture_packages where id=nullif(input_payload->>'source_architecture_package_id','')::uuid and project_id=target_project_id and status in ('approved','issued');
  if not found then raise exception 'approved_architecture_package_required'; end if;
  if criticality_value not in ('C0','C1','C2','C3','C4') then raise exception 'structural_criticality_invalid'; end if;
  if nullif(btrim(input_payload->>'system'),'') is null or nullif(btrim(input_payload->>'material_system'),'') is null then raise exception 'structural_basis_required'; end if;
  if jsonb_typeof(coalesce(input_payload->'load_assumptions','{}'::jsonb))<>'object' or jsonb_typeof(coalesce(input_payload->'design_standards','[]'::jsonb))<>'array' or jsonb_typeof(coalesce(input_payload->'calculation_run_ids','[]'::jsonb))<>'array' then raise exception 'structural_payload_invalid'; end if;
  for run_id in select jsonb_array_elements_text(coalesce(input_payload->'calculation_run_ids','[]'::jsonb)) loop
    if not exists(select 1 from engineering.calculation_runs r where r.id=run_id::uuid and r.project_id=target_project_id and lower(r.discipline) in ('structure','structural')) then raise exception 'structural_calculation_run_invalid:%',run_id; end if;
  end loop;
  select coalesce(max(version),0)+1 into version_value from engineering.structural_schemes where project_id=target_project_id;
  hash_value:=encode(extensions.digest(jsonb_build_object('project_id',target_project_id,'version',version_value,'architecture_package_id',arch.id,'architecture_hash',arch.package_hash,'system',input_payload->>'system','material_system',input_payload->>'material_system','grid_strategy',coalesce(input_payload->'grid_strategy','{}'::jsonb),'load_assumptions',input_payload->'load_assumptions','design_standards',input_payload->'design_standards','calculation_run_ids',input_payload->'calculation_run_ids','criticality',criticality_value)::text,'sha256'),'hex');
  perform set_config('conceptspaces.design_phase','structure',true);
  insert into engineering.structural_schemes(project_id,version,system,material_system,grid_strategy,load_assumptions,design_standards,analysis_model_ref,calculation_run_ids,model_refs,drawing_refs,status,created_by,supersedes_scheme_id,source_architecture_package_id,source_architecture_hash,scheme_hash,convergence_status,criticality)
  values(target_project_id,version_value,btrim(input_payload->>'system'),btrim(input_payload->>'material_system'),coalesce(input_payload->'grid_strategy','{}'::jsonb),input_payload->'load_assumptions',input_payload->'design_standards',nullif(btrim(input_payload->>'analysis_model_ref'),''),input_payload->'calculation_run_ids',coalesce(input_payload->'model_refs','[]'::jsonb),coalesce(input_payload->'drawing_refs','[]'::jsonb),'concept',auth.uid(),nullif(input_payload->>'supersedes_scheme_id','')::uuid,arch.id,arch.package_hash,hash_value,coalesce(nullif(lower(input_payload->>'convergence_status'),''),'not_run'),criticality_value) returning * into scheme;
  perform audit.append_event(p.organisation_id,p.id,'structure.scheme.created','structural_scheme',scheme.id,null,to_jsonb(scheme),null,gen_random_uuid());
  return scheme.id;
end;$$;
revoke all on function public.create_structural_scheme(uuid,jsonb) from public,anon;
grant execute on function public.create_structural_scheme(uuid,jsonb) to authenticated;

create or replace function public.transition_structural_scheme(target_scheme_id uuid,target_status text,target_credential_id uuid,target_reason text,target_evidence_refs jsonb default '[]'::jsonb,target_convergence_status text default null)
returns text language plpgsql security invoker set search_path='public','engineering','project','governance','audit','extensions','auth','pg_temp' as $$
declare s engineering.structural_schemes%rowtype; p project.projects%rowtype; arch engineering.architecture_packages%rowtype; latest_arch engineering.architecture_packages%rowtype; value text:=lower(btrim(target_status)); convergence_value text:=coalesce(nullif(lower(btrim(target_convergence_status)),''),s.convergence_status); run_id text; before_state jsonb; final_hash text; accepted_review_count int; credential_ok boolean;
begin
  select * into s from engineering.structural_schemes where id=target_scheme_id for update;
  if not found then raise exception 'structural_scheme_not_found'; end if;
  convergence_value:=coalesce(nullif(lower(btrim(target_convergence_status)),''),s.convergence_status);
  select * into p from project.projects where id=s.project_id;
  if auth.uid() is null or not project.can_manage_project(s.project_id) then raise exception 'structural_authority_required'; end if;
  if nullif(btrim(target_reason),'') is null then raise exception 'structural_transition_reason_required'; end if;
  select * into arch from engineering.architecture_packages where id=s.source_architecture_package_id;
  if arch.id is null or arch.status not in ('approved','issued') or arch.package_hash is distinct from s.source_architecture_hash then raise exception 'STRUCTURAL_ARCHITECTURE_STALE'; end if;
  select * into latest_arch from engineering.architecture_packages where project_id=s.project_id and status in ('approved','issued') order by coalesce(issued_at,approved_at,updated_at) desc,version desc limit 1;
  if latest_arch.id is distinct from arch.id and coalesce(latest_arch.issued_at,latest_arch.approved_at,latest_arch.updated_at)>coalesce(arch.issued_at,arch.approved_at,arch.updated_at) then raise exception 'STRUCTURAL_ARCHITECTURE_SUPERSEDED'; end if;
  if not ((s.status='concept' and value='analysis') or (s.status='analysis' and value='coordination') or (s.status='coordination' and value='for_review') or (s.status='for_review' and value='approved') or (s.status='approved' and value='issued')) then raise exception 'structural_transition_invalid'; end if;
  if convergence_value not in ('not_run','converged','non_converged','failed') then raise exception 'structural_convergence_invalid'; end if;
  if value in ('for_review','approved','issued') then
    if coalesce(s.load_assumptions->>'geotechnical_status','') not in ('verified','not_required') then raise exception 'GEOTECH_REQUIRED'; end if;
    if s.load_assumptions->>'geotechnical_status'='not_required' and nullif(btrim(s.load_assumptions->>'geotechnical_reason'),'') is null then raise exception 'GEOTECH_NOT_REQUIRED_REASON_REQUIRED'; end if;
    if jsonb_array_length(coalesce(s.design_standards,'[]'::jsonb))=0 then raise exception 'structural_design_standard_required'; end if;
    if jsonb_array_length(coalesce(s.calculation_run_ids,'[]'::jsonb))=0 then raise exception 'structural_calculation_required'; end if;
    for run_id in select jsonb_array_elements_text(s.calculation_run_ids) loop
      if not exists(select 1 from engineering.calculation_runs r join engineering.engines e on e.id=r.engine_id where r.id=run_id::uuid and r.project_id=s.project_id and r.status='completed' and r.output_hash is not null and jsonb_array_length(r.evidence_refs)>0 and e.enabled and e.certification_status in ('approved','conditionally_approved') and r.engine_version=e.version and engineering.criticality_rank(s.criticality)<=engineering.criticality_rank(e.maximum_criticality)) then raise exception 'STRUCTURAL_CALCULATION_NOT_RELEASE_READY:%',run_id; end if;
      select count(*) into accepted_review_count from engineering.professional_reviews pr join engineering.calculation_runs cr on cr.id=pr.resource_id where pr.project_id=s.project_id and pr.resource_type='calculation' and pr.resource_id=run_id::uuid and pr.resource_hash=cr.output_hash and pr.decision in ('accepted','accepted_with_comments') and (governance.credential_is_current_for_release(pr.credential_id,pr.reviewer_user_id,'structure') or governance.credential_is_current_for_release(pr.credential_id,pr.reviewer_user_id,'structural'));
      if accepted_review_count=0 and s.criticality in ('C3','C4') then raise exception 'STRUCTURAL_CALCULATION_REVIEW_REQUIRED:%',run_id; end if;
    end loop;
    if convergence_value<>'converged' then raise exception 'ANALYSIS_NON_CONVERGED'; end if;
    if jsonb_typeof(coalesce(target_evidence_refs,'[]'::jsonb))<>'array' or jsonb_array_length(coalesce(target_evidence_refs,'[]'::jsonb))=0 then raise exception 'structural_review_evidence_required'; end if;
  end if;
  if value='approved' then
    if s.created_by=auth.uid() then raise exception 'structural_maker_cannot_approve'; end if;
    credential_ok:=target_credential_id is not null and (governance.credential_is_current_for_release(target_credential_id,auth.uid(),'structure') or governance.credential_is_current_for_release(target_credential_id,auth.uid(),'structural'));
    if not credential_ok then raise exception 'structural_release_credential_required'; end if;
    perform set_config('conceptspaces.engineering_phase','record_review',true);
    insert into engineering.professional_reviews(project_id,resource_type,resource_id,resource_hash,discipline,reviewer_user_id,credential_id,decision,comments,reviewed_at) values(s.project_id,'design_package',s.id,s.scheme_hash,'structural',auth.uid(),target_credential_id,'accepted',target_reason,now());
  end if;
  if value='issued' and (s.approved_by is null or s.approval_credential_id is null) then raise exception 'structural_approval_required'; end if;
  before_state:=to_jsonb(s);
  final_hash:=case when value='issued' then encode(extensions.digest(jsonb_build_object('scheme_hash',s.scheme_hash,'approved_by',s.approved_by,'approval_credential_id',s.approval_credential_id,'calculation_run_ids',s.calculation_run_ids,'issue_evidence',target_evidence_refs)::text,'sha256'),'hex') else s.issue_hash end;
  perform set_config('conceptspaces.design_phase','structure',true);
  update engineering.structural_schemes set status=value,convergence_status=convergence_value,review_evidence_refs=case when value in ('for_review','approved','issued') then target_evidence_refs else review_evidence_refs end,approved_by=case when value='approved' then auth.uid() else approved_by end,approved_at=case when value='approved' then now() else approved_at end,approval_credential_id=case when value='approved' then target_credential_id else approval_credential_id end,issued_by=case when value='issued' then auth.uid() else issued_by end,issued_at=case when value='issued' then now() else issued_at end,issue_hash=final_hash,updated_at=now() where id=s.id returning * into s;
  perform audit.append_event(p.organisation_id,p.id,'structure.scheme.'||value,'structural_scheme',s.id,before_state,to_jsonb(s),target_reason,gen_random_uuid());
  return s.status;
end;$$;
revoke all on function public.transition_structural_scheme(uuid,text,uuid,text,jsonb,text) from public,anon;
grant execute on function public.transition_structural_scheme(uuid,text,uuid,text,jsonb,text) to authenticated;

create or replace function public.list_structure_workspace(target_project_id uuid)
returns jsonb language plpgsql stable security invoker set search_path='public','engineering','project','auth','pg_temp' as $$
begin
 if auth.uid() is null or not project.can_access_project(target_project_id) then raise exception 'project_access_required'; end if;
 return jsonb_build_object(
  'schemes',coalesce((select jsonb_agg(to_jsonb(s) order by s.version desc) from engineering.structural_schemes s where s.project_id=target_project_id),'[]'::jsonb),
  'architecture_packages',coalesce((select jsonb_agg(to_jsonb(a) order by coalesce(a.issued_at,a.approved_at,a.updated_at) desc) from engineering.architecture_packages a where a.project_id=target_project_id and a.status in ('approved','issued')),'[]'::jsonb),
  'calculation_runs',coalesce((select jsonb_agg(to_jsonb(r) order by r.created_at desc) from engineering.calculation_runs r where r.project_id=target_project_id and lower(r.discipline) in ('structure','structural')),'[]'::jsonb),
  'engines',coalesce((select jsonb_agg(to_jsonb(e) order by e.name,e.version) from engineering.engines e where lower(e.discipline) in ('structure','structural')),'[]'::jsonb),
  'reviews',coalesce((select jsonb_agg(to_jsonb(r) order by r.created_at desc) from engineering.professional_reviews r where r.project_id=target_project_id and r.discipline in ('structure','structural')),'[]'::jsonb)
 );
end;$$;
revoke all on function public.list_structure_workspace(uuid) from public,anon;
grant execute on function public.list_structure_workspace(uuid) to authenticated;

commit;