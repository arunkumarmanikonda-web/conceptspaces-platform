begin;

create schema if not exists integration_private;
revoke all on schema integration_private from public,anon;
grant usage on schema integration_private to authenticated,service_role;
grant usage on schema integration to authenticated,service_role;
grant select on integration.providers,integration.instances,integration.outbound_messages,integration.payment_transactions to authenticated;

alter table integration.outbound_messages add column if not exists payload jsonb not null default '{}'::jsonb;
alter table integration.outbound_messages add column if not exists consent_basis text;
alter table integration.outbound_messages add column if not exists attempt_count integer not null default 0;
alter table integration.outbound_messages add column if not exists next_attempt_at timestamptz;
alter table integration.outbound_messages add column if not exists locked_at timestamptz;
alter table integration.outbound_messages drop constraint if exists outbound_messages_status_check;
alter table integration.outbound_messages add constraint outbound_messages_status_check check (status in ('queued','processing','accepted','sent','delivered','failed','cancelled'));
create index if not exists outbound_messages_dispatch_idx on integration.outbound_messages(status,coalesce(next_attempt_at,created_at));
create index if not exists outbound_messages_provider_idx on integration.outbound_messages(provider_key,environment,created_at desc);

alter table public.payment_transactions add column if not exists provider_order_id text;
create unique index if not exists payment_transactions_provider_event_unique on public.payment_transactions(provider,provider_event_id) where provider_event_id is not null;
create index if not exists payment_transactions_provider_order_idx on public.payment_transactions(provider,provider_order_id) where provider_order_id is not null;

create or replace function integration_private.configure_provider_instance_impl(
  target_organisation_id uuid,
  target_provider_key text,
  target_environment text,
  target_config jsonb,
  secret_updates jsonb,
  target_enabled boolean
)
returns uuid
language plpgsql
security definer
set search_path=integration,integration_private,core,vault,audit,auth,public,pg_temp
as $$
declare
  actor uuid:=auth.uid();
  instance_id uuid;
  refs jsonb:='{}'::jsonb;
  field_name text;
  secret_value text;
  existing_secret_id uuid;
  new_secret_id uuid;
  vault_name text;
begin
  if actor is null then raise exception 'authentication_required'; end if;
  if target_organisation_id is null or not core.has_org_role(target_organisation_id,array['super_admin','org_admin']) then raise exception 'organisation_admin_required'; end if;
  if target_environment not in ('sandbox','production') then raise exception 'unsupported_provider_environment'; end if;
  if not exists(select 1 from integration.providers p where p.provider_key=target_provider_key) then raise exception 'unknown_provider'; end if;

  select i.id,coalesce(i.secret_refs,'{}'::jsonb) into instance_id,refs
  from integration.instances i
  where i.organisation_id=target_organisation_id and i.provider_key=target_provider_key and i.environment=target_environment
  for update;

  if instance_id is null then
    insert into integration.instances(organisation_id,provider_key,environment,status,enabled,config,secret_refs,created_by,updated_by)
    values(target_organisation_id,target_provider_key,target_environment,'not_configured',false,coalesce(target_config,'{}'::jsonb),'{}'::jsonb,actor,actor)
    returning id,secret_refs into instance_id,refs;
  end if;

  if secret_updates is not null and jsonb_typeof(secret_updates)='object' then
    for field_name,secret_value in select key,value from jsonb_each_text(secret_updates)
    loop
      if nullif(btrim(secret_value),'') is null then continue; end if;
      begin existing_secret_id:=(refs->>field_name)::uuid; exception when others then existing_secret_id:=null; end;
      vault_name:='conceptspaces/'||target_organisation_id::text||'/'||target_provider_key||'/'||target_environment||'/'||field_name;
      if existing_secret_id is null then
        select vault.create_secret(secret_value,vault_name,'Concept Spaces provider credential',null) into new_secret_id;
        refs:=jsonb_set(refs,array[field_name],to_jsonb(new_secret_id::text),true);
      else
        perform vault.update_secret(existing_secret_id,secret_value,vault_name,'Concept Spaces provider credential',null);
      end if;
    end loop;
  end if;

  update integration.instances
  set config=coalesce(target_config,'{}'::jsonb),secret_refs=refs,
      status=case when jsonb_object_length(refs)>0 or coalesce(target_config,'{}'::jsonb)<>'{}'::jsonb then 'configured' else 'not_configured' end,
      enabled=target_enabled,updated_by=actor,updated_at=now()
  where id=instance_id;

  perform audit.append_event(target_organisation_id,null,'integration.provider.configured','integration_instance',instance_id,null,
    jsonb_build_object('provider_key',target_provider_key,'environment',target_environment,'enabled',target_enabled,'configured_secret_fields',(select coalesce(jsonb_agg(k),'[]'::jsonb) from jsonb_object_keys(refs) k)),null,gen_random_uuid());
  return instance_id;
