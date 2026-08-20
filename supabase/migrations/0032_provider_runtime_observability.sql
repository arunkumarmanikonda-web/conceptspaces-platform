begin;

alter table public.provider_health_checks add column if not exists organisation_id uuid references core.organisations(id) on delete cascade;
create index if not exists provider_health_org_provider_idx on public.provider_health_checks(organisation_id,provider_key,environment,checked_at desc);

create or replace function public.record_provider_health(target_organisation_id uuid,target_provider_key text,target_environment text,target_status text,target_latency_ms integer,target_error_code text)
returns void
language plpgsql security definer
set search_path=public,integration,pg_temp
as $$
begin
  insert into public.provider_health_checks(organisation_id,provider_key,environment,status,latency_ms,consecutive_failures,last_error_code,checked_at)
  values(target_organisation_id,target_provider_key,target_environment,target_status,target_latency_ms,case when target_status in ('degraded','down') then 1 else 0 end,target_error_code,now());
  update integration.instances set last_health_check_at=now(),last_health_status=target_status,
    status=case when target_status='healthy' and status='configured' then 'verified' when target_status in ('degraded','down') then 'degraded' else status end,
    verified_at=case when target_status='healthy' then coalesce(verified_at,now()) else verified_at end,updated_at=now()
  where organisation_id=target_organisation_id and provider_key=target_provider_key and environment=target_environment and enabled=true;
end;
$$;
revoke all on function public.record_provider_health(uuid,text,text,text,integer,text) from public,anon,authenticated;
grant execute on function public.record_provider_health(uuid,text,text,text,integer,text) to service_role;
revoke execute on function public.record_provider_health(text,text,text,integer,text) from service_role;

create or replace function public.list_provider_messages(target_organisation_id uuid,target_limit integer default 100)
returns table(id uuid,project_id uuid,channel text,provider_key text,environment text,recipient text,purpose text,template_key text,subject text,status text,attempt_count integer,provider_message_id text,last_error jsonb,created_at timestamptz,sent_at timestamptz,delivered_at timestamptz)
language sql stable security invoker
set search_path=integration,core,public,auth,pg_temp
as $$
  select m.id,m.project_id,m.channel,m.provider_key,m.environment,m.recipient,m.purpose,m.template_key,m.subject,m.status,m.attempt_count,m.provider_message_id,m.error,m.created_at,m.sent_at,m.delivered_at
  from integration.outbound_messages m
  where m.organisation_id=target_organisation_id and core.is_org_member(target_organisation_id)
  order by m.created_at desc limit greatest(1,least(coalesce(target_limit,100),250));
$$;
revoke all on function public.list_provider_messages(uuid,integer) from public,anon;
grant execute on function public.list_provider_messages(uuid,integer) to authenticated;

create or replace function public.list_provider_health(target_organisation_id uuid)
returns table(provider_key text,environment text,status text,latency_ms integer,last_error_code text,checked_at timestamptz)
language sql stable security invoker
set search_path=public,core,pg_temp
as $$
  select distinct on (h.provider_key,h.environment) h.provider_key,h.environment,h.status,h.latency_ms,h.last_error_code,h.checked_at
  from public.provider_health_checks h
  where h.organisation_id=target_organisation_id and core.is_org_member(target_organisation_id)
  order by h.provider_key,h.environment,h.checked_at desc;
$$;
revoke all on function public.list_provider_health(uuid) from public,anon;
grant execute on function public.list_provider_health(uuid) to authenticated;

commit;