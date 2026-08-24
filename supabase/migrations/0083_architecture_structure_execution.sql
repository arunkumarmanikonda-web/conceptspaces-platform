begin;

-- Package-level release provenance.
alter table engineering.architecture_packages add column if not exists criticality text not null default 'C2' check (criticality in ('C0','C1','C2','C3','C4'));
alter table engineering.architecture_packages add column if not exists approval_credential_id uuid references core.professional_credentials(id) on delete restrict;
alter table engineering.architecture_packages add column if not exists issue_hash text;
alter table engineering.structural_schemes add column if not exists criticality text not null default 'C3' check (criticality in ('C0','C1','C2','C3','C4'));
alter table engineering.structural_schemes add column if not exists approval_credential_id uuid references core.professional_credentials(id) on delete restrict;
alter table engineering.structural_schemes add column if not exists issue_hash text;

create or replace function engineering.guard_issued_design_package_mutation()
returns trigger
language plpgsql
security definer
set search_path='engineering','pg_temp'
as $$
begin
  if old.status='issued' then
    raise exception 'issued_design_package_immutable';
  end if;
  return new;
end;
$$;
revoke all on function engineering.guard_issued_design_package_mutation() from public,anon,authenticated;

drop trigger if exists trg_guard_issued_architecture_package on engineering.architecture_packages;
create trigger trg_guard_issued_architecture_package before update on engineering.architecture_packages
for each row execute function engineering.guard_issued_design_package_mutation();

drop trigger if exists trg_guard_issued_structural_scheme on engineering.structural_schemes;
create trigger trg_guard_issued_structural_scheme before update on engineering.structural_schemes
for each row execute function engineering.guard_issued_design_package_mutation();

create or replace function public.create_architecture_package(target_project_id uuid,input_payload jsonb)
returns uuid
language plpgsql
security invoker
set search_path='public','engineering','aec','project','audit','extensions','auth','pg_temp'
as $$
declare
  p project.projects%rowtype;
  pkg engineering.architecture_packages%rowtype;
  baseline aec.programme_baselines%rowtype;
  option_id uuid:=nullif(input_payload->>'design_option_id','')::uuid;
  stage_value text:=coalesce(nullif(lower(btrim(input_payload->>'stage')),''),'concept');
  version_value int;
  hash_value text;
begin
  select * into p from project.projects where id=target_project_id;
  if not found or auth.uid() is null or not project.can_manage_project(target_project_id) then raise exception 'architecture_authority_required'; end if;
  select * into baseline from aec.programme_baselines where project_id=target_project_id and status='approved' order by version desc limit 1;
  if not found then raise exception 'approved_programme_baseline_required'; end if;
  if option_id is not null and not exists(select 1 from aec.design_options o where o.id=option_id and o.project_id=target_project_id and o.status in ('validated','shortlisted','client_selected')) then raise exception 'validated_design_option_required'; end if;
  if jsonb_typeof(coalesce(input_payload->'drawing_refs','[]'::jsonb))<>'array' or jsonb_typeof(coalesce(input_payload->'model_refs','[]'::jsonb))<>'array' then raise exception 'architecture_reference_array_invalid'; end if;
  select coalesce(max(version),0)+1 into version_value from engineering.architecture_packages where project_id=target_project_id and stage=stage_value;
  hash_value:=encode(extensions.digest(jsonb_build_object(
    'project_id',target_project_id,'stage',stage_value,'version',version_value,'programme_hash',baseline.baseline_hash,
    'design_option_id',option_id,'circulation',coalesce(input_payload->'circulation_strategy','{}'::jsonb),
    'zoning',coalesce(input_payload->'zoning_strategy','{}'::jsonb),'drawing_refs',coalesce(input_payload->'drawing_refs','[]'::jsonb),
    'model_refs',coalesce(input_payload->'model_refs','[]'::jsonb),'coverage',coalesce(nullif(input_payload->>'requirement_coverage_percent','')::numeric,0),
    'source_model_hash',nullif(btrim(input_payload->>'source_model_hash'),''),'criticality',coalesce(nullif(input_payload->>'criticality',''),'C2')
  )::text,'sha256'),'hex');
  perform set_config('conceptspaces.design_phase','architecture',true);
  insert into engineering.architecture_packages(project_id,stage,version,space_programme_ref,circulation_strategy,zoning_strategy,drawing_refs,model_refs,requirement_coverage_percent,design_option_id,status,created_by,supersedes_package_id,package_hash,source_model_hash,criticality)
  values(target_project_id,stage_value,version_value,baseline.id::text,coalesce(input_payload->'circulation_strategy','{}'::jsonb),coalesce(input_payload->'zoning_strategy','{}'::jsonb),coalesce(input_payload->'drawing_refs','[]'::jsonb),coalesce(input_payload->'model_refs','[]'::jsonb),coalesce(nullif(input_payload->>'requirement_coverage_percent','')::numeric,0),option_id,'draft',auth.uid(),nullif(input_payload->>'supersedes_package_id','')::uuid,hash_value,nullif(btrim(input_payload->>'source_model_hash'),''),coalesce(nullif(input_payload->>'criticality',''),'C2')) returning * into pkg;
  perform audit.append_event(p.organisation_id,p.id,'architecture.package.created','architecture_package',pkg.id,null,to_jsonb(pkg),null,gen_random_uuid());
  return pkg.id;