end;
$$;
revoke all on function integration_private.configure_provider_instance_impl(uuid,text,text,jsonb,jsonb,boolean) from public,anon;
grant execute on function integration_private.configure_provider_instance_impl(uuid,text,text,jsonb,jsonb,boolean) to authenticated;

create or replace function public.configure_provider_instance(
  target_organisation_id uuid,target_provider_key text,target_environment text,target_config jsonb,secret_updates jsonb,target_enabled boolean
)
returns uuid
language sql
security invoker
set search_path=public,integration_private,pg_temp
as $$ select integration_private.configure_provider_instance_impl(target_organisation_id,target_provider_key,target_environment,target_config,secret_updates,target_enabled); $$;
revoke all on function public.configure_provider_instance(uuid,text,text,jsonb,jsonb,boolean) from public,anon;
grant execute on function public.configure_provider_instance(uuid,text,text,jsonb,jsonb,boolean) to authenticated;

create or replace function public.list_user_organisations()
returns table(id uuid,name text,role_code text)
language sql stable security invoker
set search_path=core,public,auth,pg_temp
as $$
  select o.id,o.name,m.role_code from core.memberships m join core.organisations o on o.id=m.organisation_id
  where m.user_id=auth.uid() and m.status='active' order by o.name;
$$;
revoke all on function public.list_user_organisations() from public,anon;
grant execute on function public.list_user_organisations() to authenticated;

create or replace function public.list_provider_instances(target_organisation_id uuid)
returns table(provider_key text,display_name text,category text,supports_sandbox boolean,webhook_capable boolean,environment text,status text,enabled boolean,config jsonb,configured_secret_fields jsonb,verified_at timestamptz,last_health_check_at timestamptz,last_health_status text)
language sql stable security invoker
set search_path=integration,core,public,auth,pg_temp
as $$
  select p.provider_key,p.display_name,p.category,p.supports_sandbox,p.webhook_capable,
    coalesce(i.environment,'production'),coalesce(i.status,'not_configured'),coalesce(i.enabled,false),coalesce(i.config,'{}'::jsonb),
    coalesce((select jsonb_agg(k order by k) from jsonb_object_keys(coalesce(i.secret_refs,'{}'::jsonb)) k),'[]'::jsonb),
    i.verified_at,i.last_health_check_at,i.last_health_status
  from integration.providers p
  left join integration.instances i on i.provider_key=p.provider_key and i.organisation_id=target_organisation_id
  where core.is_org_member(target_organisation_id)
  order by p.category,p.display_name,coalesce(i.environment,'production');
$$;
revoke all on function public.list_provider_instances(uuid) from public,anon;
grant execute on function public.list_provider_instances(uuid) to authenticated;

grant insert on integration.outbound_messages to authenticated;
drop policy if exists outbound_messages_runtime_insert on integration.outbound_messages;
create policy outbound_messages_runtime_insert on integration.outbound_messages for insert to authenticated
with check (
  current_setting('conceptspaces.provider_phase',true)='queue'
  and current_setting('conceptspaces.provider_actor',true)=auth.uid()::text
  and organisation_id=nullif(current_setting('conceptspaces.provider_org',true),'')::uuid
  and created_by=auth.uid() and status='queued'
  and core.is_org_member(organisation_id)
  and (project_id is null or project.can_access_project(project_id))
);

