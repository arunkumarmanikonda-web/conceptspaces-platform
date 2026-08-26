begin;

alter table analytics.kpi_definitions add column if not exists organisation_id uuid references core.organisations(id) on delete cascade;
alter table analytics.kpi_definitions add column if not exists version integer not null default 1;
alter table analytics.kpi_definitions add column if not exists active boolean not null default true;
alter table analytics.kpi_definitions add column if not exists supersedes_definition_id uuid references analytics.kpi_definitions(id) on delete set null;
alter table analytics.kpi_definitions add column if not exists configuration_hash text;
alter table analytics.kpi_definitions add column if not exists created_by uuid references auth.users(id);
alter table analytics.kpi_definitions add column if not exists updated_by uuid references auth.users(id);

-- The table is empty at this migration boundary; all future definitions are tenant-owned.
alter table analytics.kpi_definitions alter column organisation_id set not null;
alter table analytics.kpi_definitions drop constraint if exists kpi_definitions_code_key;
alter table analytics.kpi_definitions drop constraint if exists kpi_definitions_org_code_version_key;
alter table analytics.kpi_definitions add constraint kpi_definitions_org_code_version_key unique(organisation_id,code,version);

alter table analytics.kpi_observations add column if not exists calculation_snapshot jsonb not null default '{}'::jsonb;
alter table analytics.kpi_observations add column if not exists observation_hash text;
alter table analytics.kpi_observations add column if not exists created_by uuid references auth.users(id);

alter table analytics.kpi_definitions enable row level security;
alter table analytics.kpi_observations enable row level security;
grant select,insert,update on analytics.kpi_definitions to authenticated;
grant select,insert on analytics.kpi_observations to authenticated;

drop policy if exists cs_read on analytics.kpi_definitions;
drop policy if exists kpi_definitions_read on analytics.kpi_definitions;
create policy kpi_definitions_read on analytics.kpi_definitions
for select to authenticated using(core.is_internal_org_member(organisation_id));
drop policy if exists kpi_definitions_insert on analytics.kpi_definitions;
create policy kpi_definitions_insert on analytics.kpi_definitions
for insert to authenticated with check(
 core.has_org_role(organisation_id,array['super_admin','org_admin'])
 and current_setting('conceptspaces.analytics_phase',true)='definition'
);
drop policy if exists kpi_definitions_update on analytics.kpi_definitions;
create policy kpi_definitions_update on analytics.kpi_definitions
for update to authenticated
using(core.has_org_role(organisation_id,array['super_admin','org_admin']))
with check(
 core.has_org_role(organisation_id,array['super_admin','org_admin'])
 and current_setting('conceptspaces.analytics_phase',true)='definition'
);

drop policy if exists kpi_observations_insert on analytics.kpi_observations;
create policy kpi_observations_insert on analytics.kpi_observations
for insert to authenticated with check(
 core.has_org_role(organisation_id,array['super_admin','org_admin','project_manager','finance','lead_architect'])
 and current_setting('conceptspaces.analytics_phase',true)='observation'
 and ((project_id is null) or project.can_access_project(project_id))
);

create or replace function analytics.prevent_kpi_observation_mutation()
returns trigger
language plpgsql
security definer
set search_path='analytics','pg_temp'
as $$
begin
 raise exception 'kpi_observation_immutable';
end;
$$;
revoke all on function analytics.prevent_kpi_observation_mutation() from public,anon,authenticated;
drop trigger if exists trg_kpi_observation_immutable on analytics.kpi_observations;
create trigger trg_kpi_observation_immutable
before update or delete on analytics.kpi_observations
for each row execute function analytics.prevent_kpi_observation_mutation();

create or replace function public.create_kpi_definition(target_organisation_id uuid,input_payload jsonb)
returns uuid
language plpgsql
security invoker
set search_path='public','analytics','core','audit','extensions','auth','pg_temp'
as $$
declare
 definition analytics.kpi_definitions%rowtype;
 previous analytics.kpi_definitions%rowtype;
 code_value text:=upper(btrim(input_payload->>'code'));
 direction_value text:=lower(btrim(input_payload->>'direction'));
 version_value integer:=1;
 hash_value text;
