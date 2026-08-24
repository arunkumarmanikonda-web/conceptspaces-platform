begin;

-- F02: effective-dated business configuration.
create table if not exists configuration.config_versions(
  id uuid primary key default gen_random_uuid(),
  organisation_id uuid references core.organisations(id) on delete cascade,
  namespace text not null,
  config_key text not null,
  version integer not null,
  status text not null default 'draft' check(status in ('draft','review','published','retired')),
  value jsonb not null,
  schema_definition jsonb not null default '{}'::jsonb,
  effective_from timestamptz not null,
  effective_until timestamptz,
  supersedes_id uuid references configuration.config_versions(id) on delete restrict,
  rollback_of_id uuid references configuration.config_versions(id) on delete restrict,
  created_by uuid references auth.users(id) on delete set null,
  published_by uuid references auth.users(id) on delete set null,
  created_at timestamptz not null default now(),
  published_at timestamptz,
  updated_at timestamptz not null default now(),
  change_reason text,
  content_hash text not null,
  constraint config_effective_range check(effective_until is null or effective_until>=effective_from)
);
create unique index if not exists config_versions_scope_version_uidx on configuration.config_versions(coalesce(organisation_id,'00000000-0000-0000-0000-000000000000'::uuid),namespace,config_key,version);
create index if not exists config_versions_resolution_idx on configuration.config_versions(namespace,config_key,status,effective_from,effective_until);
alter table configuration.config_versions enable row level security;
grant select,insert,update on configuration.config_versions to authenticated;

drop policy if exists config_versions_admin_read on configuration.config_versions;
create policy config_versions_admin_read on configuration.config_versions for select to authenticated using(core.is_platform_admin() or (organisation_id is not null and core.has_org_role(organisation_id,array['org_admin'])));
drop policy if exists config_versions_admin_insert on configuration.config_versions;
create policy config_versions_admin_insert on configuration.config_versions for insert to authenticated with check((core.is_platform_admin() or (organisation_id is not null and core.has_org_role(organisation_id,array['org_admin']))) and current_setting('conceptspaces.config_phase',true) in ('draft','rollback'));
drop policy if exists config_versions_admin_update on configuration.config_versions;
create policy config_versions_admin_update on configuration.config_versions for update to authenticated using(core.is_platform_admin() or (organisation_id is not null and core.has_org_role(organisation_id,array['org_admin']))) with check((core.is_platform_admin() or (organisation_id is not null and core.has_org_role(organisation_id,array['org_admin']))) and current_setting('conceptspaces.config_phase',true) in ('review','publish','retire','supersede'));

create or replace function configuration.guard_published_config_mutation()
returns trigger language plpgsql security definer set search_path='configuration','pg_temp' as $$
begin
  if old.status='published' then
    if current_setting('conceptspaces.config_phase',true) not in ('retire','supersede') then raise exception 'PUBLISHED_CONFIG_IMMUTABLE';end if;
    if new.organisation_id is distinct from old.organisation_id or new.namespace is distinct from old.namespace or new.config_key is distinct from old.config_key or new.version is distinct from old.version or new.value is distinct from old.value or new.schema_definition is distinct from old.schema_definition or new.effective_from is distinct from old.effective_from or new.supersedes_id is distinct from old.supersedes_id or new.rollback_of_id is distinct from old.rollback_of_id or new.created_by is distinct from old.created_by or new.content_hash is distinct from old.content_hash then raise exception 'PUBLISHED_CONFIG_CONTENT_IMMUTABLE';end if;
  end if;
  return new;
end;$$;
revoke all on function configuration.guard_published_config_mutation() from public,anon,authenticated;
drop trigger if exists trg_guard_published_config_mutation on configuration.config_versions;
create trigger trg_guard_published_config_mutation before update on configuration.config_versions for each row execute function configuration.guard_published_config_mutation();

