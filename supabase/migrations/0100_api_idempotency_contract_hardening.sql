begin;

drop policy if exists api_credentials_org_admin_read on public.api_credentials;
create policy api_credentials_org_admin_read on public.api_credentials for select to authenticated using(core.has_org_role(organisation_id,array['super_admin','org_admin']));
drop policy if exists event_subscriptions_org_admin_read on public.event_subscriptions;
create policy event_subscriptions_org_admin_read on public.event_subscriptions for select to authenticated using(core.has_org_role(organisation_id,array['super_admin','org_admin']));

drop policy if exists data_contracts_update on integration.data_contracts;
create policy data_contracts_update on integration.data_contracts for update to authenticated using(core.is_platform_admin()) with check(core.is_platform_admin() and current_setting('conceptspaces.integration_phase',true)='contract_deprecate');

create table if not exists integration.api_idempotency_keys(
 id uuid primary key default gen_random_uuid(),
 organisation_id uuid not null references core.organisations(id) on delete cascade,
 credential_id uuid references public.api_credentials(id) on delete cascade,
 route text not null,
 idempotency_key text not null,
 request_hash text not null,
 status text not null default 'reserved' check(status in ('reserved','completed','failed')),
 resource_type text,
 resource_id uuid,
 response_hash text,
 created_at timestamptz not null default now(),
 completed_at timestamptz,
 expires_at timestamptz not null default now()+interval '24 hours',
 unique(credential_id,route,idempotency_key)
);
alter table integration.api_idempotency_keys enable row level security;
revoke all on integration.api_idempotency_keys from public,anon,authenticated;

create or replace function integration.reserve_api_idempotency(target_credential_id uuid,target_route text,target_idempotency_key text,target_request_hash text)
returns jsonb language plpgsql security definer set search_path='integration','public','pg_temp' as $$
declare r integration.api_idempotency_keys%rowtype;c public.api_credentials%rowtype;
begin
 if target_credential_id is null or nullif(btrim(target_route),'') is null or nullif(btrim(target_idempotency_key),'') is null or nullif(btrim(target_request_hash),'') is null then raise exception 'idempotency_contract_fields_required';end if;
 select * into c from public.api_credentials where id=target_credential_id;if not found or c.revoked_at is not null or (c.expires_at is not null and c.expires_at<=now()) then raise exception 'credential_invalid_or_revoked';end if;
 select * into r from integration.api_idempotency_keys where credential_id=target_credential_id and route=target_route and idempotency_key=target_idempotency_key for update;
 if found then if r.request_hash<>target_request_hash then raise exception 'IDEMPOTENCY_CONFLICT';end if;return jsonb_build_object('state',r.status,'idempotency_id',r.id,'resource_type',r.resource_type,'resource_id',r.resource_id,'response_hash',r.response_hash);end if;
 insert into integration.api_idempotency_keys(organisation_id,credential_id,route,idempotency_key,request_hash) values(c.organisation_id,c.id,btrim(target_route),btrim(target_idempotency_key),btrim(target_request_hash)) returning * into r;
 return jsonb_build_object('state','reserved','idempotency_id',r.id);
end;$$;
revoke all on function integration.reserve_api_idempotency(uuid,text,text,text) from public,anon,authenticated;grant execute on function integration.reserve_api_idempotency(uuid,text,text,text) to service_role;

create or replace function integration.complete_api_idempotency(target_idempotency_id uuid,target_status text,target_resource_type text,target_resource_id uuid,target_response_hash text)
returns void language plpgsql security definer set search_path='integration','pg_temp' as $$
declare s text:=lower(btrim(target_status));
begin if s not in ('completed','failed') then raise exception 'idempotency_completion_status_invalid';end if;update integration.api_idempotency_keys set status=s,resource_type=nullif(btrim(target_resource_type),''),resource_id=target_resource_id,response_hash=nullif(btrim(target_response_hash),''),completed_at=now() where id=target_idempotency_id and status='reserved';if not found then raise exception 'idempotency_reservation_not_found_or_closed';end if;end;$$;
revoke all on function integration.complete_api_idempotency(uuid,text,text,uuid,text) from public,anon,authenticated;grant execute on function integration.complete_api_idempotency(uuid,text,text,uuid,text) to service_role;

create or replace function public.deprecate_data_contract_version(target_version_id uuid,target_deprecation_at timestamptz,target_reason text)
returns text language plpgsql security invoker set search_path='integration','core','audit','auth','pg_temp' as $$
declare r integration.data_contract_versions%rowtype;c integration.data_contracts%rowtype;before_state jsonb;org_id uuid;
begin select * into r from integration.data_contract_versions where id=target_version_id for update;if not found then raise exception 'data_contract_version_not_found';end if;if auth.uid() is null or not core.is_platform_admin() then raise exception 'platform_admin_required';end if;if r.status<>'published' or target_deprecation_at is null or target_deprecation_at<=now() or nullif(btrim(target_reason),'') is null then raise exception 'data_contract_deprecation_window_required';end if;select * into c from integration.data_contracts where id=r.contract_id;before_state:=to_jsonb(r);perform set_config('conceptspaces.integration_phase','contract_deprecate',true);update integration.data_contract_versions set status='deprecated',deprecation_at=target_deprecation_at where id=r.id returning * into r;if not exists(select 1 from integration.data_contract_versions v where v.contract_id=c.id and v.status='published' and v.id<>r.id) then update integration.data_contracts set status='deprecated',updated_at=now() where id=c.id;end if;select organisation_id into org_id from core.memberships where user_id=auth.uid() and status='active' limit 1;if org_id is not null then perform audit.append_event(org_id,null,'schema.version_deprecated','data_contract_version',r.id,before_state,jsonb_build_object('contract_key',c.contract_key,'major',r.major_version,'minor',r.minor_version,'deprecation_at',r.deprecation_at,'schema_hash',r.schema_hash),target_reason,gen_random_uuid());end if;return r.status;end;$$;
revoke all on function public.deprecate_data_contract_version(uuid,timestamptz,text) from public,anon;grant execute on function public.deprecate_data_contract_version(uuid,timestamptz,text) to authenticated;

commit;