begin
 if auth.uid() is null or not core.has_org_role(target_organisation_id,array['super_admin','org_admin']) then raise exception 'analytics_definition_authority_required'; end if;
 if nullif(code_value,'') is null or nullif(btrim(input_payload->>'name'),'') is null or nullif(btrim(input_payload->>'domain'),'') is null or nullif(btrim(input_payload->>'unit'),'') is null or nullif(btrim(input_payload->>'calculation_ref'),'') is null then raise exception 'kpi_definition_fields_required'; end if;
 if direction_value not in ('higher_is_better','lower_is_better','target_band') then raise exception 'kpi_direction_invalid'; end if;
 select * into previous from analytics.kpi_definitions where organisation_id=target_organisation_id and code=code_value and active order by version desc limit 1 for update;
 if found then version_value:=previous.version+1; end if;
 hash_value:=encode(extensions.digest(jsonb_build_object(
  'organisation_id',target_organisation_id,'code',code_value,'version',version_value,
  'name',btrim(input_payload->>'name'),'domain',lower(btrim(input_payload->>'domain')),
  'unit',btrim(input_payload->>'unit'),'direction',direction_value,
  'target',nullif(input_payload->>'target','')::numeric,
  'warning_threshold',nullif(input_payload->>'warning_threshold','')::numeric,
  'critical_threshold',nullif(input_payload->>'critical_threshold','')::numeric,
  'calculation_ref',btrim(input_payload->>'calculation_ref'),
  'refresh_cadence',coalesce(nullif(lower(btrim(input_payload->>'refresh_cadence')),''),'manual')
 )::text,'sha256'),'hex');
 perform set_config('conceptspaces.analytics_phase','definition',true);
 if previous.id is not null then update analytics.kpi_definitions set active=false,updated_by=auth.uid(),updated_at=now() where id=previous.id; end if;
 insert into analytics.kpi_definitions(organisation_id,code,name,domain,unit,direction,target,warning_threshold,critical_threshold,calculation_ref,refresh_cadence,version,active,supersedes_definition_id,configuration_hash,created_by,updated_by)
 values(target_organisation_id,code_value,btrim(input_payload->>'name'),lower(btrim(input_payload->>'domain')),btrim(input_payload->>'unit'),direction_value,nullif(input_payload->>'target','')::numeric,nullif(input_payload->>'warning_threshold','')::numeric,nullif(input_payload->>'critical_threshold','')::numeric,btrim(input_payload->>'calculation_ref'),coalesce(nullif(lower(btrim(input_payload->>'refresh_cadence')),''),'manual'),version_value,true,previous.id,hash_value,auth.uid(),auth.uid()) returning * into definition;
 perform audit.append_event(target_organisation_id,null,'analytics.kpi_definition.created','kpi_definition',definition.id,case when previous.id is null then null else to_jsonb(previous) end,to_jsonb(definition),hash_value,gen_random_uuid());
 return definition.id;
end;
$$;
revoke all on function public.create_kpi_definition(uuid,jsonb) from public,anon;
grant execute on function public.create_kpi_definition(uuid,jsonb) to authenticated;

create or replace function public.record_kpi_observation(target_kpi_id uuid,target_project_id uuid,input_payload jsonb)
returns uuid
language plpgsql
security invoker
set search_path='public','analytics','project','core','audit','extensions','auth','pg_temp'
as $$
declare
 definition analytics.kpi_definitions%rowtype;
 observation analytics.kpi_observations%rowtype;
 observed_value numeric:=nullif(input_payload->>'value','')::numeric;
 observed_time timestamptz:=coalesce(nullif(input_payload->>'observed_at','')::timestamptz,now());
 confidence_value text:=upper(btrim(input_payload->>'confidence'));
 source_value text:=btrim(input_payload->>'source_ref');
 hash_value text;
