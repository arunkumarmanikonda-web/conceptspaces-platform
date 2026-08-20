begin;

grant usage on schema aec,regula to authenticated,service_role;
grant select on aec.site_geometries,aec.site_constraints,regula.packs,regula.rules,regula.project_applicability,regula.compliance_findings to authenticated;

alter table aec.site_geometries add column if not exists input_hash text;
alter table aec.site_geometries add column if not exists content_hash text;
alter table aec.site_geometries add column if not exists engine text;
alter table aec.site_geometries add column if not exists engine_version text;
alter table aec.site_geometries add column if not exists engine_valid boolean not null default false;
alter table aec.site_geometries add column if not exists validation_messages jsonb not null default '[]'::jsonb;
alter table aec.site_geometries add column if not exists supersedes_geometry_id uuid references aec.site_geometries(id);
alter table aec.site_geometries add column if not exists evaluated_at timestamptz;
create unique index if not exists site_geometries_content_hash_unique on aec.site_geometries(project_id,content_hash) where content_hash is not null;
create index if not exists site_geometries_current_idx on aec.site_geometries(project_id,engine_valid,created_at desc);

create table if not exists regula.evaluation_runs(
  id uuid primary key default gen_random_uuid(),
  project_id uuid not null references project.projects(id) on delete cascade,
  as_of date not null,
  engine text not null,
  engine_version text not null,
  input_hash text not null,
  result_hash text,
  status text not null check(status in ('running','completed','failed')),
  rules_evaluated integer not null default 0,
  deterministic_passes integer not null default 0,
  deterministic_failures integer not null default 0,
  interpretation_required integer not null default 0,
  not_verified integer not null default 0,
  initiated_by uuid references auth.users(id),
  completed_at timestamptz,
  created_at timestamptz not null default now(),
  unique(project_id,input_hash)
);
alter table regula.evaluation_runs enable row level security;
drop policy if exists cs_read on regula.evaluation_runs;
create policy cs_read on regula.evaluation_runs for select to authenticated using(project.can_access_project(project_id));
grant select on regula.evaluation_runs to authenticated;

alter table regula.compliance_findings add column if not exists evaluation_run_id uuid references regula.evaluation_runs(id) on delete set null;
create index if not exists regula_findings_run_idx on regula.compliance_findings(evaluation_run_id,checked_at desc);

create or replace function aec.guard_site_geometry_immutable()
returns trigger language plpgsql security definer set search_path=aec,pg_temp
as $$
begin
  if old.project_id is distinct from new.project_id
     or old.geometry is distinct from new.geometry
     or old.area is distinct from new.area
     or old.unit is distinct from new.unit
     or old.coordinate_system is distinct from new.coordinate_system
     or old.source_type is distinct from new.source_type
     or old.source_reference is distinct from new.source_reference
     or old.input_hash is distinct from new.input_hash
     or old.content_hash is distinct from new.content_hash
     or old.engine is distinct from new.engine
     or old.engine_version is distinct from new.engine_version
     or old.engine_valid is distinct from new.engine_valid
     or old.validation_messages is distinct from new.validation_messages
     or old.supersedes_geometry_id is distinct from new.supersedes_geometry_id
  then raise exception 'site_geometry_evidence_is_immutable_create_new_revision'; end if;
  return new;
end;$$;
drop trigger if exists concept_spaces_site_geometry_immutable on aec.site_geometries;
create trigger concept_spaces_site_geometry_immutable before update on aec.site_geometries for each row execute function aec.guard_site_geometry_immutable();

create or replace function public.authorize_aec_runtime(target_project_id uuid)
returns boolean language sql stable security invoker set search_path=project,public,auth,pg_temp
as $$ select auth.uid() is not null and project.can_manage_project(target_project_id); $$;
revoke all on function public.authorize_aec_runtime(uuid) from public,anon;
grant execute on function public.authorize_aec_runtime(uuid) to authenticated;