create or replace function public.create_config_version(target_organisation_id uuid,input_payload jsonb)
returns uuid language plpgsql security invoker set search_path='configuration','core','audit','extensions','auth','pg_temp' as $$
declare r configuration.config_versions%rowtype;v int;ns text:=btrim(input_payload->>'namespace');k text:=btrim(input_payload->>'key');ef timestamptz:=coalesce(nullif(input_payload->>'effective_from','')::timestamptz,now());eu timestamptz:=nullif(input_payload->>'effective_until','')::timestamptz;h text;audit_org uuid;
begin
 if auth.uid() is null then raise exception 'authentication_required';end if;
 if target_organisation_id is null then if not core.is_platform_admin() then raise exception 'platform_admin_required';end if;elsif not (core.is_platform_admin() or core.has_org_role(target_organisation_id,array['org_admin'])) then raise exception 'organisation_admin_required';end if;
 if nullif(ns,'') is null or nullif(k,'') is null or input_payload->'value' is null then raise exception 'config_namespace_key_value_required';end if;
 if eu is not null and eu<ef then raise exception 'config_effective_range_invalid';end if;
 if (input_payload->'value')::text ~* '"(secret|password|token|api[_-]?key|private[_-]?key)"[[:space:]]*:' then raise exception 'SECRETS_FORBIDDEN_IN_CONFIG';end if;
 select coalesce(max(version),0)+1 into v from configuration.config_versions x where x.organisation_id is not distinct from target_organisation_id and x.namespace=ns and x.config_key=k;
 h:=encode(extensions.digest(jsonb_build_object('organisation_id',target_organisation_id,'namespace',ns,'key',k,'version',v,'value',input_payload->'value','schema_definition',coalesce(input_payload->'schema_definition','{}'::jsonb),'effective_from',ef,'effective_until',eu)::text,'sha256'),'hex');
 perform set_config('conceptspaces.config_phase','draft',true);
 insert into configuration.config_versions(organisation_id,namespace,config_key,version,status,value,schema_definition,effective_from,effective_until,created_by,change_reason,content_hash) values(target_organisation_id,ns,k,v,'draft',input_payload->'value',coalesce(input_payload->'schema_definition','{}'::jsonb),ef,eu,auth.uid(),nullif(btrim(input_payload->>'reason'),''),h) returning * into r;
 audit_org:=coalesce(target_organisation_id,(select organisation_id from core.memberships where user_id=auth.uid() and status='active' order by case when role_code='super_admin' then 0 else 1 end limit 1));
 if audit_org is not null then perform audit.append_event(audit_org,null,'config.version_created','config_version',r.id,null,to_jsonb(r),h,gen_random_uuid());end if;
 return r.id;
end;$$;
revoke all on function public.create_config_version(uuid,jsonb) from public,anon;grant execute on function public.create_config_version(uuid,jsonb) to authenticated;

create or replace function public.transition_config_version(target_config_id uuid,target_status text,target_reason text)
returns text language plpgsql security invoker set search_path='configuration','core','audit','auth','pg_temp' as $$
declare r configuration.config_versions%rowtype;s text:=lower(btrim(target_status));before_state jsonb;prior configuration.config_versions%rowtype;audit_org uuid;overlap_count int;
begin
 select * into r from configuration.config_versions where id=target_config_id for update;if not found then raise exception 'config_version_not_found';end if;
 if auth.uid() is null then raise exception 'authentication_required';end if;
 if r.organisation_id is null then if not core.is_platform_admin() then raise exception 'platform_admin_required';end if;elsif not (core.is_platform_admin() or core.has_org_role(r.organisation_id,array['org_admin'])) then raise exception 'organisation_admin_required';end if;
 if nullif(btrim(target_reason),'') is null then raise exception 'config_transition_reason_required';end if;
 if (r.status='draft' and s<>'review') or (r.status='review' and s not in ('draft','published')) or (r.status='published' and s<>'retired') then raise exception 'config_transition_invalid';end if;
 if s='published' and r.created_by=auth.uid() then raise exception 'maker_cannot_publish_own_config';end if;
 before_state:=to_jsonb(r);
 if s='published' then
   select * into prior from configuration.config_versions x where x.id<>r.id and x.organisation_id is not distinct from r.organisation_id and x.namespace=r.namespace and x.config_key=r.config_key and x.status='published' and x.effective_from<r.effective_from and (x.effective_until is null or x.effective_until>=r.effective_from) order by x.effective_from desc limit 1 for update;
   if found then perform set_config('conceptspaces.config_phase','supersede',true);update configuration.config_versions set effective_until=r.effective_from-interval '1 microsecond',updated_at=now() where id=prior.id;end if;
   select count(*) into overlap_count from configuration.config_versions x where x.id<>r.id and x.organisation_id is not distinct from r.organisation_id and x.namespace=r.namespace and x.config_key=r.config_key and x.status='published' and tstzrange(x.effective_from,coalesce(x.effective_until,'infinity'::timestamptz),'[]') && tstzrange(r.effective_from,coalesce(r.effective_until,'infinity'::timestamptz),'[]');
   if overlap_count>0 then raise exception 'EFFECTIVE_DATE_OVERLAP';end if;
   perform set_config('conceptspaces.config_phase','publish',true);update configuration.config_versions set status='published',published_by=auth.uid(),published_at=now(),supersedes_id=coalesce(r.supersedes_id,prior.id),updated_at=now(),change_reason=target_reason where id=r.id returning * into r;
 elsif s='retired' then perform set_config('conceptspaces.config_phase','retire',true);update configuration.config_versions set status='retired',effective_until=coalesce(effective_until,now()),updated_at=now(),change_reason=target_reason where id=r.id returning * into r;
 else perform set_config('conceptspaces.config_phase','review',true);update configuration.config_versions set status=s,updated_at=now(),change_reason=target_reason where id=r.id returning * into r;
 end if;
 audit_org:=coalesce(r.organisation_id,(select organisation_id from core.memberships where user_id=auth.uid() and status='active' limit 1));if audit_org is not null then perform audit.append_event(audit_org,null,'config.version_'||s,'config_version',r.id,before_state,to_jsonb(r),target_reason,gen_random_uuid());end if;return r.status;
