begin;

alter table engineering.architecture_packages
  add column if not exists criticality text not null default 'C2' check (criticality in ('C0','C1','C2','C3','C4')),
  add column if not exists approval_credential_id uuid references core.professional_credentials(id) on delete restrict,
  add column if not exists issue_hash text;

alter table engineering.structural_schemes
  add column if not exists criticality text not null default 'C3' check (criticality in ('C0','C1','C2','C3','C4')),
  add column if not exists approval_credential_id uuid references core.professional_credentials(id) on delete restrict,
  add column if not exists issue_hash text;

create or replace function engineering.guard_issued_design_package_mutation()
returns trigger language plpgsql security definer set search_path='engineering','pg_temp' as $$
begin
  if old.status='issued' then raise exception 'issued_design_package_immutable'; end if;
  return new;
end;$$;
revoke all on function engineering.guard_issued_design_package_mutation() from public,anon,authenticated;

drop trigger if exists trg_guard_issued_architecture_package on engineering.architecture_packages;
create trigger trg_guard_issued_architecture_package before update on engineering.architecture_packages for each row execute function engineering.guard_issued_design_package_mutation();
drop trigger if exists trg_guard_issued_structural_scheme on engineering.structural_schemes;
create trigger trg_guard_issued_structural_scheme before update on engineering.structural_schemes for each row execute function engineering.guard_issued_design_package_mutation();

create or replace function public.create_architecture_package(target_project_id uuid,input_payload jsonb)
returns uuid language plpgsql security invoker set search_path='public','engineering','aec','project','audit','extensions','auth','pg_temp' as $$
declare p project.projects%rowtype; pkg engineering.architecture_packages%rowtype; baseline aec.programme_baselines%rowtype; option_id uuid:=nullif(input_payload->>'design_option_id','')::uuid; stage_value text:=coalesce(nullif(lower(btrim(input_payload->>'stage')),''),'concept'); version_value int; hash_value text; criticality_value text:=coalesce(nullif(upper(btrim(input_payload->>'criticality')),''),'C2');
begin
  select * into p from project.projects where id=target_project_id;
  if not found or auth.uid() is null or not project.can_manage_project(target_project_id) then raise exception 'architecture_authority_required'; end if;
  select * into baseline from aec.programme_baselines where project_id=target_project_id and status='approved' order by version desc limit 1;
  if not found then raise exception 'approved_programme_baseline_required'; end if;
  if criticality_value not in ('C0','C1','C2','C3','C4') then raise exception 'architecture_criticality_invalid'; end if;
  if option_id is not null and not exists(select 1 from aec.design_options o where o.id=option_id and o.project_id=target_project_id and o.status in ('validated','shortlisted','client_selected')) then raise exception 'validated_design_option_required'; end if;
  if jsonb_typeof(coalesce(input_payload->'drawing_refs','[]'::jsonb))<>'array' or jsonb_typeof(coalesce(input_payload->'model_refs','[]'::jsonb))<>'array' then raise exception 'architecture_reference_array_invalid'; end if;
  select coalesce(max(version),0)+1 into version_value from engineering.architecture_packages where project_id=target_project_id and stage=stage_value;
  hash_value:=encode(extensions.digest(jsonb_build_object('project_id',target_project_id,'stage',stage_value,'version',version_value,'programme_hash',baseline.programme_hash,'design_option_id',option_id,'circulation',coalesce(input_payload->'circulation_strategy','{}'::jsonb),'zoning',coalesce(input_payload->'zoning_strategy','{}'::jsonb),'drawing_refs',coalesce(input_payload->'drawing_refs','[]'::jsonb),'model_refs',coalesce(input_payload->'model_refs','[]'::jsonb),'coverage',coalesce(nullif(input_payload->>'requirement_coverage_percent','')::numeric,0),'source_model_hash',nullif(btrim(input_payload->>'source_model_hash'),''),'criticality',criticality_value)::text,'sha256'),'hex');
  perform set_config('conceptspaces.design_phase','architecture',true);
  insert into engineering.architecture_packages(project_id,stage,version,space_programme_ref,circulation_strategy,zoning_strategy,drawing_refs,model_refs,requirement_coverage_percent,design_option_id,status,created_by,supersedes_package_id,package_hash,source_model_hash,criticality)
  values(target_project_id,stage_value,version_value,baseline.id::text,coalesce(input_payload->'circulation_strategy','{}'::jsonb),coalesce(input_payload->'zoning_strategy','{}'::jsonb),coalesce(input_payload->'drawing_refs','[]'::jsonb),coalesce(input_payload->'model_refs','[]'::jsonb),coalesce(nullif(input_payload->>'requirement_coverage_percent','')::numeric,0),option_id,'draft',auth.uid(),nullif(input_payload->>'supersedes_package_id','')::uuid,hash_value,nullif(btrim(input_payload->>'source_model_hash'),''),criticality_value) returning * into pkg;
  perform audit.append_event(p.organisation_id,p.id,'architecture.package.created','architecture_package',pkg.id,null,to_jsonb(pkg),null,gen_random_uuid());
  return pkg.id;
end;$$;
revoke all on function public.create_architecture_package(uuid,jsonb) from public,anon;
grant execute on function public.create_architecture_package(uuid,jsonb) to authenticated;