create or replace function public.persist_geometry_evaluation(
  target_project_id uuid,target_actor_id uuid,target_input jsonb,target_result jsonb,target_input_hash text,target_content_hash text,target_supersedes_geometry_id uuid default null
)
returns uuid language plpgsql security invoker set search_path=aec,project,core,public,auth,pg_temp
as $$
declare p project.projects%rowtype; gid uuid; source_type_value text; verification_value text:='unverified';
begin
  if current_user<>'service_role' then raise exception 'service_role_required'; end if;
  if target_actor_id is null or target_input_hash !~ '^[0-9a-f]{64}$' or target_content_hash !~ '^[0-9a-f]{64}$' then raise exception 'invalid_geometry_provenance'; end if;
  select * into p from project.projects where id=target_project_id; if not found then raise exception 'project_not_found'; end if;
  if not exists(select 1 from core.memberships m where m.organisation_id=p.organisation_id and m.user_id=target_actor_id and m.status='active')
     and not exists(select 1 from project.project_members pm where pm.project_id=p.id and pm.user_id=target_actor_id and pm.status='active') then raise exception 'actor_project_authority_required'; end if;
  if coalesce(target_result->>'engine','')<>'conceptspaces-precision-geometry' or coalesce(target_result->>'engine_version','')='' then raise exception 'untrusted_geometry_engine'; end if;
  source_type_value:=lower(coalesce(target_input->>'source_type','manual'));
  if source_type_value not in ('survey','cadastral','dwg','dxf','point_cloud','lidar','manual') then raise exception 'unsupported_geometry_source'; end if;
  if target_supersedes_geometry_id is not null and not exists(select 1 from aec.site_geometries g where g.id=target_supersedes_geometry_id and g.project_id=target_project_id) then raise exception 'superseded_geometry_not_in_project'; end if;
  insert into aec.site_geometries(project_id,coordinate_system,georeferenced,unit,source_type,source_reference,verification,geometry,area,created_by,input_hash,content_hash,engine,engine_version,engine_valid,validation_messages,supersedes_geometry_id,evaluated_at)
  values(target_project_id,nullif(target_result->>'coordinate_system',''),coalesce(target_result->>'input_mode','')='geographic','m',source_type_value,nullif(target_input->>'source_reference',''),verification_value,
    jsonb_build_object('input',target_input,'result',target_result),nullif(target_result->>'area','')::numeric,target_actor_id,target_input_hash,target_content_hash,target_result->>'engine',target_result->>'engine_version',coalesce((target_result->>'valid')::boolean,false),coalesce(target_result->'validation_messages','[]'::jsonb),target_supersedes_geometry_id,now())
  on conflict(project_id,content_hash) where content_hash is not null do update set evaluated_at=aec.site_geometries.evaluated_at
  returning id into gid;
  return gid;
end;$$;
revoke all on function public.persist_geometry_evaluation(uuid,uuid,jsonb,jsonb,text,text,uuid) from public,anon,authenticated;
grant execute on function public.persist_geometry_evaluation(uuid,uuid,jsonb,jsonb,text,text,uuid) to service_role;

grant update(verification,verified_by,verified_at,updated_at) on aec.site_geometries to authenticated;
drop policy if exists site_geometry_professional_verify on aec.site_geometries;
create policy site_geometry_professional_verify on aec.site_geometries for update to authenticated
using(
  current_setting('conceptspaces.geometry_verify',true)='on'
  and current_setting('conceptspaces.geometry_actor',true)=auth.uid()::text
  and project.can_access_project(project_id)
)
with check(
  current_setting('conceptspaces.geometry_verify',true)='on'
  and verified_by=auth.uid()
  and verification='professionally_verified'
  and engine_valid=true
);

create or replace function public.verify_site_geometry(target_geometry_id uuid,target_content_hash text)
returns void language plpgsql security invoker set search_path=aec,project,core,public,auth,pg_temp
as $$
declare g aec.site_geometries%rowtype; actor uuid:=auth.uid();
begin
  if actor is null then raise exception 'authentication_required'; end if;
  select * into g from aec.site_geometries where id=target_geometry_id for update; if not found then raise exception 'geometry_not_found'; end if;
  if g.content_hash is distinct from lower(target_content_hash) then raise exception 'geometry_hash_changed'; end if;
  if not g.engine_valid then raise exception 'invalid_geometry_cannot_be_verified'; end if;
  if not (core.has_verified_professional_eligibility(actor,'lead_architect') or core.has_verified_professional_eligibility(actor,'architect')) then raise exception 'verified_architectural_professional_required'; end if;
  perform set_config('conceptspaces.geometry_verify','on',true);perform set_config('conceptspaces.geometry_actor',actor::text,true);
  update aec.site_geometries set verification='professionally_verified',verified_by=actor,verified_at=now(),updated_at=now() where id=g.id;
