begin;

alter table site.activities add column if not exists forecast_finish date;
alter table site.activities add column if not exists delay_reason text;
alter table site.activities add column if not exists recovery_plan text;
alter table site.activities add column if not exists lookahead_bucket text;

create table if not exists site.activity_dependencies(
  id uuid primary key default gen_random_uuid(),
  project_id uuid not null references project.projects(id) on delete cascade,
  predecessor_activity_id uuid not null references site.activities(id) on delete cascade,
  successor_activity_id uuid not null references site.activities(id) on delete cascade,
  relationship text not null default 'FS' check(relationship in ('FS','SS','FF','SF')),
  lag_days integer not null default 0,
  created_by uuid references auth.users(id),
  created_at timestamptz not null default now(),
  unique(project_id,predecessor_activity_id,successor_activity_id),
  check(predecessor_activity_id<>successor_activity_id)
);
create index if not exists activity_dependencies_project_idx on site.activity_dependencies(project_id,predecessor_activity_id,successor_activity_id);

create table if not exists site.programmes(
  id uuid primary key default gen_random_uuid(),
  project_id uuid not null references project.projects(id) on delete cascade,
  version integer not null,
  title text not null,
  status text not null default 'baselined' check(status in ('baselined','superseded')),
  baseline_snapshot jsonb not null,
  baseline_hash text not null,
  baselined_by uuid references auth.users(id),
  baselined_at timestamptz not null default now(),
  created_at timestamptz not null default now(),
  unique(project_id,version)
);
create index if not exists programmes_project_status_idx on site.programmes(project_id,status,version desc);

alter table site.activity_dependencies enable row level security;
alter table site.programmes enable row level security;
drop policy if exists activity_dependencies_read on site.activity_dependencies;
create policy activity_dependencies_read on site.activity_dependencies for select to authenticated using(project.can_access_project(project_id));
drop policy if exists activity_dependencies_write on site.activity_dependencies;
create policy activity_dependencies_write on site.activity_dependencies for all to authenticated using(project.can_manage_project(project_id)) with check(project.can_manage_project(project_id) and current_setting('conceptspaces.site_phase',true)='programme');
drop policy if exists programmes_read on site.programmes;
create policy programmes_read on site.programmes for select to authenticated using(project.can_access_project(project_id));
drop policy if exists programmes_insert on site.programmes;
create policy programmes_insert on site.programmes for insert to authenticated with check(project.can_manage_project(project_id) and current_setting('conceptspaces.site_phase',true)='programme');
drop policy if exists programmes_update on site.programmes;
create policy programmes_update on site.programmes for update to authenticated using(project.can_manage_project(project_id)) with check(project.can_manage_project(project_id) and current_setting('conceptspaces.site_phase',true)='programme');
grant select,insert,update,delete on site.activity_dependencies to authenticated;
grant select,insert,update on site.programmes to authenticated;

create or replace function public.create_site_activity(target_project_id uuid,input_payload jsonb)
returns uuid
language plpgsql security invoker
set search_path=public,site,procurement,project,audit,auth,pg_temp
as $$
declare a site.activities%rowtype; vendor_id_value uuid:=nullif(input_payload->>'contractor_vendor_id','')::uuid; project_org uuid; planned_start_value date:=nullif(input_payload->>'planned_start','')::date; planned_finish_value date:=nullif(input_payload->>'planned_finish','')::date; org_id uuid;
begin
  if auth.uid() is null or not project.can_manage_project(target_project_id) then raise exception 'project_manage_authority_required'; end if;
  if nullif(btrim(input_payload->>'wbs_code'),'') is null or nullif(btrim(input_payload->>'title'),'') is null then raise exception 'activity_identity_required'; end if;
  if planned_start_value is not null and planned_finish_value is not null and planned_finish_value<planned_start_value then raise exception 'activity_planned_dates_invalid'; end if;
  if vendor_id_value is not null then select organisation_id into project_org from project.projects where id=target_project_id; if not exists(select 1 from procurement.vendors v where v.id=vendor_id_value and v.organisation_id=project_org and v.status='active') then raise exception 'activity_contractor_invalid'; end if; end if;
  perform set_config('conceptspaces.site_phase','activity',true);
  insert into site.activities(project_id,wbs_code,title,state,planned_start,planned_finish,progress_percent,contractor_vendor_id,evidence_refs,forecast_finish,lookahead_bucket)
  values(target_project_id,btrim(input_payload->>'wbs_code'),btrim(input_payload->>'title'),'not_started',planned_start_value,planned_finish_value,0,vendor_id_value,'[]'::jsonb,planned_finish_value,nullif(btrim(input_payload->>'lookahead_bucket'),'')) returning * into a;
  select organisation_id into org_id from project.projects where id=target_project_id; perform audit.append_event(org_id,target_project_id,'site.activity.created','activity',a.id,null,to_jsonb(a),null,gen_random_uuid()); return a.id;