create or replace function public.transition_architecture_package(target_package_id uuid,target_status text,target_credential_id uuid,target_reason text,target_evidence_refs jsonb default '[]'::jsonb)
returns text language plpgsql security invoker set search_path='public','engineering','project','governance','audit','extensions','auth','pg_temp' as $$
declare pkg engineering.architecture_packages%rowtype; p project.projects%rowtype; value text:=lower(btrim(target_status)); before_state jsonb; final_hash text; credential_ok boolean;
begin
  select * into pkg from engineering.architecture_packages where id=target_package_id for update;
  if not found then raise exception 'architecture_package_not_found'; end if;
  select * into p from project.projects where id=pkg.project_id;
  if auth.uid() is null or not project.can_manage_project(pkg.project_id) then raise exception 'architecture_authority_required'; end if;
  if nullif(btrim(target_reason),'') is null then raise exception 'architecture_transition_reason_required'; end if;
  if not ((pkg.status='draft' and value='coordinating') or (pkg.status='coordinating' and value='for_review') or (pkg.status='for_review' and value='approved') or (pkg.status='approved' and value='issued')) then raise exception 'architecture_transition_invalid'; end if;
  if value in ('for_review','approved','issued') and (jsonb_typeof(coalesce(target_evidence_refs,'[]'::jsonb))<>'array' or jsonb_array_length(coalesce(target_evidence_refs,'[]'::jsonb))=0) then raise exception 'architecture_review_evidence_required'; end if;
  if value='approved' then
    if pkg.created_by=auth.uid() then raise exception 'architecture_maker_cannot_approve'; end if;
    credential_ok:=target_credential_id is not null and (governance.credential_is_current_for_release(target_credential_id,auth.uid(),'architecture') or governance.credential_is_current_for_release(target_credential_id,auth.uid(),'architectural'));
    if not credential_ok then raise exception 'architecture_release_credential_required'; end if;
    perform set_config('conceptspaces.engineering_phase','record_review',true);
    insert into engineering.professional_reviews(project_id,resource_type,resource_id,resource_hash,discipline,reviewer_user_id,credential_id,decision,comments,reviewed_at) values(pkg.project_id,'design_package',pkg.id,pkg.package_hash,'architecture',auth.uid(),target_credential_id,'accepted',target_reason,now());
  end if;
  if value='issued' and (pkg.approved_by is null or pkg.approval_credential_id is null) then raise exception 'architecture_approval_required'; end if;
  before_state:=to_jsonb(pkg);
  final_hash:=case when value='issued' then encode(extensions.digest(jsonb_build_object('package_hash',pkg.package_hash,'approved_by',pkg.approved_by,'approval_credential_id',pkg.approval_credential_id,'issue_evidence',target_evidence_refs)::text,'sha256'),'hex') else pkg.issue_hash end;
  perform set_config('conceptspaces.design_phase','architecture',true);
  update engineering.architecture_packages set status=value,review_evidence_refs=case when value in ('for_review','approved','issued') then target_evidence_refs else review_evidence_refs end,approved_by=case when value='approved' then auth.uid() else approved_by end,approved_at=case when value='approved' then now() else approved_at end,approval_credential_id=case when value='approved' then target_credential_id else approval_credential_id end,issued_by=case when value='issued' then auth.uid() else issued_by end,issued_at=case when value='issued' then now() else issued_at end,issue_hash=final_hash,updated_at=now() where id=pkg.id returning * into pkg;
  perform audit.append_event(p.organisation_id,p.id,'architecture.package.'||value,'architecture_package',pkg.id,before_state,to_jsonb(pkg),target_reason,gen_random_uuid());
  return pkg.status;
end;$$;
revoke all on function public.transition_architecture_package(uuid,text,uuid,text,jsonb) from public,anon;
grant execute on function public.transition_architecture_package(uuid,text,uuid,text,jsonb) to authenticated;

create or replace function public.list_architecture_workspace(target_project_id uuid)
returns jsonb language plpgsql stable security invoker set search_path='public','engineering','aec','project','core','auth','pg_temp' as $$
begin
 if auth.uid() is null or not project.can_access_project(target_project_id) then raise exception 'project_access_required'; end if;
 return jsonb_build_object(
  'packages',coalesce((select jsonb_agg(to_jsonb(a) order by a.stage,a.version desc) from engineering.architecture_packages a where a.project_id=target_project_id),'[]'::jsonb),
  'programme_baselines',coalesce((select jsonb_agg(to_jsonb(b) order by b.version desc) from aec.programme_baselines b where b.project_id=target_project_id),'[]'::jsonb),
  'design_options',coalesce((select jsonb_agg(to_jsonb(o) order by o.created_at desc) from aec.design_options o where o.project_id=target_project_id),'[]'::jsonb),
  'reviews',coalesce((select jsonb_agg(to_jsonb(r) order by r.created_at desc) from engineering.professional_reviews r where r.project_id=target_project_id and r.resource_type='design_package' and r.discipline='architecture'),'[]'::jsonb)
 );
end;$$;
revoke all on function public.list_architecture_workspace(uuid) from public,anon;
grant execute on function public.list_architecture_workspace(uuid) to authenticated;

commit;