end;$$;
revoke all on function public.verify_site_geometry(uuid,text) from public,anon;
grant execute on function public.verify_site_geometry(uuid,text) to authenticated;

create or replace function public.list_project_site_geometry(target_project_id uuid)
returns table(id uuid,source_type text,source_reference text,verification text,engine_valid boolean,content_hash text,area numeric,coordinate_system text,geometry jsonb,validation_messages jsonb,verified_by uuid,verified_at timestamptz,created_at timestamptz)
language sql stable security invoker set search_path=aec,project,public,auth,pg_temp
as $$ select g.id,g.source_type,g.source_reference,g.verification,g.engine_valid,g.content_hash,g.area,g.coordinate_system,g.geometry,g.validation_messages,g.verified_by,g.verified_at,g.created_at from aec.site_geometries g where g.project_id=target_project_id and project.can_access_project(target_project_id) order by g.created_at desc; $$;
revoke all on function public.list_project_site_geometry(uuid) from public,anon;
grant execute on function public.list_project_site_geometry(uuid) to authenticated;

-- Applicability resolution is deterministic by jurisdiction/effective date but remains proposed until a verified regulatory professional confirms it.
grant insert,update on regula.project_applicability to authenticated;
drop policy if exists regula_applicability_runtime_insert on regula.project_applicability;
create policy regula_applicability_runtime_insert on regula.project_applicability for insert to authenticated
with check(current_setting('conceptspaces.regula_phase',true)='resolve' and current_setting('conceptspaces.regula_actor',true)=auth.uid()::text and project.can_manage_project(project_id) and status='proposed');
drop policy if exists regula_applicability_runtime_update on regula.project_applicability;
create policy regula_applicability_runtime_update on regula.project_applicability for update to authenticated
using(current_setting('conceptspaces.regula_phase',true)='confirm' and current_setting('conceptspaces.regula_actor',true)=auth.uid()::text and project.can_access_project(project_id))
with check(current_setting('conceptspaces.regula_phase',true)='confirm' and confirmed_by=auth.uid() and status in ('confirmed','rejected'));

create or replace function public.resolve_regula_applicability(target_project_id uuid,target_as_of date default current_date)
returns integer language plpgsql security invoker set search_path=regula,project,public,auth,pg_temp
as $$
declare p project.projects%rowtype; actor uuid:=auth.uid(); affected integer:=0;
begin
  if actor is null then raise exception 'authentication_required'; end if; if not project.can_manage_project(target_project_id) then raise exception 'project_manage_authority_required'; end if;
  select * into p from project.projects where id=target_project_id; if not found then raise exception 'project_not_found'; end if;
  perform set_config('conceptspaces.regula_phase','resolve',true);perform set_config('conceptspaces.regula_actor',actor::text,true);
  insert into regula.project_applicability(project_id,pack_id,applicability_reason,precedence,status)
  select p.id,rp.id,'Jurisdiction/effective-date candidate resolved deterministically',
    case when rp.jurisdiction_city is not null then 10 when rp.jurisdiction_state is not null then 20 else 30 end,'proposed'
  from regula.packs rp
  where rp.publication_status='published' and upper(rp.jurisdiction_country)=upper(p.jurisdiction_country)
    and (rp.jurisdiction_state is null or lower(rp.jurisdiction_state)=lower(coalesce(p.jurisdiction_state,'')))
    and (rp.jurisdiction_city is null or lower(rp.jurisdiction_city)=lower(coalesce(p.jurisdiction_city,'')))
    and rp.effective_from<=target_as_of and (rp.effective_until is null or rp.effective_until>=target_as_of)
  on conflict(project_id,pack_id) do nothing;
  get diagnostics affected=row_count;return affected;
end;$$;
revoke all on function public.resolve_regula_applicability(uuid,date) from public,anon;
grant execute on function public.resolve_regula_applicability(uuid,date) to authenticated;

