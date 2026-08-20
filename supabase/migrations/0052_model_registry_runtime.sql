begin;

alter table cde.models add column if not exists revision text not null default 'P01';
alter table cde.models add column if not exists supersedes_model_id uuid references cde.models(id) on delete set null;
alter table cde.models add column if not exists approved_by uuid references auth.users(id);
alter table cde.models add column if not exists approved_at timestamptz;
alter table cde.models add column if not exists issued_by uuid references auth.users(id);
alter table cde.models add column if not exists issued_at timestamptz;
alter table cde.models add column if not exists validation_summary jsonb not null default '{}'::jsonb;
alter table cde.models add column if not exists validation_hash text;
create index if not exists models_project_status_idx on cde.models(project_id,status,updated_at desc);
create index if not exists models_supersedes_idx on cde.models(supersedes_model_id) where supersedes_model_id is not null;

create table if not exists cde.model_validation_runs(
  id uuid primary key default gen_random_uuid(),
  project_id uuid not null references project.projects(id) on delete cascade,
  model_id uuid not null references cde.models(id) on delete cascade,
  validation_type text not null check(validation_type in ('ifc','ids','geometry','semantic','round_trip')),
  adapter_key text,
  adapter_version text,
  passed boolean not null,
  result_hash text not null,
  findings jsonb not null default '[]'::jsonb,
  evidence_refs jsonb not null default '[]'::jsonb,
  created_by uuid references auth.users(id),
  created_at timestamptz not null default now()
);
create index if not exists model_validation_runs_model_idx on cde.model_validation_runs(model_id,created_at desc);

alter table cde.model_validation_runs enable row level security;
drop policy if exists model_validation_runs_read on cde.model_validation_runs;
create policy model_validation_runs_read on cde.model_validation_runs for select to authenticated using(project.can_access_project(project_id));
drop policy if exists model_validation_runs_insert on cde.model_validation_runs;
create policy model_validation_runs_insert on cde.model_validation_runs for insert to authenticated with check(
  project.can_manage_project(project_id)
  and created_by=auth.uid()
  and current_setting('conceptspaces.model_phase',true)='validate'
);

grant select on cde.model_validation_runs to authenticated;
grant insert on cde.model_validation_runs to authenticated;

drop policy if exists models_operate_update on cde.models;
drop policy if exists models_governed_update on cde.models;
create policy models_governed_update on cde.models for update to authenticated
using(project.can_manage_project(project_id))
with check(project.can_manage_project(project_id) and current_setting('conceptspaces.model_phase',true) in ('validate','transition','supersede'));

create or replace function public.record_cde_model_validation(target_model_id uuid,input_payload jsonb)
returns uuid
language plpgsql security invoker
set search_path=public,cde,project,coordination,audit,auth,pg_temp
as $$
declare m cde.models%rowtype; v cde.model_validation_runs%rowtype; org_id uuid; validation_type_value text; result_hash_value text; issue_id uuid;
begin
  select * into m from cde.models where id=target_model_id for update;
  if not found or auth.uid() is null or not project.can_manage_project(m.project_id) then raise exception 'model_manage_authority_required'; end if;
  if m.status in ('issued','superseded','withdrawn') then raise exception 'immutable_model_revision'; end if;
  validation_type_value:=lower(coalesce(nullif(btrim(input_payload->>'validation_type'),''),'ifc'));
  if validation_type_value not in ('ifc','ids','geometry','semantic','round_trip') then raise exception 'unsupported_validation_type'; end if;
  result_hash_value:=lower(coalesce(input_payload->>'result_hash',''));
  if result_hash_value !~ '^[0-9a-f]{64}$' then raise exception 'validation_result_hash_required'; end if;
  perform set_config('conceptspaces.model_phase','validate',true);
  insert into cde.model_validation_runs(project_id,model_id,validation_type,adapter_key,adapter_version,passed,result_hash,findings,evidence_refs,created_by)
  values(m.project_id,m.id,validation_type_value,nullif(btrim(input_payload->>'adapter_key'),''),nullif(btrim(input_payload->>'adapter_version'),''),coalesce((input_payload->>'passed')::boolean,false),result_hash_value,coalesce(input_payload->'findings','[]'::jsonb),coalesce(input_payload->'evidence_refs','[]'::jsonb),auth.uid()) returning * into v;
  update cde.models set validation_summary=jsonb_build_object('validation_run_id',v.id,'type',v.validation_type,'passed',v.passed,'findings',v.findings,'validated_at',v.created_at),validation_hash=v.result_hash,updated_at=now() where id=m.id returning * into m;
  if not v.passed then
    issue_id:=public.create_coordination_issue(jsonb_build_object('project_id',m.project_id,'issue_type','coordination','title',upper(v.validation_type)||' validation failed · '||m.model_name,'description','Model validation failed. Review structured findings in validation run '||v.id::text,'priority',case when jsonb_array_length(v.findings)>0 then 'high' else 'medium' end,'criticality',coalesce(nullif(upper(input_payload->>'criticality'),''),'C2')));
    insert into coordination.issue_links(issue_id,resource_type,resource_id,relationship) values(issue_id,'model',m.id,'validation_failure') on conflict do nothing;
  end if;
  select organisation_id into org_id from project.projects where id=m.project_id;
  perform audit.append_event(org_id,m.project_id,'cde.model.validation_recorded','model_validation',v.id,null,to_jsonb(v),v.result_hash,gen_random_uuid());
  return v.id;