create or replace function public.queue_provider_message(
  target_organisation_id uuid,target_project_id uuid,target_channel text,target_recipient text,target_purpose text,
  target_template_key text,target_subject text,target_payload jsonb,target_consent_basis text,target_idempotency_key text
)
returns uuid
language plpgsql security invoker
set search_path=integration,core,project,public,auth,pg_temp
as $$
declare
  actor uuid:=auth.uid(); provider text; env text; message_id uuid; purpose_value text:=lower(btrim(target_purpose));
begin
  if actor is null then raise exception 'authentication_required'; end if;
  if not core.is_org_member(target_organisation_id) then raise exception 'organisation_membership_required'; end if;
  if target_project_id is not null and not project.can_access_project(target_project_id) then raise exception 'project_access_required'; end if;
  if lower(target_channel) not in ('email','whatsapp','sms') then raise exception 'unsupported_channel'; end if;
  if purpose_value not in ('project_notification','approval_request','invoice_notice','contract_notice','security_notice','otp','system_notice') then raise exception 'unsupported_transactional_purpose'; end if;
  if nullif(btrim(target_recipient),'') is null then raise exception 'recipient_required'; end if;
  if nullif(btrim(target_idempotency_key),'') is null then raise exception 'idempotency_key_required'; end if;
  provider:=case lower(target_channel) when 'email' then 'resend' when 'whatsapp' then 'aisensy' when 'sms' then 'fast2sms' end;
  select i.environment into env from integration.instances i where i.organisation_id=target_organisation_id and i.provider_key=provider and i.enabled=true and i.status in ('configured','verified') order by case i.environment when 'production' then 0 else 1 end limit 1;
  if env is null then raise exception 'provider_not_configured'; end if;
  perform set_config('conceptspaces.provider_phase','queue',true); perform set_config('conceptspaces.provider_actor',actor::text,true); perform set_config('conceptspaces.provider_org',target_organisation_id::text,true);
  insert into integration.outbound_messages(organisation_id,project_id,channel,provider_key,environment,idempotency_key,recipient,purpose,template_key,subject,payload,variables,consent_basis,status,created_by,next_attempt_at)
  values(target_organisation_id,target_project_id,lower(target_channel),provider,env,btrim(target_idempotency_key),btrim(target_recipient),purpose_value,nullif(btrim(target_template_key),''),nullif(btrim(target_subject),''),coalesce(target_payload,'{}'::jsonb),coalesce(target_payload,'{}'::jsonb),nullif(btrim(target_consent_basis),''),'queued',actor,now())
  on conflict (organisation_id,channel,idempotency_key) do update set idempotency_key=excluded.idempotency_key
  returning id into message_id;
  return message_id;
end;
$$;
revoke all on function public.queue_provider_message(uuid,uuid,text,text,text,text,text,jsonb,text,text) from public,anon;
grant execute on function public.queue_provider_message(uuid,uuid,text,text,text,text,text,jsonb,text,text) to authenticated;

create or replace function public.authorize_provider_dispatch(target_message_id uuid)
returns boolean language sql stable security invoker
set search_path=integration,core,public,auth,pg_temp
as $$
  select exists(select 1 from integration.outbound_messages m where m.id=target_message_id and (m.created_by=auth.uid() or core.has_org_role(m.organisation_id,array['super_admin','org_admin','project_manager'])) and m.status in ('queued','failed'));
$$;
revoke all on function public.authorize_provider_dispatch(uuid) from public,anon;
grant execute on function public.authorize_provider_dispatch(uuid) to authenticated;