end;$$;
revoke all on function public.create_site_activity(uuid,jsonb) from public,anon; grant execute on function public.create_site_activity(uuid,jsonb) to authenticated;

create or replace function public.update_site_activity(target_activity_id uuid,input_payload jsonb)
returns text
language plpgsql security invoker
set search_path=public,site,project,audit,auth,pg_temp
as $$
declare a site.activities%rowtype; before_state jsonb; state_value text; progress_value numeric; actual_start_value date; actual_finish_value date; forecast_finish_value date; evidence jsonb; org_id uuid;
begin
  select * into a from site.activities where id=target_activity_id for update;
  if not found or auth.uid() is null or not project.can_manage_project(a.project_id) then raise exception 'activity_manage_authority_required'; end if;
  state_value:=lower(coalesce(nullif(btrim(input_payload->>'state'),''),a.state));
  progress_value:=coalesce(nullif(input_payload->>'progress_percent','')::numeric,a.progress_percent);
  actual_start_value:=coalesce(nullif(input_payload->>'actual_start','')::date,a.actual_start);
  actual_finish_value:=coalesce(nullif(input_payload->>'actual_finish','')::date,a.actual_finish);
  forecast_finish_value:=coalesce(nullif(input_payload->>'forecast_finish','')::date,a.forecast_finish,a.planned_finish);
  evidence:=coalesce(input_payload->'evidence_refs',a.evidence_refs);
  if state_value not in ('not_started','in_progress','blocked','complete') or progress_value<0 or progress_value>100 then raise exception 'activity_state_or_progress_invalid'; end if;
  if (progress_value>0 or state_value in ('in_progress','blocked','complete')) and (jsonb_typeof(evidence)<>'array' or jsonb_array_length(evidence)=0) then raise exception 'activity_progress_evidence_required'; end if;
  if state_value='blocked' and nullif(btrim(input_payload->>'delay_reason'),'') is null and nullif(a.delay_reason,'') is null then raise exception 'activity_delay_reason_required'; end if;
  if state_value='complete' then progress_value:=100; actual_finish_value:=coalesce(actual_finish_value,current_date); actual_start_value:=coalesce(actual_start_value,a.planned_start,current_date); end if;
  if actual_start_value is not null and actual_finish_value is not null and actual_finish_value<actual_start_value then raise exception 'activity_actual_dates_invalid'; end if;
  before_state:=to_jsonb(a); perform set_config('conceptspaces.site_phase','activity',true);
  update site.activities set state=state_value,progress_percent=progress_value,actual_start=actual_start_value,actual_finish=actual_finish_value,forecast_finish=forecast_finish_value,delay_reason=coalesce(nullif(btrim(input_payload->>'delay_reason'),''),delay_reason),recovery_plan=coalesce(nullif(btrim(input_payload->>'recovery_plan'),''),recovery_plan),lookahead_bucket=coalesce(nullif(btrim(input_payload->>'lookahead_bucket'),''),lookahead_bucket),evidence_refs=evidence,updated_at=now() where id=a.id returning * into a;
  select organisation_id into org_id from project.projects where id=a.project_id; perform audit.append_event(org_id,a.project_id,'site.activity.updated','activity',a.id,before_state,to_jsonb(a),input_payload->>'reason',gen_random_uuid()); return a.state;
end;$$;
revoke all on function public.update_site_activity(uuid,jsonb) from public,anon; grant execute on function public.update_site_activity(uuid,jsonb) to authenticated;

create or replace function public.set_site_activity_dependency(target_project_id uuid,target_predecessor_id uuid,target_successor_id uuid,target_relationship text default 'FS',target_lag_days integer default 0)
returns uuid
language plpgsql security invoker
set search_path=public,site,project,audit,auth,pg_temp
as $$
declare dep site.activity_dependencies%rowtype; relationship_value text:=upper(btrim(target_relationship)); org_id uuid; cycle_exists boolean;
begin
  if auth.uid() is null or not project.can_manage_project(target_project_id) then raise exception 'project_manage_authority_required'; end if;
  if target_predecessor_id=target_successor_id or relationship_value not in ('FS','SS','FF','SF') then raise exception 'activity_dependency_invalid'; end if;
  if not exists(select 1 from site.activities a where a.id=target_predecessor_id and a.project_id=target_project_id) or not exists(select 1 from site.activities a where a.id=target_successor_id and a.project_id=target_project_id) then raise exception 'dependency_project_activity_required'; end if;
  with recursive reach(id) as (
    select target_successor_id
    union
    select d.successor_activity_id from site.activity_dependencies d join reach r on d.predecessor_activity_id=r.id where d.project_id=target_project_id
  ) select exists(select 1 from reach where id=target_predecessor_id) into cycle_exists;
  if cycle_exists then raise exception 'programme_dependency_cycle'; end if;
  perform set_config('conceptspaces.site_phase','programme',true);
  insert into site.activity_dependencies(project_id,predecessor_activity_id,successor_activity_id,relationship,lag_days,created_by)
  values(target_project_id,target_predecessor_id,target_successor_id,relationship_value,coalesce(target_lag_days,0),auth.uid())
  on conflict(project_id,predecessor_activity_id,successor_activity_id) do update set relationship=excluded.relationship,lag_days=excluded.lag_days returning * into dep;
  select organisation_id into org_id from project.projects where id=target_project_id; perform audit.append_event(org_id,target_project_id,'site.programme.dependency_set','activity_dependency',dep.id,null,to_jsonb(dep),null,gen_random_uuid()); return dep.id;