end;$$;
revoke all on function public.transition_config_version(uuid,text,text) from public,anon;grant execute on function public.transition_config_version(uuid,text,text) to authenticated;

create or replace function public.rollback_config_version(source_config_id uuid,target_effective_from timestamptz,target_reason text)
returns uuid language plpgsql security invoker set search_path='configuration','core','audit','extensions','auth','pg_temp' as $$
declare src configuration.config_versions%rowtype;current_row configuration.config_versions%rowtype;r configuration.config_versions%rowtype;v int;ef timestamptz:=coalesce(target_effective_from,now());h text;audit_org uuid;
begin
 select * into src from configuration.config_versions where id=source_config_id;if not found or src.status not in ('published','retired') then raise exception 'published_or_retired_source_required';end if;
 if auth.uid() is null then raise exception 'authentication_required';end if;
 if src.organisation_id is null then if not core.is_platform_admin() then raise exception 'platform_admin_required';end if;elsif not (core.is_platform_admin() or core.has_org_role(src.organisation_id,array['org_admin'])) then raise exception 'organisation_admin_required';end if;
 if src.created_by=auth.uid() then raise exception 'independent_rollback_authority_required';end if;
 if nullif(btrim(target_reason),'') is null then raise exception 'rollback_reason_required';end if;
 select * into current_row from configuration.config_versions x where x.organisation_id is not distinct from src.organisation_id and x.namespace=src.namespace and x.config_key=src.config_key and x.status='published' and x.effective_from<=ef and (x.effective_until is null or x.effective_until>=ef) order by x.effective_from desc limit 1 for update;
 if found then perform set_config('conceptspaces.config_phase','supersede',true);update configuration.config_versions set effective_until=ef-interval '1 microsecond',updated_at=now() where id=current_row.id;end if;
 select coalesce(max(version),0)+1 into v from configuration.config_versions x where x.organisation_id is not distinct from src.organisation_id and x.namespace=src.namespace and x.config_key=src.config_key;
 h:=encode(extensions.digest(jsonb_build_object('rollback_of_id',src.id,'version',v,'value',src.value,'schema_definition',src.schema_definition,'effective_from',ef)::text,'sha256'),'hex');
 perform set_config('conceptspaces.config_phase','rollback',true);
 insert into configuration.config_versions(organisation_id,namespace,config_key,version,status,value,schema_definition,effective_from,supersedes_id,rollback_of_id,created_by,published_by,published_at,change_reason,content_hash) values(src.organisation_id,src.namespace,src.config_key,v,'published',src.value,src.schema_definition,ef,current_row.id,src.id,src.created_by,auth.uid(),now(),target_reason,h) returning * into r;
 audit_org:=coalesce(r.organisation_id,(select organisation_id from core.memberships where user_id=auth.uid() and status='active' limit 1));if audit_org is not null then perform audit.append_event(audit_org,null,'config.rollback_published','config_version',r.id,to_jsonb(current_row),to_jsonb(r),target_reason,gen_random_uuid());end if;return r.id;