end;
$$;
revoke all on function public.create_architecture_package(uuid,jsonb) from public,anon;
grant execute on function public.create_architecture_package(uuid,jsonb) to authenticated;

create or replace function public.transition_architecture_package(target_package_id uuid,target_status text,target_credential_id uuid,target_reason text,target_evidence_refs jsonb default '[]'::jsonb)
returns text
language plpgsql
security invoker
set search_path='public','engineering','project','governance','audit','extensions','auth','pg_temp'
as $$
declare
  pkg engineering.architecture_packages%rowtype;
  p project.projects%rowtype;
  value text:=lower(btrim(target_status));
  before_state jsonb;
  final_hash text;
begin
  select * into pkg from engineering.architecture_packages where id=target_package_id for update;
  if not found then raise exception 'architecture_package_not_found'; end if;
  select * into p from project.projects where id=pkg.project_id;
  if auth.uid() is null or not project.can_manage_project(pkg.project_id) then raise exception 'architecture_authority_required'; end if;
  if value not in ('coordinating','for_review','approved','issued') then raise exception 'architecture_status_invalid'; end if;
  if value='coordinating' and pkg.status<>'draft' then raise exception 'architecture_transition_invalid'; end if;
  if value='for_review' and pkg.status<>'coordinating' then raise exception 'architecture_transition_invalid'; end if;
  if value='approved' and pkg.status<>'for_review' then raise exception 'architecture_transition_invalid'; end if;
  if value='issued' and pkg.status<>'approved' then raise exception 'architecture_transition_invalid'; end if;
  if value in ('for_review','approved','issued') and (jsonb_typeof(coalesce(target_evidence_refs,'[]'::jsonb))<>'array' or jsonb_array_length(coalesce(target_evidence_refs,'[]'::jsonb))=0) then raise exception 'architecture_review_evidence_required'; end if;
  if value='approved' then
    if pkg.created_by=auth.uid() then raise exception 'architecture_maker_cannot_approve'; end if;
    if target_credential_id is null or not governance.credential_is_current_for_release(target_credential_id,auth.uid(),'architecture') then raise exception 'architecture_release_credential_required'; end if;
    perform set_config('conceptspaces.engineering_phase','record_review',true);
    insert into engineering.professional_reviews(project_id,resource_type,resource_id,resource_hash,discipline,reviewer_user_id,credential_id,decision,comments,reviewed_at)
    values(pkg.project_id,'design_package',pkg.id,pkg.package_hash,'architecture',auth.uid(),target_credential_id,'accepted',target_reason,now());
  end if;
  if value='issued' and (pkg.approved_by is null or pkg.approval_credential_id is null) then raise exception 'architecture_approval_required'; end if;
  before_state:=to_jsonb(pkg);
  final_hash:=case when value='issued' then encode(extensions.digest(jsonb_build_object('package_hash',pkg.package_hash,'approved_by',pkg.approved_by,'approval_credential_id',pkg.approval_credential_id,'issue_evidence',target_evidence_refs)::text,'sha256'),'hex') else pkg.issue_hash end;
  perform set_config('conceptspaces.design_phase','architecture',true);
  update engineering.architecture_packages set status=value,review_evidence_refs=case when value in ('for_review','approved','issued') then coalesce(target_evidence_refs,'[]'::jsonb) else review_evidence_refs end,approved_by=case when value='approved' then auth.uid() else approved_by end,approved_at=case when value='approved' then now() else approved_at end,approval_credential_id=case when value='approved' then target_credential_id else approval_credential_id end,issued_by=case when value='issued' then auth.uid() else issued_by end,issued_at=case when value='issued' then now() else issued_at end,issue_hash=final_hash,updated_at=now() where id=pkg.id returning * into pkg;
  perform audit.append_event(p.organisation_id,p.id,'architecture.package.'||value,'architecture_package',pkg.id,before_state,to_jsonb(pkg),target_reason,gen_random_uuid());
  return pkg.status;
