begin;

drop function if exists public.invite_workspace_identity(uuid,text,text);
drop function if exists public.revoke_workspace_invitation(uuid,text);
drop function if exists public.list_workspace_invitations(uuid);

-- Service-isolated workflows can preserve the verified human actor in the
-- append-only ledger without exposing an actor override through the API.
create or replace function audit.append_event(
  target_organisation_id uuid,
  target_project_id uuid,
  target_action text,
  target_resource_type text,
  target_resource_id uuid,
  target_before_state jsonb default null,
  target_after_state jsonb default null,
  target_reason text default null,
  target_correlation_id uuid default gen_random_uuid()
)
returns uuid
language plpgsql
security definer
set search_path = audit, public, extensions, pg_temp
as $$
declare
  previous text;
  event_id uuid:=gen_random_uuid();
  event_time timestamptz:=clock_timestamp();
  payload text;
  computed text;
  actor uuid:=coalesce(auth.uid(),nullif(current_setting('conceptspaces.audit_actor',true),'')::uuid);
begin
  if target_organisation_id is null then raise exception 'audit_organisation_required'; end if;
  if nullif(btrim(target_action),'') is null then raise exception 'audit_action_required'; end if;
  if nullif(btrim(target_resource_type),'') is null then raise exception 'audit_resource_type_required'; end if;
  perform pg_advisory_xact_lock(hashtext('concept_spaces_audit_'||target_organisation_id::text));
  select event_hash into previous from audit.events
  where organisation_id=target_organisation_id order by created_at desc,id desc limit 1;
  payload:=concat_ws('|',coalesce(previous,''),event_id::text,target_organisation_id::text,
    coalesce(target_project_id::text,''),coalesce(actor::text,''),target_action,target_resource_type,
    coalesce(target_resource_id::text,''),coalesce(target_before_state::text,''),
    coalesce(target_after_state::text,''),coalesce(target_reason,''),target_correlation_id::text,event_time::text);
  computed:=encode(extensions.digest(payload,'sha256'),'hex');
  insert into audit.events(id,organisation_id,project_id,actor_id,actor_type,action,resource_type,
    resource_id,before_state,after_state,reason,correlation_id,previous_hash,event_hash,created_at)
  values(event_id,target_organisation_id,target_project_id,actor,
    case when actor is null then 'system' else 'user' end,target_action,target_resource_type,
    target_resource_id,target_before_state,target_after_state,target_reason,target_correlation_id,
    previous,computed,event_time);
  return event_id;
end;
$$;

revoke all on function audit.append_event(uuid,uuid,text,text,uuid,jsonb,jsonb,text,uuid)
  from public,anon,authenticated;
grant execute on function audit.append_event(uuid,uuid,text,text,uuid,jsonb,jsonb,text,uuid)
  to authenticated,service_role;

create or replace function public.service_invite_workspace_identity(
  actor_user_id uuid,
  target_organisation_id uuid,
  target_email text,
  target_role_code text
)
returns jsonb
language plpgsql
security definer
set search_path = core, audit, auth, extensions, pg_temp
as $$
declare
  email_value text:=lower(btrim(target_email));
  role_value text:=lower(btrim(target_role_code));
  invitation core.invitations%rowtype;
  identity_id uuid;
  identity_confirmed boolean:=false;
  identity_state text:='new';
  actor_is_platform_admin boolean;
  actor_is_org_admin boolean;