end;$$;
revoke all on function public.rollback_config_version(uuid,timestamptz,text) from public,anon;grant execute on function public.rollback_config_version(uuid,timestamptz,text) to authenticated;

create or replace function public.resolve_config_value(target_organisation_id uuid,target_namespace text,target_key text,target_as_of timestamptz default now())
returns jsonb language plpgsql stable security invoker set search_path='configuration','core','auth','pg_temp' as $$
declare r configuration.config_versions%rowtype;
begin
 if auth.uid() is null then raise exception 'authentication_required';end if;if target_organisation_id is not null and not core.is_org_member(target_organisation_id) then raise exception 'organisation_access_required';end if;
 select * into r from configuration.config_versions x where x.status='published' and x.namespace=btrim(target_namespace) and x.config_key=btrim(target_key) and x.effective_from<=target_as_of and (x.effective_until is null or x.effective_until>=target_as_of) and (x.organisation_id is not distinct from target_organisation_id or x.organisation_id is null) order by case when x.organisation_id is not null then 0 else 1 end,x.effective_from desc limit 1;
 if not found then return jsonb_build_object('status','not_configured','namespace',target_namespace,'key',target_key);end if;
 return jsonb_build_object('status','resolved','id',r.id,'organisation_id',r.organisation_id,'namespace',r.namespace,'key',r.config_key,'version',r.version,'value',r.value,'effective_from',r.effective_from,'effective_until',r.effective_until,'content_hash',r.content_hash);
end;$$;
revoke all on function public.resolve_config_value(uuid,text,text,timestamptz) from public,anon;grant execute on function public.resolve_config_value(uuid,text,text,timestamptz) to authenticated;

create or replace function public.list_system_config_workspace(target_organisation_id uuid)
returns jsonb language plpgsql stable security invoker set search_path='configuration','core','auth','pg_temp' as $$
begin
 if auth.uid() is null then raise exception 'authentication_required';end if;if target_organisation_id is null then if not core.is_platform_admin() then raise exception 'platform_admin_required';end if;elsif not (core.is_platform_admin() or core.has_org_role(target_organisation_id,array['org_admin'])) then raise exception 'organisation_admin_required';end if;
 return jsonb_build_object('versions',coalesce((select jsonb_agg(to_jsonb(x) order by x.namespace,x.config_key,x.version desc) from configuration.config_versions x where x.organisation_id is not distinct from target_organisation_id),'[]'::jsonb));
end;$$;
revoke all on function public.list_system_config_workspace(uuid) from public,anon;grant execute on function public.list_system_config_workspace(uuid) to authenticated;

-- F02: versioned workflow definitions and graph simulation.
create table if not exists workflow.workflow_versions(
  id uuid primary key default gen_random_uuid(),
  organisation_id uuid references core.organisations(id) on delete cascade,
  workflow_code text not null,
  name text not null,
  version integer not null,
  status text not null default 'draft' check(status in ('draft','review','published','retired')),
  trigger_type text not null,
  max_criticality text not null check(max_criticality in ('C0','C1','C2','C3','C4')),
  definition jsonb not null,
  simulation_result jsonb not null default '{}'::jsonb,
  supersedes_id uuid references workflow.workflow_versions(id) on delete restrict,
  created_by uuid references auth.users(id) on delete set null,
  approved_by uuid references auth.users(id) on delete set null,
  created_at timestamptz not null default now(),
  published_at timestamptz,
  updated_at timestamptz not null default now(),
  content_hash text not null
);
create unique index if not exists workflow_versions_scope_version_uidx on workflow.workflow_versions(coalesce(organisation_id,'00000000-0000-0000-0000-000000000000'::uuid),workflow_code,version);
alter table workflow.workflow_versions enable row level security;
grant select,insert,update on workflow.workflow_versions to authenticated;
drop policy if exists workflow_versions_admin_read on workflow.workflow_versions;
create policy workflow_versions_admin_read on workflow.workflow_versions for select to authenticated using(core.is_platform_admin() or (organisation_id is not null and core.has_org_role(organisation_id,array['org_admin'])));
drop policy if exists workflow_versions_admin_insert on workflow.workflow_versions;
create policy workflow_versions_admin_insert on workflow.workflow_versions for insert to authenticated with check((core.is_platform_admin() or (organisation_id is not null and core.has_org_role(organisation_id,array['org_admin']))) and current_setting('conceptspaces.workflow_phase',true)='draft');
drop policy if exists workflow_versions_admin_update on workflow.workflow_versions;
create policy workflow_versions_admin_update on workflow.workflow_versions for update to authenticated using(core.is_platform_admin() or (organisation_id is not null and core.has_org_role(organisation_id,array['org_admin']))) with check((core.is_platform_admin() or (organisation_id is not null and core.has_org_role(organisation_id,array['org_admin']))) and current_setting('conceptspaces.workflow_phase',true) in ('review','publish','retire','supersede'));