end;
$$;
revoke all on function public.transition_architecture_package(uuid,text,uuid,text,jsonb) from public,anon;
grant execute on function public.transition_architecture_package(uuid,text,uuid,text,jsonb) to authenticated;

create or replace function public.create_structural_scheme(target_project_id uuid,input_payload jsonb)
returns uuid
language plpgsql
security invoker
set search_path='public','engineering','project','audit','extensions','auth','pg_temp'
as $$
declare
  p project.projects%rowtype;
  arch engineering.architecture_packages%rowtype;
  scheme engineering.structural_schemes%rowtype;
  version_value int;
  run_id text;
  hash_value text;
begin
  select * into p from project.projects where id=target_project_id;
  if not found or auth.uid() is null or not project.can_manage_project(target_project_id) then raise exception 'structural_authority_required'; end if;
  select * into arch from engineering.architecture_packages where id=nullif(input_payload->>'source_architecture_package_id','')::uuid and project_id=target_project_id and status in ('approved','issued');
  if not found then raise exception 'approved_architecture_package_required'; end if;
  if nullif(btrim(input_payload->>'system'),'') is null or nullif(btrim(input_payload->>'material_system'),'') is null then raise exception 'structural_basis_required'; end if;
  if jsonb_typeof(coalesce(input_payload->'calculation_run_ids','[]'::jsonb))<>'array' then raise exception 'structural_calculation_ids_invalid'; end if;
  for run_id in select jsonb_array_elements_text(coalesce(input_payload->'calculation_run_ids','[]'::jsonb)) loop
    if not exists(select 1 from engineering.calculation_runs r where r.id=run_id::uuid and r.project_id=target_project_id and lower(r.discipline) in ('structure','structural')) then raise exception 'structural_calculation_run_invalid:%',run_id; end if;
  end loop;
  select coalesce(max(version),0)+1 into version_value from engineering.structural_schemes where project_id=target_project_id;
  hash_value:=encode(extensions.digest(jsonb_build_object('project_id',target_project_id,'version',version_value,'architecture_package_id',arch.id,'architecture_hash',arch.package_hash,'system',input_payload->>'system','material_system',input_payload->>'material_system','grid_strategy',coalesce(input_payload->'grid_strategy','{}'::jsonb),'load_assumptions',coalesce(input_payload->'load_assumptions','{}'::jsonb),'design_standards',coalesce(input_payload->'design_standards','[]'::jsonb),'calculation_run_ids',coalesce(input_payload->'calculation_run_ids','[]'::jsonb),'criticality',coalesce(nullif(input_payload->>'criticality',''),'C3'))::text,'sha256'),'hex');
  perform set_config('conceptspaces.design_phase','structure',true);
  insert into engineering.structural_schemes(project_id,version,system,material_system,grid_strategy,load_assumptions,design_standards,analysis_model_ref,calculation_run_ids,model_refs,drawing_refs,status,created_by,supersedes_scheme_id,source_architecture_package_id,source_architecture_hash,scheme_hash,convergence_status,criticality)
  values(target_project_id,version_value,btrim(input_payload->>'system'),btrim(input_payload->>'material_system'),coalesce(input_payload->'grid_strategy','{}'::jsonb),coalesce(input_payload->'load_assumptions','{}'::jsonb),coalesce(input_payload->'design_standards','[]'::jsonb),nullif(btrim(input_payload->>'analysis_model_ref'),''),coalesce(input_payload->'calculation_run_ids','[]'::jsonb),coalesce(input_payload->'model_refs','[]'::jsonb),coalesce(input_payload->'drawing_refs','[]'::jsonb),'concept',auth.uid(),nullif(input_payload->>'supersedes_scheme_id','')::uuid,arch.id,arch.package_hash,hash_value,coalesce(nullif(input_payload->>'convergence_status',''),'not_run'),coalesce(nullif(input_payload->>'criticality',''),'C3')) returning * into scheme;
  perform audit.append_event(p.organisation_id,p.id,'structure.scheme.created','structural_scheme',scheme.id,null,to_jsonb(scheme),null,gen_random_uuid());
  return scheme.id;