begin
 select * into definition from analytics.kpi_definitions where id=target_kpi_id and active;
 if not found or auth.uid() is null or not core.has_org_role(definition.organisation_id,array['super_admin','org_admin','project_manager','finance','lead_architect']) then raise exception 'kpi_observation_authority_required'; end if;
 if observed_value is null or nullif(source_value,'') is null then raise exception 'kpi_value_source_required'; end if;
 if confidence_value not in ('A','B','C','D') then raise exception 'kpi_confidence_invalid'; end if;
 if target_project_id is not null and not exists(select 1 from project.projects p where p.id=target_project_id and p.organisation_id=definition.organisation_id and project.can_access_project(p.id)) then raise exception 'kpi_project_invalid'; end if;
 hash_value:=encode(extensions.digest(jsonb_build_object(
  'kpi_id',definition.id,'configuration_hash',definition.configuration_hash,'project_id',target_project_id,
  'observed_at',observed_time,'value',observed_value,'source_ref',source_value,'confidence',confidence_value,
  'calculation_ref',definition.calculation_ref
 )::text,'sha256'),'hex');
 perform set_config('conceptspaces.analytics_phase','observation',true);
 insert into analytics.kpi_observations(kpi_id,organisation_id,project_id,observed_at,value,source_ref,confidence,calculation_snapshot,observation_hash,created_by)
 values(definition.id,definition.organisation_id,target_project_id,observed_time,observed_value,source_value,confidence_value,jsonb_build_object('calculation_ref',definition.calculation_ref,'definition_version',definition.version,'configuration_hash',definition.configuration_hash),hash_value,auth.uid()) returning * into observation;
 perform audit.append_event(definition.organisation_id,target_project_id,'analytics.kpi_observed','kpi_observation',observation.id,null,to_jsonb(observation),source_value,gen_random_uuid());
 return observation.id;
end;
$$;
revoke all on function public.record_kpi_observation(uuid,uuid,jsonb) from public,anon;
grant execute on function public.record_kpi_observation(uuid,uuid,jsonb) to authenticated;

create or replace function public.list_analytics_workspace(target_organisation_id uuid)
returns jsonb
language plpgsql
stable
security invoker
set search_path='public','analytics','project','core','auth','pg_temp'
as $$
begin
 if auth.uid() is null or not core.is_internal_org_member(target_organisation_id) then raise exception 'organisation_access_required'; end if;
 return jsonb_build_object(
  'definitions',coalesce((select jsonb_agg(to_jsonb(d) order by d.domain,d.code,d.version desc) from analytics.kpi_definitions d where d.organisation_id=target_organisation_id),'[]'::jsonb),
  'observations',coalesce((select jsonb_agg(to_jsonb(o) order by o.observed_at desc) from analytics.kpi_observations o where o.organisation_id=target_organisation_id),'[]'::jsonb),
  'latest',coalesce((select jsonb_agg(to_jsonb(x) order by x.code,x.project_id nulls first) from (
    select distinct on(o.kpi_id,o.project_id)
      o.id,o.kpi_id,o.project_id,o.observed_at,o.value,o.source_ref,o.confidence,o.observation_hash,
      d.code,d.name,d.domain,d.unit,d.direction,d.target,d.warning_threshold,d.critical_threshold,d.calculation_ref,d.version as definition_version,d.configuration_hash
    from analytics.kpi_observations o join analytics.kpi_definitions d on d.id=o.kpi_id
    where o.organisation_id=target_organisation_id
    order by o.kpi_id,o.project_id,o.observed_at desc,o.created_at desc
  ) x),'[]'::jsonb),
  'projects',coalesce((select jsonb_agg(jsonb_build_object('id',p.id,'code',p.code,'name',p.name) order by p.code) from project.projects p where p.organisation_id=target_organisation_id and project.can_access_project(p.id)),'[]'::jsonb)
 );
end;
$$;
revoke all on function public.list_analytics_workspace(uuid) from public,anon;
grant execute on function public.list_analytics_workspace(uuid) to authenticated;

commit;