create or replace function workflow.guard_published_workflow_mutation()
returns trigger language plpgsql security definer set search_path='workflow','pg_temp' as $$
begin
 if old.status='published' then
  if current_setting('conceptspaces.workflow_phase',true) not in ('retire','supersede') then raise exception 'PUBLISHED_WORKFLOW_IMMUTABLE';end if;
  if new.organisation_id is distinct from old.organisation_id or new.workflow_code is distinct from old.workflow_code or new.name is distinct from old.name or new.version is distinct from old.version or new.trigger_type is distinct from old.trigger_type or new.max_criticality is distinct from old.max_criticality or new.definition is distinct from old.definition or new.created_by is distinct from old.created_by or new.content_hash is distinct from old.content_hash then raise exception 'PUBLISHED_WORKFLOW_CONTENT_IMMUTABLE';end if;
 end if;return new;
end;$$;
revoke all on function workflow.guard_published_workflow_mutation() from public,anon,authenticated;
drop trigger if exists trg_guard_published_workflow_mutation on workflow.workflow_versions;
create trigger trg_guard_published_workflow_mutation before update on workflow.workflow_versions for each row execute function workflow.guard_published_workflow_mutation();

create or replace function public.create_workflow_version(target_organisation_id uuid,input_payload jsonb)
returns uuid language plpgsql security invoker set search_path='workflow','core','audit','extensions','auth','pg_temp' as $$
declare r workflow.workflow_versions%rowtype;v int;code text:=btrim(input_payload->>'code');nm text:=btrim(input_payload->>'name');crit text:=upper(btrim(input_payload->>'max_criticality'));h text;audit_org uuid;
begin
 if auth.uid() is null then raise exception 'authentication_required';end if;if target_organisation_id is null then if not core.is_platform_admin() then raise exception 'platform_admin_required';end if;elsif not (core.is_platform_admin() or core.has_org_role(target_organisation_id,array['org_admin'])) then raise exception 'organisation_admin_required';end if;
 if nullif(code,'') is null or nullif(nm,'') is null or input_payload->'definition' is null or jsonb_typeof(input_payload->'definition')<>'object' or crit not in ('C0','C1','C2','C3','C4') then raise exception 'workflow_fields_invalid';end if;
 select coalesce(max(version),0)+1 into v from workflow.workflow_versions x where x.organisation_id is not distinct from target_organisation_id and x.workflow_code=code;
 h:=encode(extensions.digest(jsonb_build_object('organisation_id',target_organisation_id,'code',code,'name',nm,'version',v,'trigger_type',coalesce(nullif(btrim(input_payload->>'trigger_type'),''),'manual'),'max_criticality',crit,'definition',input_payload->'definition')::text,'sha256'),'hex');
 perform set_config('conceptspaces.workflow_phase','draft',true);insert into workflow.workflow_versions(organisation_id,workflow_code,name,version,status,trigger_type,max_criticality,definition,created_by,content_hash) values(target_organisation_id,code,nm,v,'draft',coalesce(nullif(btrim(input_payload->>'trigger_type'),''),'manual'),crit,input_payload->'definition',auth.uid(),h) returning * into r;
 audit_org:=coalesce(target_organisation_id,(select organisation_id from core.memberships where user_id=auth.uid() and status='active' limit 1));if audit_org is not null then perform audit.append_event(audit_org,null,'workflow.version_created','workflow_version',r.id,null,to_jsonb(r),h,gen_random_uuid());end if;return r.id;