end;
$$;
revoke all on function public.create_structural_scheme(uuid,jsonb) from public,anon;
grant execute on function public.create_structural_scheme(uuid,jsonb) to authenticated;

create or replace function public.transition_structural_scheme(target_scheme_id uuid,target_status text,target_credential_id uuid,target_reason text,target_evidence_refs jsonb default '[]'::jsonb,target_convergence_status text default null)
returns text
language plpgsql
security invoker
set search_path='public','engineering','project','governance','audit','extensions','auth','pg_temp'
as $$
declare
  s engineering.structural_schemes%rowtype;
  p project.projects%rowtype;
  arch engineering.architecture_packages%rowtype;
  value text:=lower(btrim(target_status));
  run_id text;
  before_state jsonb;
  final_hash text;
  accepted_review_count int;
begin
  select * into s from engineering.structural_schemes where id=target_scheme_id for update;
  if not found then raise exception 'structural_scheme_not_found'; end if;
  select * into p from project.projects where id=s.project_id;
  if auth.uid() is null or not project.can_manage_project(s.project_id) then raise exception 'structural_authority_required'; end if;
  select * into arch from engineering.architecture_packages where id=s.source_architecture_package_id;
  if arch.id is null or arch.status not in ('approved','issued') or arch.package_hash is distinct from s.source_architecture_hash then raise exception 'STRUCTURAL_ARCHITECTURE_STALE'; end if;
  if value not in ('analysis','coordination','for_review','approved','issued') then raise exception 'structural_status_invalid'; end if;
  if value='analysis' and s.status<>'concept' then raise exception 'structural_transition_invalid'; end if;
  if value='coordination' and s.status<>'analysis' then raise exception 'structural_transition_invalid'; end if;
  if value='for_review' and s.status<>'coordination' then raise exception 'structural_transition_invalid'; end if;
  if value='approved' and s.status<>'for_review' then raise exception 'structural_transition_invalid'; end if;
  if value='issued' and s.status<>'approved' then raise exception 'structural_transition_invalid'; end if;
  if target_convergence_status is not null and target_convergence_status not in ('not_run','converged','non_converged','failed') then raise exception 'structural_convergence_invalid'; end if;
  if value in ('for_review','approved','issued') then
    if jsonb_array_length(coalesce(s.calculation_run_ids,'[]'::jsonb))=0 then raise exception 'structural_calculation_required'; end if;
    for run_id in select jsonb_array_elements_text(s.calculation_run_ids) loop
      if not exists(select 1 from engineering.calculation_runs r join engineering.engines e on e.id=r.engine_id where r.id=run_id::uuid and r.project_id=s.project_id and r.status='completed' and r.output_hash is not null and jsonb_array_length(r.evidence_refs)>0 and e.enabled and e.certification_status in ('approved','conditionally_approved') and (case s.criticality when 'C4' then e.maximum_criticality='C4' when 'C3' then e.maximum_criticality in ('C3','C4') else true end)) then raise exception 'STRUCTURAL_CALCULATION_NOT_RELEASE_READY:%',run_id; end if;
      select count(*) into accepted_review_count from engineering.professional_reviews pr where pr.project_id=s.project_id and pr.resource_type='calculation' and pr.resource_id=run_id::uuid and pr.decision in ('accepted','accepted_with_comments') and governance.credential_is_current_for_release(pr.credential_id,pr.reviewer_user_id,'structure');
      if accepted_review_count=0 and s.criticality in ('C3','C4') then raise exception 'STRUCTURAL_CALCULATION_REVIEW_REQUIRED:%',run_id; end if;
    end loop;
    if coalesce(target_convergence_status,s.convergence_status)<>'converged' then raise exception 'ANALYSIS_NON_CONVERGED'; end if;
    if jsonb_typeof(coalesce(target_evidence_refs,'[]'::jsonb))<>'array' or jsonb_array_length(coalesce(target_evidence_refs,'[]'::jsonb))=0 then raise exception 'structural_review_evidence_required'; end if;
  end if;
  if value='approved' then
    if s.created_by=auth.uid() then raise exception 'structural_maker_cannot_approve'; end if;
    if target_credential_id is null or not governance.credential_is_current_for_release(target_credential_id,auth.uid(),'structure') then raise exception 'structural_release_credential_required'; end if;
    perform set_config('conceptspaces.engineering_phase','record_review',true);
    insert into engineering.professional_reviews(project_id,resource_type,resource_id,resource_hash,discipline,reviewer_user_id,credential_id,decision,comments,reviewed_at)
    values(s.project_id,'design_package',s.id,s.scheme_hash,'structure',auth.uid(),target_credential_id,'accepted',target_reason,now());
  end if;
  if value='issued' and (s.approved_by is null or s.approval_credential_id is null) then raise exception 'structural_approval_required'; end if;
  before_state:=to_jsonb(s);
  final_hash:=case when value='issued' then encode(extensions.digest(jsonb_build_object('scheme_hash',s.scheme_hash,'approved_by',s.approved_by,'approval_credential_id',s.approval_credential_id,'calculation_run_ids',s.calculation_run_ids,'issue_evidence',target_evidence_refs)::text,'sha256'),'hex') else s.issue_hash end;
  perform set_config('conceptspaces.design_phase','structure',true);
  update engineering.structural_schemes set status=value,convergence_status=coalesce(target_convergence_status,convergence_status),review_evidence_refs=case when value in ('for_review','approved','issued') then coalesce(target_evidence_refs,'[]'::jsonb) else review_evidence_refs end,approved_by=case when value='approved' then auth.uid() else approved_by end,approved_at=case when value='approved' then now() else approved_at end,approval_credential_id=case when value='approved' then target_credential_id else approval_credential_id end,issued_by=case when value='issued' then auth.uid() else issued_by end,issued_at=case when value='issued' then now() else issued_at end,issue_hash=final_hash,updated_at=now() where id=s.id returning * into s;
  perform audit.append_event(p.organisation_id,p.id,'structure.scheme.'||value,'structural_scheme',s.id,before_state,to_jsonb(s),target_reason,gen_random_uuid());
  return s.status;