create or replace function public.provider_runtime_material(target_organisation_id uuid,target_provider_key text,target_environment text)
returns jsonb
language plpgsql security definer
set search_path=integration,vault,public,pg_temp
as $$
declare i integration.instances%rowtype; secrets jsonb:='{}'::jsonb; k text; sid uuid; v text;
begin
  select * into i from integration.instances where organisation_id=target_organisation_id and provider_key=target_provider_key and environment=target_environment and enabled=true and status in ('configured','verified');
  if not found then raise exception 'provider_not_configured'; end if;
  for k,v in select key,value from jsonb_each_text(coalesce(i.secret_refs,'{}'::jsonb)) loop
    begin sid:=v::uuid; exception when others then continue; end;
    select ds.decrypted_secret into v from vault.decrypted_secrets ds where ds.id=sid;
    if v is not null then secrets:=jsonb_set(secrets,array[k],to_jsonb(v),true); end if;
  end loop;
  return jsonb_build_object('provider_key',i.provider_key,'environment',i.environment,'config',i.config,'secrets',secrets);
end;
$$;
revoke all on function public.provider_runtime_material(uuid,text,text) from public,anon,authenticated;
grant execute on function public.provider_runtime_material(uuid,text,text) to service_role;

create or replace function public.claim_provider_message(target_message_id uuid)
returns jsonb
language plpgsql security definer
set search_path=integration,public,pg_temp
as $$
declare m integration.outbound_messages%rowtype;
begin
  select * into m from integration.outbound_messages where id=target_message_id for update;
  if not found then raise exception 'message_not_found'; end if;
  if m.status not in ('queued','failed') then raise exception 'message_not_dispatchable'; end if;
  if coalesce(m.next_attempt_at,now())>now() then raise exception 'message_not_ready'; end if;
  update integration.outbound_messages set status='processing',attempt_count=attempt_count+1,locked_at=now(),error=null where id=m.id returning * into m;
  return to_jsonb(m);
end;
$$;
revoke all on function public.claim_provider_message(uuid) from public,anon,authenticated;
grant execute on function public.claim_provider_message(uuid) to service_role;

create or replace function public.complete_provider_message(target_message_id uuid,target_status text,target_provider_message_id text,target_error jsonb)
returns void
language plpgsql security definer
set search_path=integration,public,pg_temp
as $$
declare s text:=lower(target_status);
begin
  if s not in ('accepted','sent','delivered','failed','cancelled') then raise exception 'unsupported_delivery_status'; end if;
  update integration.outbound_messages set status=s,provider_message_id=coalesce(nullif(target_provider_message_id,''),provider_message_id),error=target_error,
    sent_at=case when s in ('accepted','sent','delivered') then coalesce(sent_at,now()) else sent_at end,
    delivered_at=case when s='delivered' then coalesce(delivered_at,now()) else delivered_at end,
    next_attempt_at=case when s='failed' and attempt_count<5 then now()+(least(3600,power(2,attempt_count)::int*30)||' seconds')::interval else null end,
    locked_at=null where id=target_message_id;
end;
$$;
revoke all on function public.complete_provider_message(uuid,text,text,jsonb) from public,anon,authenticated;
grant execute on function public.complete_provider_message(uuid,text,text,jsonb) to service_role;

create or replace function public.record_provider_health(target_provider_key text,target_environment text,target_status text,target_latency_ms integer,target_error_code text)
returns void
language plpgsql security definer
set search_path=public,integration,pg_temp
as $$
begin
  insert into public.provider_health_checks(provider_key,environment,status,latency_ms,consecutive_failures,last_error_code,checked_at)
  values(target_provider_key,target_environment,target_status,target_latency_ms,case when target_status in ('degraded','down') then 1 else 0 end,target_error_code,now());
  update integration.instances set last_health_check_at=now(),last_health_status=target_status,
    status=case when target_status='healthy' and status='configured' then 'verified' when target_status in ('degraded','down') then 'degraded' else status end,
    verified_at=case when target_status='healthy' then coalesce(verified_at,now()) else verified_at end,updated_at=now()
  where provider_key=target_provider_key and environment=target_environment and enabled=true;
end;
$$;
revoke all on function public.record_provider_health(text,text,text,integer,text) from public,anon,authenticated;
grant execute on function public.record_provider_health(text,text,text,integer,text) to service_role;