end;$$;
revoke all on function public.create_workflow_version(uuid,jsonb) from public,anon;grant execute on function public.create_workflow_version(uuid,jsonb) to authenticated;

create or replace function public.simulate_workflow_version(target_workflow_id uuid)
returns jsonb language plpgsql stable security invoker set search_path='workflow','core','auth','pg_temp' as $$
declare r workflow.workflow_versions%rowtype;start_code text;state_count int;distinct_count int;terminal_count int;bad_transition_count int;unreachable text[]:=array[]::text[];dead_ends text[]:=array[]::text[];errors text[]:=array[]::text[];
begin
 select * into r from workflow.workflow_versions where id=target_workflow_id;if not found then raise exception 'workflow_version_not_found';end if;
 if auth.uid() is null then raise exception 'authentication_required';end if;if r.organisation_id is null then if not core.is_platform_admin() then raise exception 'platform_admin_required';end if;elsif not (core.is_platform_admin() or core.has_org_role(r.organisation_id,array['org_admin'])) then raise exception 'organisation_admin_required';end if;
 if jsonb_typeof(r.definition->'states')<>'array' or jsonb_typeof(r.definition->'transitions')<>'array' then return jsonb_build_object('passed',false,'errors',jsonb_build_array('states_and_transitions_arrays_required'),'unreachable_states','[]'::jsonb,'dead_end_states','[]'::jsonb);end if;
 start_code:=nullif(btrim(r.definition->>'start'),'');
 select count(*),count(distinct s->>'code'),count(*) filter(where lower(coalesce(s->>'terminal','false'))='true') into state_count,distinct_count,terminal_count from jsonb_array_elements(r.definition->'states') s;
 if state_count=0 then errors:=array_append(errors,'at_least_one_state_required');end if;if state_count<>distinct_count then errors:=array_append(errors,'duplicate_state_code');end if;
 if start_code is null or not exists(select 1 from jsonb_array_elements(r.definition->'states') s where s->>'code'=start_code) then errors:=array_append(errors,'start_state_missing');end if;
 if terminal_count=0 then errors:=array_append(errors,'terminal_state_required');end if;
 select count(*) into bad_transition_count from jsonb_array_elements(r.definition->'transitions') t where not exists(select 1 from jsonb_array_elements(r.definition->'states') s where s->>'code'=t->>'from') or not exists(select 1 from jsonb_array_elements(r.definition->'states') s where s->>'code'=t->>'to');
 if bad_transition_count>0 then errors:=array_append(errors,'transition_references_unknown_state');end if;
 if coalesce(array_length(errors,1),0)=0 then
   with recursive reach(code) as (select start_code union select t->>'to' from reach x join lateral jsonb_array_elements(r.definition->'transitions') t on t->>'from'=x.code) select coalesce(array_agg(s->>'code' order by s->>'code'),'{}'::text[]) into unreachable from jsonb_array_elements(r.definition->'states') s where not exists(select 1 from reach where reach.code=s->>'code');
   with recursive reach(code) as (select start_code union select t->>'to' from reach x join lateral jsonb_array_elements(r.definition->'transitions') t on t->>'from'=x.code) select coalesce(array_agg(s->>'code' order by s->>'code'),'{}'::text[]) into dead_ends from jsonb_array_elements(r.definition->'states') s where exists(select 1 from reach where reach.code=s->>'code') and lower(coalesce(s->>'terminal','false'))<>'true' and not exists(select 1 from jsonb_array_elements(r.definition->'transitions') t where t->>'from'=s->>'code');
 end if;
 if coalesce(array_length(unreachable,1),0)>0 then errors:=array_append(errors,'unreachable_states_detected');end if;if coalesce(array_length(dead_ends,1),0)>0 then errors:=array_append(errors,'reachable_dead_end_states_detected');end if;
 return jsonb_build_object('passed',coalesce(array_length(errors,1),0)=0,'errors',to_jsonb(errors),'unreachable_states',to_jsonb(unreachable),'dead_end_states',to_jsonb(dead_ends),'workflow_id',r.id,'version',r.version,'content_hash',r.content_hash);