end;
$$;
revoke all on function public.transition_structural_scheme(uuid,text,uuid,text,jsonb,text) from public,anon;
grant execute on function public.transition_structural_scheme(uuid,text,uuid,text,jsonb,text) to authenticated;

create or replace function public.list_architecture_workspace(target_project_id uuid)
returns jsonb
language plpgsql stable security invoker
set search_path='public','engineering','aec','project','core','auth','pg_temp'
as $$
begin
 if auth.uid() is null or not project.can_access_project(target_project_id) then raise exception 'project_access_required'; end if;
 return jsonb_build_object(
  'packages',coalesce((select jsonb_agg(to_jsonb(a) order by a.stage,a.version desc) from engineering.architecture_packages a where a.project_id=target_project_id),'[]'::jsonb),
  'programme_baselines',coalesce((select jsonb_agg(to_jsonb(b) order by b.version desc) from aec.programme_baselines b where b.project_id=target_project_id),'[]'::jsonb),
  'design_options',coalesce((select jsonb_agg(to_jsonb(o) order by o.created_at desc) from aec.design_options o where o.project_id=target_project_id),'[]'::jsonb),
  'reviews',coalesce((select jsonb_agg(to_jsonb(r) order by r.created_at desc) from engineering.professional_reviews r where r.project_id=target_project_id and r.resource_type='design_package' and r.discipline='architecture'),'[]'::jsonb),
  'credentials',coalesce((select jsonb_agg(jsonb_build_object('id',c.id,'discipline',c.discipline,'status',c.status,'expires_at',c.expires_at)) from core.professional_credentials c where c.user_id=auth.uid() and c.status='verified'),'[]'::jsonb)
 );