begin
  if auth.role()<>'service_role' or actor_user_id is null then raise exception 'service_role_required'; end if;
  actor_is_platform_admin:=exists(select 1 from core.memberships m
    where m.user_id=actor_user_id and m.status='active' and m.role_code='super_admin');
  actor_is_org_admin:=exists(select 1 from core.memberships m
    where m.user_id=actor_user_id and m.organisation_id=target_organisation_id
      and m.status='active' and m.role_code='org_admin');
  if not exists(select 1 from core.organisations o where o.id=target_organisation_id and o.status='active') then
    raise exception 'active_organisation_required';
  end if;
  if not (actor_is_platform_admin or actor_is_org_admin) then raise exception 'organisation_admin_required'; end if;
  if email_value !~* '^[^[:space:]@]+@[^[:space:]@]+\.[^[:space:]@]+$' then
    raise exception 'valid_work_email_required';
  end if;
  if role_value not in (
    'super_admin','org_admin','sales','project_manager','lead_architect','architect','interior_designer',
    'structural_engineer','mep_engineer','quantity_surveyor','contractor','finance','client','auditor','regulatory_reviewer'
  ) then raise exception 'unsupported_role'; end if;
  if role_value='super_admin' and not actor_is_platform_admin then raise exception 'platform_admin_required'; end if;

  perform set_config('conceptspaces.audit_actor',actor_user_id::text,true);
  update core.invitations set status='revoked'
  where organisation_id=target_organisation_id and email=email_value and status='pending';
  select u.id,(u.email_confirmed_at is not null) into identity_id,identity_confirmed
  from auth.users u where lower(u.email)=email_value order by u.created_at limit 1;
  insert into core.invitations(organisation_id,email,role_codes,token_hash,status,invited_by,expires_at)
  values(target_organisation_id,email_value,array[role_value],
    encode(extensions.digest(concat_ws('|',target_organisation_id::text,email_value,role_value,
      gen_random_uuid()::text,clock_timestamp()::text),'sha256'),'hex'),
    case when identity_id is not null and identity_confirmed then 'accepted' else 'pending' end,
    actor_user_id,now()+interval '7 days') returning * into invitation;

  if identity_id is not null and identity_confirmed then
    insert into core.memberships(organisation_id,user_id,role_code,status)
    values(target_organisation_id,identity_id,role_value,'active')
    on conflict(organisation_id,user_id,role_code) do update set status='active';
    update core.invitations set accepted_by=identity_id,accepted_at=now() where id=invitation.id;
    identity_state:='existing_authorised';
  elsif identity_id is not null then identity_state:='existing_unconfirmed';
  end if;

  perform audit.append_event(target_organisation_id,null,'identity.invitation_created','workspace_invitation',
    invitation.id,null,jsonb_build_object(
      'email_hash',encode(extensions.digest(email_value,'sha256'),'hex'),'role_code',role_value,
      'status',case when identity_state='existing_authorised' then 'accepted' else 'pending' end),
    'Administrator-approved identity invitation',gen_random_uuid());
  return jsonb_build_object('invitation_id',invitation.id,'identity_state',identity_state,
    'expires_at',invitation.expires_at);
end;
$$;

revoke all on function public.service_invite_workspace_identity(uuid,uuid,text,text) from public,anon,authenticated;
grant execute on function public.service_invite_workspace_identity(uuid,uuid,text,text) to service_role;

create or replace function public.service_revoke_workspace_invitation(
  actor_user_id uuid,
  target_invitation_id uuid,
  target_reason text
)
returns boolean
language plpgsql
security definer
set search_path = core, audit, auth, pg_temp
as $$
declare invitation core.invitations%rowtype;
begin
  if auth.role()<>'service_role' or actor_user_id is null then raise exception 'service_role_required'; end if;
  select * into invitation from core.invitations where id=target_invitation_id for update;
  if not found then return false; end if;
  if not (exists(select 1 from core.memberships m where m.user_id=actor_user_id and m.status='active' and m.role_code='super_admin')
    or exists(select 1 from core.memberships m where m.user_id=actor_user_id
      and m.organisation_id=invitation.organisation_id and m.status='active' and m.role_code='org_admin')) then
    raise exception 'organisation_admin_required';
  end if;
  if invitation.status<>'pending' then return false; end if;
  perform set_config('conceptspaces.audit_actor',actor_user_id::text,true);
  update core.invitations set status='revoked' where id=invitation.id;
  perform audit.append_event(invitation.organisation_id,null,'identity.invitation_revoked','workspace_invitation',
    invitation.id,jsonb_build_object('status','pending'),jsonb_build_object('status','revoked'),
    coalesce(nullif(btrim(target_reason),''),'Invitation delivery failed'),gen_random_uuid());
  return true;
end;
$$;

revoke all on function public.service_revoke_workspace_invitation(uuid,uuid,text) from public,anon,authenticated;
grant execute on function public.service_revoke_workspace_invitation(uuid,uuid,text) to service_role;

create or replace function public.service_list_workspace_invitations(actor_user_id uuid,target_organisation_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = core, auth, pg_temp
as $$
begin
  if auth.role()<>'service_role' or actor_user_id is null then raise exception 'service_role_required'; end if;
  if not (exists(select 1 from core.memberships m where m.user_id=actor_user_id and m.status='active' and m.role_code='super_admin')
    or exists(select 1 from core.memberships m where m.user_id=actor_user_id
      and m.organisation_id=target_organisation_id and m.status='active' and m.role_code='org_admin')) then
    raise exception 'organisation_admin_required';
  end if;
  return coalesce((select jsonb_agg(jsonb_build_object(
    'id',i.id,'email',i.email::text,'role_codes',i.role_codes,'status',i.status,
    'expires_at',i.expires_at,'created_at',i.created_at) order by i.created_at desc)
    from (select * from core.invitations where organisation_id=target_organisation_id
      order by created_at desc limit 100) i),'[]'::jsonb);
end;
$$;

revoke all on function public.service_list_workspace_invitations(uuid,uuid) from public,anon,authenticated;
grant execute on function public.service_list_workspace_invitations(uuid,uuid) to service_role;

commit;