end;$$;
revoke all on function public.simulate_workflow_version(uuid) from public,anon;grant execute on function public.simulate_workflow_version(uuid) to authenticated;

create or replace function public.transition_workflow_version(target_workflow_id uuid,target_status text,target_reason text)
returns text language plpgsql security invoker set search_path='workflow','core','audit','auth','pg_temp' as $$
declare r workflow.workflow_versions%rowtype;s text:=lower(btrim(target_status));before_state jsonb;sim jsonb;prior workflow.workflow_versions%rowtype;audit_org uuid;
begin
 select * into r from workflow.workflow_versions where id=target_workflow_id for update;if not found then raise exception 'workflow_version_not_found';end if;
 if auth.uid() is null then raise exception 'authentication_required';end if;if r.organisation_id is null then if not core.is_platform_admin() then raise exception 'platform_admin_required';end if;elsif not (core.is_platform_admin() or core.has_org_role(r.organisation_id,array['org_admin'])) then raise exception 'organisation_admin_required';end if;
 if nullif(btrim(target_reason),'') is null then raise exception 'workflow_transition_reason_required';end if;if (r.status='draft' and s<>'review') or (r.status='review' and s not in ('draft','published')) or (r.status='published' and s<>'retired') then raise exception 'workflow_transition_invalid';end if;if s='published' and r.created_by=auth.uid() then raise exception 'maker_cannot_publish_own_workflow';end if;
 before_state:=to_jsonb(r);
 if s='published' then sim:=public.simulate_workflow_version(r.id);if coalesce((sim->>'passed')::boolean,false)=false then raise exception 'WORKFLOW_SIMULATION_FAILED:%',sim::text;end if;select * into prior from workflow.workflow_versions x where x.id<>r.id and x.organisation_id is not distinct from r.organisation_id and x.workflow_code=r.workflow_code and x.status='published' order by x.version desc limit 1 for update;if found then perform set_config('conceptspaces.workflow_phase','supersede',true);update workflow.workflow_versions set status='retired',updated_at=now() where id=prior.id;end if;perform set_config('conceptspaces.workflow_phase','publish',true);update workflow.workflow_versions set status='published',simulation_result=sim,approved_by=auth.uid(),published_at=now(),supersedes_id=coalesce(r.supersedes_id,prior.id),updated_at=now() where id=r.id returning * into r;
 elsif s='retired' then perform set_config('conceptspaces.workflow_phase','retire',true);update workflow.workflow_versions set status='retired',updated_at=now() where id=r.id returning * into r;
 else perform set_config('conceptspaces.workflow_phase','review',true);update workflow.workflow_versions set status=s,updated_at=now() where id=r.id returning * into r;
 end if;
 audit_org:=coalesce(r.organisation_id,(select organisation_id from core.memberships where user_id=auth.uid() and status='active' limit 1));if audit_org is not null then perform audit.append_event(audit_org,null,'workflow.version_'||s,'workflow_version',r.id,before_state,to_jsonb(r),target_reason,gen_random_uuid());end if;return r.status;
end;$$;
revoke all on function public.transition_workflow_version(uuid,text,text) from public,anon;grant execute on function public.transition_workflow_version(uuid,text,text) to authenticated;

create or replace function public.list_workflow_definition_workspace(target_organisation_id uuid)
returns jsonb language plpgsql stable security invoker set search_path='workflow','core','auth','pg_temp' as $$
begin
 if auth.uid() is null then raise exception 'authentication_required';end if;if target_organisation_id is null then if not core.is_platform_admin() then raise exception 'platform_admin_required';end if;elsif not (core.is_platform_admin() or core.has_org_role(target_organisation_id,array['org_admin'])) then raise exception 'organisation_admin_required';end if;
 return jsonb_build_object('versions',coalesce((select jsonb_agg(to_jsonb(x) order by x.workflow_code,x.version desc) from workflow.workflow_versions x where x.organisation_id is not distinct from target_organisation_id),'[]'::jsonb));
end;$$;
revoke all on function public.list_workflow_definition_workspace(uuid) from public,anon;grant execute on function public.list_workflow_definition_workspace(uuid) to authenticated;

commit;
