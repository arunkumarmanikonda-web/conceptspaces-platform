begin;

create index if not exists outbound_messages_provider_message_idx on integration.outbound_messages(provider_key,provider_message_id) where provider_message_id is not null;

create or replace function public.apply_provider_delivery_event(
  target_provider_key text,target_provider_message_id text,target_status text,target_event_id text,target_raw_hash text,target_metadata jsonb
)
returns jsonb
language plpgsql
security definer
set search_path=integration,public,pg_temp
as $$
declare
  m integration.outbound_messages%rowtype;
  s text:=lower(target_status);
begin
  if s not in ('accepted','sent','delivered','failed') then raise exception 'unsupported_delivery_status'; end if;
  if nullif(btrim(target_provider_message_id),'') is null then raise exception 'provider_message_id_required'; end if;
  select * into m from integration.outbound_messages where provider_key=target_provider_key and provider_message_id=target_provider_message_id order by created_at desc limit 1 for update;
  if not found then return jsonb_build_object('matched',false,'provider_message_id',target_provider_message_id); end if;
  if m.status='delivered' and s in ('accepted','sent') then return jsonb_build_object('matched',true,'message_id',m.id,'status',m.status,'ignored_regression',true); end if;
  update integration.outbound_messages set status=s,
    delivered_at=case when s='delivered' then coalesce(delivered_at,now()) else delivered_at end,
    sent_at=case when s in ('accepted','sent','delivered') then coalesce(sent_at,now()) else sent_at end,
    error=case when s='failed' then coalesce(target_metadata,'{}'::jsonb) else error end,
    updated_at=now()
  where id=m.id returning * into m;
  return jsonb_build_object('matched',true,'message_id',m.id,'status',m.status,'event_id',target_event_id,'raw_hash',target_raw_hash);
end;
$$;
revoke all on function public.apply_provider_delivery_event(text,text,text,text,text,jsonb) from public,anon,authenticated;
grant execute on function public.apply_provider_delivery_event(text,text,text,text,text,jsonb) to service_role;

commit;