end;$$;
revoke all on function public.set_site_activity_dependency(uuid,uuid,uuid,text,integer) from public,anon; grant execute on function public.set_site_activity_dependency(uuid,uuid,uuid,text,integer) to authenticated;

create or replace function public.baseline_site_programme(target_project_id uuid,target_title text)
returns uuid
language plpgsql security invoker
set search_path=public,site,project,audit,extensions,auth,pg_temp
as $$
declare snapshot jsonb; hash_value text; version_value integer; prog site.programmes%rowtype; org_id uuid;
begin
  if auth.uid() is null or not project.can_manage_project(target_project_id) then raise exception 'project_manage_authority_required'; end if;
  if nullif(btrim(target_title),'') is null then raise exception 'programme_title_required'; end if;
  if not exists(select 1 from site.activities where project_id=target_project_id) then raise exception 'programme_activity_required'; end if;
  snapshot:=jsonb_build_object(
    'activities',coalesce((select jsonb_agg(jsonb_build_object('id',a.id,'wbs_code',a.wbs_code::text,'title',a.title,'planned_start',a.planned_start,'planned_finish',a.planned_finish,'contractor_vendor_id',a.contractor_vendor_id) order by a.wbs_code,a.id) from site.activities a where a.project_id=target_project_id),'[]'::jsonb),
    'dependencies',coalesce((select jsonb_agg(jsonb_build_object('predecessor_activity_id',d.predecessor_activity_id,'successor_activity_id',d.successor_activity_id,'relationship',d.relationship,'lag_days',d.lag_days) order by d.predecessor_activity_id,d.successor_activity_id) from site.activity_dependencies d where d.project_id=target_project_id),'[]'::jsonb)
  );
  hash_value:=encode(extensions.digest(snapshot::text,'sha256'),'hex');
  select coalesce(max(version),0)+1 into version_value from site.programmes where project_id=target_project_id;
  perform set_config('conceptspaces.site_phase','programme',true);
  update site.programmes set status='superseded' where project_id=target_project_id and status='baselined';
  insert into site.programmes(project_id,version,title,status,baseline_snapshot,baseline_hash,baselined_by) values(target_project_id,version_value,btrim(target_title),'baselined',snapshot,hash_value,auth.uid()) returning * into prog;
  select organisation_id into org_id from project.projects where id=target_project_id; perform audit.append_event(org_id,target_project_id,'site.programme.baselined','programme',prog.id,null,to_jsonb(prog),hash_value,gen_random_uuid()); return prog.id;
end;$$;
revoke all on function public.baseline_site_programme(uuid,text) from public,anon; grant execute on function public.baseline_site_programme(uuid,text) to authenticated;

create or replace function public.list_site_programme_workspace(target_project_id uuid)
returns jsonb
language plpgsql stable security invoker
set search_path=public,site,project,pg_temp
as $$
begin
  if auth.uid() is null or not project.can_access_project(target_project_id) then raise exception 'project_access_required'; end if;
  return jsonb_build_object(
    'programmes',coalesce((select jsonb_agg(to_jsonb(p) order by p.version desc) from site.programmes p where p.project_id=target_project_id),'[]'::jsonb),
    'activities',coalesce((select jsonb_agg(to_jsonb(a) order by a.wbs_code) from site.activities a where a.project_id=target_project_id),'[]'::jsonb),
    'dependencies',coalesce((select jsonb_agg(to_jsonb(d) order by d.created_at) from site.activity_dependencies d where d.project_id=target_project_id),'[]'::jsonb)
  );
end;$$;
revoke all on function public.list_site_programme_workspace(uuid) from public,anon; grant execute on function public.list_site_programme_workspace(uuid) to authenticated;

commit;