end;
$$;
revoke all on function public.list_architecture_workspace(uuid) from public,anon;
grant execute on function public.list_architecture_workspace(uuid) to authenticated;

create or replace function public.list_structure_workspace(target_project_id uuid)
returns jsonb
language plpgsql stable security invoker
set search_path='public','engineering','project','core','auth','pg_temp'
as $$
begin
 if auth.uid() is null or not project.can_access_project(target_project_id) then raise exception 'project_access_required'; end if;
 return jsonb_build_object(
  'schemes',coalesce((select jsonb_agg(to_jsonb(s) order by s.version desc) from engineering.structural_schemes s where s.project_id=target_project_id),'[]'::jsonb),
  'architecture_packages',coalesce((select jsonb_agg(to_jsonb(a) order by a.version desc) from engineering.architecture_packages a where a.project_id=target_project_id and a.status in ('approved','issued')),'[]'::jsonb),
  'calculation_runs',coalesce((select jsonb_agg(to_jsonb(r) order by r.created_at desc) from engineering.calculation_runs r where r.project_id=target_project_id and lower(r.discipline) in ('structure','structural')),'[]'::jsonb),
  'engines',coalesce((select jsonb_agg(to_jsonb(e) order by e.name,e.version) from engineering.engines e where lower(e.discipline) in ('structure','structural')),'[]'::jsonb),
  'reviews',coalesce((select jsonb_agg(to_jsonb(r) order by r.created_at desc) from engineering.professional_reviews r where r.project_id=target_project_id and r.discipline in ('structure','structural')),'[]'::jsonb),
  'credentials',coalesce((select jsonb_agg(jsonb_build_object('id',c.id,'discipline',c.discipline,'status',c.status,'expires_at',c.expires_at)) from core.professional_credentials c where c.user_id=auth.uid() and c.status='verified'),'[]'::jsonb)
 );
end;
$$;
revoke all on function public.list_structure_workspace(uuid) from public,anon;
grant execute on function public.list_structure_workspace(uuid) to authenticated;

commit;