create or replace function public.confirm_regula_applicability(target_applicability_id uuid,target_decision text)
returns void language plpgsql security invoker set search_path=regula,project,core,public,auth,pg_temp
as $$
declare a regula.project_applicability%rowtype; actor uuid:=auth.uid(); decision text:=lower(target_decision);
begin
  if actor is null then raise exception 'authentication_required'; end if;if decision not in ('confirmed','rejected') then raise exception 'unsupported_applicability_decision'; end if;
  select * into a from regula.project_applicability where id=target_applicability_id for update;if not found then raise exception 'applicability_not_found';end if;
  if not core.has_verified_professional_eligibility(actor,'regulatory_reviewer') then raise exception 'verified_regulatory_reviewer_required';end if;
  perform set_config('conceptspaces.regula_phase','confirm',true);perform set_config('conceptspaces.regula_actor',actor::text,true);
  update regula.project_applicability set status=decision,confirmed_by=actor,confirmed_at=now() where id=a.id;
end;$$;
revoke all on function public.confirm_regula_applicability(uuid,text) from public,anon;
grant execute on function public.confirm_regula_applicability(uuid,text) to authenticated;

create or replace function public.prepare_regula_evaluation(target_project_id uuid,target_as_of date default current_date)
returns jsonb language plpgsql stable security invoker set search_path=regula,project,public,auth,pg_temp
as $$
declare p project.projects%rowtype; payload jsonb;
begin
  if auth.uid() is null or not project.can_access_project(target_project_id) then raise exception 'project_access_required'; end if;
  select * into p from project.projects where id=target_project_id;if not found then raise exception 'project_not_found';end if;
  payload:=jsonb_build_object(
    'project',jsonb_build_object('id',p.id,'jurisdiction_country',p.jurisdiction_country,'jurisdiction_state',p.jurisdiction_state,'jurisdiction_city',p.jurisdiction_city,'criticality',p.criticality),
    'as_of',target_as_of,
    'facts',coalesce((select jsonb_agg(jsonb_build_object('record_key',t.record_key,'value',t.value,'unit',t.unit,'status',t.status,'confidence',t.confidence,'source_reference',t.source_reference) order by t.record_key,t.created_at desc) from project.truth_records t where t.project_id=p.id and t.valid_until is null),'[]'::jsonb),
    'rules',coalesce((select jsonb_agg(jsonb_build_object('rule_id',r.id,'rule_code',r.rule_code::text,'subject',r.subject,'disposition',r.disposition,'requires_professional_interpretation',r.requires_professional_interpretation,'source_reference',r.source_reference,'metadata',r.metadata,'pack_code',pk.code::text,'pack_title',pk.title,'pack_effective_from',pk.effective_from) order by a.precedence,r.rule_code)
      from regula.project_applicability a join regula.packs pk on pk.id=a.pack_id join regula.rules r on r.pack_id=pk.id
      where a.project_id=p.id and a.status='confirmed' and pk.publication_status='published' and r.effective_from<=target_as_of and (pk.effective_until is null or pk.effective_until>=target_as_of)),'[]'::jsonb)
  );
  return payload;
end;$$;
revoke all on function public.prepare_regula_evaluation(uuid,date) from public,anon;
grant execute on function public.prepare_regula_evaluation(uuid,date) to authenticated;