end;$$;
revoke all on function public.record_cde_model_validation(uuid,jsonb) from public,anon;
grant execute on function public.record_cde_model_validation(uuid,jsonb) to authenticated;

create or replace function public.transition_cde_model(target_model_id uuid,target_status text,target_reason text default null)
returns text
language plpgsql security invoker
set search_path=public,cde,project,audit,auth,pg_temp
as $$
declare m cde.models%rowtype; before_state jsonb; status_value text:=lower(btrim(target_status)); org_id uuid; latest_validation cde.model_validation_runs%rowtype;
begin
  select * into m from cde.models where id=target_model_id for update;
  if not found or auth.uid() is null or not project.can_manage_project(m.project_id) then raise exception 'model_manage_authority_required'; end if;
  if status_value not in ('for_review','for_approval','approved','issued','superseded','withdrawn') then raise exception 'unsupported_model_status'; end if;
  if m.status in ('superseded','withdrawn') then raise exception 'terminal_model_revision'; end if;
  if status_value='for_review' and m.status<>'draft' then raise exception 'invalid_model_transition'; end if;
  if status_value='for_approval' and m.status<>'for_review' then raise exception 'invalid_model_transition'; end if;
  if status_value='approved' and m.status<>'for_approval' then raise exception 'invalid_model_transition'; end if;
  if status_value='issued' and m.status<>'approved' then raise exception 'invalid_model_transition'; end if;
  if status_value in ('approved','issued') then
    select * into latest_validation from cde.model_validation_runs where model_id=m.id order by created_at desc limit 1;
    if not found or not latest_validation.passed then raise exception 'passing_model_validation_required'; end if;
    if m.validation_hash is distinct from latest_validation.result_hash then raise exception 'model_validation_stale'; end if;
  end if;
  if status_value in ('superseded','withdrawn') and nullif(btrim(target_reason),'') is null then raise exception 'model_transition_reason_required'; end if;
  before_state:=to_jsonb(m);
  perform set_config('conceptspaces.model_phase','transition',true);
  update cde.models set status=status_value,
    approved_by=case when status_value='approved' then auth.uid() else approved_by end,
    approved_at=case when status_value='approved' then now() else approved_at end,
    issued_by=case when status_value='issued' then auth.uid() else issued_by end,
    issued_at=case when status_value='issued' then now() else issued_at end,
    updated_at=now()
  where id=m.id returning * into m;
  select organisation_id into org_id from project.projects where id=m.project_id;
  perform audit.append_event(org_id,m.project_id,'cde.model.'||status_value,'model',m.id,before_state,to_jsonb(m),target_reason,gen_random_uuid());
  return m.status;