create or replace function public.prepare_invoice_payment(target_invoice_id uuid)
returns jsonb
language plpgsql security invoker
set search_path=public,core,project,auth,pg_temp
as $$
declare i public.invoices%rowtype; remaining numeric;
begin
  select * into i from public.invoices where id=target_invoice_id;
  if not found then raise exception 'invoice_not_found'; end if;
  if not core.has_org_role(i.organisation_id,array['super_admin','org_admin','finance','project_manager']) then raise exception 'payment_authority_required'; end if;
  if i.status not in ('issued','part_paid','overdue') then raise exception 'invoice_not_payment_eligible'; end if;
  remaining:=i.total-i.amount_paid;
  if remaining<=0 then raise exception 'invoice_has_no_balance'; end if;
  return jsonb_build_object('invoice_id',i.id,'organisation_id',i.organisation_id,'project_id',i.project_id,'invoice_number',i.invoice_number,'currency',upper(i.currency),'amount_minor',round(remaining*100)::bigint,'receipt','INV-'||i.invoice_number,'idempotency_key','invoice:'||i.id::text||':'||round(remaining*100)::bigint::text);
end;
$$;
revoke all on function public.prepare_invoice_payment(uuid) from public,anon;
grant execute on function public.prepare_invoice_payment(uuid) to authenticated;

create or replace function public.register_razorpay_order(target_invoice_id uuid,target_order_id text,target_amount_minor bigint,target_currency text,target_idempotency_key text,target_metadata jsonb)
returns uuid
language plpgsql security definer
set search_path=public,pg_temp
as $$
declare i public.invoices%rowtype; tx_id uuid;
begin
  select * into i from public.invoices where id=target_invoice_id;
  if not found then raise exception 'invoice_not_found'; end if;
  if target_amount_minor<=0 then raise exception 'invalid_payment_amount'; end if;
  insert into public.payment_transactions(organisation_id,invoice_id,provider,provider_order_id,amount,currency,status,idempotency_key,metadata)
  values(i.organisation_id,i.id,'razorpay',target_order_id,target_amount_minor::numeric/100.0,upper(target_currency),'created',target_idempotency_key,coalesce(target_metadata,'{}'::jsonb))
  on conflict(provider,idempotency_key) do update set provider_order_id=excluded.provider_order_id,updated_at=now()
  returning id into tx_id;
  return tx_id;
end;
$$;
revoke all on function public.register_razorpay_order(uuid,text,bigint,text,text,jsonb) from public,anon,authenticated;
grant execute on function public.register_razorpay_order(uuid,text,bigint,text,text,jsonb) to service_role;

create or replace function public.ingest_razorpay_capture(target_organisation_id uuid,target_event_id text,target_payment_id text,target_order_id text,target_amount_minor bigint,target_currency text,target_raw_hash text)
returns jsonb
language plpgsql security definer
set search_path=public,finance,audit,pg_temp
as $$
declare tx public.payment_transactions%rowtype; result jsonb;
begin
  select * into tx from public.payment_transactions where organisation_id=target_organisation_id and provider='razorpay' and provider_order_id=target_order_id for update;
  if not found then raise exception 'razorpay_order_not_registered'; end if;
  if tx.provider_event_id=target_event_id and tx.applied_at is not null then return jsonb_build_object('duplicate',true,'transaction_id',tx.id,'applied_at',tx.applied_at); end if;
  if target_amount_minor<=0 or round(tx.amount*100)::bigint<>target_amount_minor then raise exception 'razorpay_amount_mismatch'; end if;
  if upper(tx.currency)<>upper(target_currency) then raise exception 'razorpay_currency_mismatch'; end if;
  update public.payment_transactions set provider_payment_id=target_payment_id,provider_event_id=target_event_id,status='captured',metadata=coalesce(metadata,'{}'::jsonb)||jsonb_build_object('webhook_raw_hash',target_raw_hash),updated_at=now() where id=tx.id returning * into tx;
  result:=finance.apply_captured_payment(tx.id);
  return result||jsonb_build_object('transaction_id',tx.id,'duplicate',false);
end;
$$;
revoke all on function public.ingest_razorpay_capture(uuid,text,text,text,bigint,text,text) from public,anon,authenticated;
grant execute on function public.ingest_razorpay_capture(uuid,text,text,text,bigint,text,text) to service_role;

commit;