create or replace function public.persist_regula_evaluation(target_project_id uuid,target_actor_id uuid,target_as_of date,target_engine text,target_engine_version text,target_input_hash text,target_result_hash text,target_results jsonb)
returns uuid language plpgsql security invoker set search_path=regula,project,core,public,auth,pg_temp
as $$
declare p project.projects%rowtype; run_id uuid; item jsonb; rule_row regula.rules%rowtype; status_value text; disposition_value text; pass_count int:=0;fail_count int:=0;interp_count int:=0;nv_count int:=0;count_rules int:=0;
begin
  if current_user<>'service_role' then raise exception 'service_role_required';end if;
  if target_input_hash !~ '^[0-9a-f]{64}$' or target_result_hash !~ '^[0-9a-f]{64}$' then raise exception 'invalid_regula_hash';end if;
  if target_engine<>'conceptspaces-regula-deterministic' then raise exception 'untrusted_regula_engine';end if;
  select * into p from project.projects where id=target_project_id;if not found then raise exception 'project_not_found';end if;
  if not exists(select 1 from core.memberships m where m.organisation_id=p.organisation_id and m.user_id=target_actor_id and m.status='active') and not exists(select 1 from project.project_members pm where pm.project_id=p.id and pm.user_id=target_actor_id and pm.status='active') then raise exception 'actor_project_authority_required';end if;
  insert into regula.evaluation_runs(project_id,as_of,engine,engine_version,input_hash,result_hash,status,initiated_by,completed_at)
  values(p.id,target_as_of,target_engine,target_engine_version,target_input_hash,target_result_hash,'completed',target_actor_id,now())
  on conflict(project_id,input_hash) do update set result_hash=excluded.result_hash,completed_at=excluded.completed_at
  returning id into run_id;
  delete from regula.compliance_findings where evaluation_run_id=run_id;
  if jsonb_typeof(target_results)<>'array' then raise exception 'regula_results_array_required';end if;
  for item in select value from jsonb_array_elements(target_results) loop
    select r.* into rule_row from regula.rules r join regula.project_applicability a on a.pack_id=r.pack_id where r.id=(item->>'rule_id')::uuid and a.project_id=p.id and a.status='confirmed';if not found then raise exception 'result_rule_not_confirmed_for_project';end if;
    status_value:=coalesce(item->>'status','not_verified');if status_value not in ('pass','fail','not_verified','requires_interpretation') then raise exception 'invalid_regula_result_status';end if;
    disposition_value:=rule_row.disposition;
    insert into regula.compliance_findings(project_id,rule_id,disposition,status,observed_value,required_value,evidence_refs,explanation,checked_by_type,checked_by,checked_at,evaluation_run_id)
    values(p.id,rule_row.id,disposition_value,status_value,item->'observed_value',item->'required_value',coalesce(item->'evidence_refs','[]'::jsonb),left(coalesce(item->>'explanation',''),2000),'system',target_actor_id,now(),run_id);
    count_rules:=count_rules+1;if status_value='pass' then pass_count:=pass_count+1;elsif status_value='fail' then fail_count:=fail_count+1;elsif status_value='requires_interpretation' then interp_count:=interp_count+1;else nv_count:=nv_count+1;end if;
  end loop;
  update regula.evaluation_runs set rules_evaluated=count_rules,deterministic_passes=pass_count,deterministic_failures=fail_count,interpretation_required=interp_count,not_verified=nv_count where id=run_id;
  return run_id;
end;$$;
revoke all on function public.persist_regula_evaluation(uuid,uuid,date,text,text,text,text,jsonb) from public,anon,authenticated;
grant execute on function public.persist_regula_evaluation(uuid,uuid,date,text,text,text,text,jsonb) to service_role;

create or replace function public.list_project_regula_state(target_project_id uuid)
returns jsonb language plpgsql stable security invoker set search_path=regula,project,public,auth,pg_temp
as $$
begin
  if auth.uid() is null or not project.can_access_project(target_project_id) then raise exception 'project_access_required';end if;
  return jsonb_build_object(
    'applicability',coalesce((select jsonb_agg(jsonb_build_object('id',a.id,'pack_id',a.pack_id,'pack_code',p.code::text,'title',p.title,'authority',p.authority,'effective_from',p.effective_from,'effective_until',p.effective_until,'status',a.status,'precedence',a.precedence,'confirmed_by',a.confirmed_by,'confirmed_at',a.confirmed_at) order by a.precedence,p.code) from regula.project_applicability a join regula.packs p on p.id=a.pack_id where a.project_id=target_project_id),'[]'::jsonb),
    'latest_run',(select to_jsonb(r) from regula.evaluation_runs r where r.project_id=target_project_id order by r.created_at desc limit 1),
    'latest_findings',coalesce((select jsonb_agg(jsonb_build_object('id',f.id,'rule_code',r.rule_code::text,'subject',r.subject,'disposition',f.disposition,'status',f.status,'observed_value',f.observed_value,'required_value',f.required_value,'explanation',f.explanation,'source_reference',r.source_reference,'checked_at',f.checked_at) order by r.rule_code) from regula.compliance_findings f join regula.rules r on r.id=f.rule_id where f.evaluation_run_id=(select er.id from regula.evaluation_runs er where er.project_id=target_project_id order by er.created_at desc limit 1)),'[]'::jsonb)
  );
end;$$;
revoke all on function public.list_project_regula_state(uuid) from public,anon;
grant execute on function public.list_project_regula_state(uuid) to authenticated;

commit;