end;$$;
revoke all on function public.transition_cde_model(uuid,text,text) from public,anon;
grant execute on function public.transition_cde_model(uuid,text,text) to authenticated;

create or replace function public.register_cde_model_revision(target_model_id uuid,input_payload jsonb)
returns uuid
language plpgsql security invoker
set search_path=public,cde,project,audit,auth,pg_temp
as $$
declare source_model cde.models%rowtype; new_model cde.models%rowtype; org_id uuid; object_key_value text; checksum_value text; revision_value text;
begin
  select * into source_model from cde.models where id=target_model_id for update;
  if not found or auth.uid() is null or not project.can_manage_project(source_model.project_id) then raise exception 'model_manage_authority_required'; end if;
  if source_model.status in ('superseded','withdrawn') then raise exception 'terminal_source_model'; end if;
  object_key_value:=btrim(input_payload->>'object_key'); checksum_value:=lower(coalesce(input_payload->>'checksum','')); revision_value:=btrim(input_payload->>'revision');
  if nullif(revision_value,'') is null then raise exception 'model_revision_required'; end if;
  if nullif(object_key_value,'') is null or object_key_value not like source_model.project_id::text||'/models/%' then raise exception 'invalid_model_storage_path'; end if;
  if checksum_value !~ '^[0-9a-f]{64}$' then raise exception 'sha256_checksum_required'; end if;
  if checksum_value=source_model.checksum then raise exception 'new_revision_content_required'; end if;
  insert into cde.models(project_id,discipline,model_name,format,schema_version,object_key,checksum,coordinate_system,status,created_by,revision,supersedes_model_id)
  values(source_model.project_id,coalesce(nullif(upper(btrim(input_payload->>'discipline')),''),source_model.discipline),coalesce(nullif(btrim(input_payload->>'model_name'),''),source_model.model_name),coalesce(nullif(lower(btrim(input_payload->>'format')),''),source_model.format),coalesce(nullif(btrim(input_payload->>'schema_version'),''),source_model.schema_version),object_key_value,checksum_value,coalesce(nullif(btrim(input_payload->>'coordinate_system'),''),source_model.coordinate_system),'draft',auth.uid(),revision_value,source_model.id) returning * into new_model;
  perform set_config('conceptspaces.model_phase','supersede',true);
  update cde.models set status='superseded',updated_at=now() where id=source_model.id;
  select organisation_id into org_id from project.projects where id=source_model.project_id;
  perform audit.append_event(org_id,source_model.project_id,'cde.model.revision_created','model',new_model.id,to_jsonb(source_model),to_jsonb(new_model),null,gen_random_uuid());
  return new_model.id;
end;$$;
revoke all on function public.register_cde_model_revision(uuid,jsonb) from public,anon;
grant execute on function public.register_cde_model_revision(uuid,jsonb) to authenticated;

create or replace function public.list_model_workspace(target_project_id uuid)
returns jsonb
language plpgsql stable security invoker
set search_path=public,cde,coordination,project,pg_temp
as $$
begin
  if auth.uid() is null or not project.can_access_project(target_project_id) then raise exception 'project_access_required'; end if;
  return jsonb_build_object(
    'models',coalesce((select jsonb_agg(to_jsonb(m) order by m.updated_at desc) from cde.models m where m.project_id=target_project_id),'[]'::jsonb),
    'validation_runs',coalesce((select jsonb_agg(to_jsonb(v) order by v.created_at desc) from cde.model_validation_runs v where v.project_id=target_project_id),'[]'::jsonb),
    'issues',coalesce((select jsonb_agg(to_jsonb(i) order by i.updated_at desc) from coordination.issues i where i.project_id=target_project_id and exists(select 1 from coordination.issue_links l where l.issue_id=i.id and l.resource_type='model')),'[]'::jsonb)
  );
end;$$;
revoke all on function public.list_model_workspace(uuid) from public,anon;
grant execute on function public.list_model_workspace(uuid) to authenticated;

commit;