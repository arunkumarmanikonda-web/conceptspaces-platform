begin;

alter table core.profiles add column if not exists email extensions.citext;
update core.profiles p set email = u.email from auth.users u where u.id = p.user_id and p.email is distinct from u.email;

create or replace function core.handle_auth_user_authority()
returns trigger
language plpgsql
security definer
set search_path = core, public, auth, extensions
as $$
declare
  bootstrap_org uuid;
begin
  insert into core.profiles(user_id, display_name, email)
  values (
    new.id,
    coalesce(new.raw_user_meta_data->>'full_name', split_part(coalesce(new.email,''),'@',1)),
    new.email
  )
  on conflict (user_id) do update
    set display_name = coalesce(core.profiles.display_name, excluded.display_name),
        email = excluded.email,
        updated_at = now();

  if new.email_confirmed_at is not null then
    perform pg_advisory_xact_lock(hashtext('concept_spaces_bootstrap_administrator'));
    if not exists (select 1 from core.memberships) then
      insert into core.organisations(name, code, settings)
      values ('Concept Spaces', 'CS-HQ', jsonb_build_object('bootstrap','first_confirmed_identity'))
      on conflict (code) do update set updated_at = now()
      returning id into bootstrap_org;
      if bootstrap_org is null then
        select id into bootstrap_org from core.organisations where code = 'CS-HQ' limit 1;
      end if;
      insert into core.memberships(organisation_id,user_id,role_code,status)
      values (bootstrap_org,new.id,'super_admin','active')
      on conflict (organisation_id,user_id,role_code) do update set status='active';
    end if;
  end if;
  return new;
end;
$$;

-- Directory visibility: self, platform admin, or an org admin sharing an organisation.
drop policy if exists profiles_admin_read on core.profiles;
create policy profiles_admin_read on core.profiles
for select to authenticated
using (
  core.is_platform_admin()
  or exists (
    select 1
    from core.memberships target_m
    join core.memberships admin_m on admin_m.organisation_id = target_m.organisation_id
    where target_m.user_id = core.profiles.user_id
      and target_m.status = 'active'
      and admin_m.user_id = (select auth.uid())
      and admin_m.status = 'active'
      and admin_m.role_code = 'org_admin'
  )
);

grant select on core.profiles to authenticated;

-- Workspace authority writes remain RLS-bound. Org admins can administer their
-- organisation but cannot manufacture platform administrators.
drop policy if exists memberships_admin_insert on core.memberships;
create policy memberships_admin_insert on core.memberships
for insert to authenticated
with check (
  core.is_platform_admin()
  or (
    core.has_org_role(organisation_id,array['org_admin'])
    and role_code <> 'super_admin'
  )
);

drop policy if exists memberships_admin_update on core.memberships;
create policy memberships_admin_update on core.memberships
for update to authenticated
using (
  core.is_platform_admin()
  or (
    core.has_org_role(organisation_id,array['org_admin'])
    and role_code <> 'super_admin'
  )
)
with check (
  core.is_platform_admin()
  or (
    core.has_org_role(organisation_id,array['org_admin'])
    and role_code <> 'super_admin'
  )
);

grant insert, update on core.memberships to authenticated;

-- Professional credentials are user-submitted but independently verified.
drop policy if exists credentials_self_insert on core.professional_credentials;
create policy credentials_self_insert on core.professional_credentials
for insert to authenticated
with check (
  user_id=(select auth.uid())
  and verification_status='pending'
  and verified_by is null
  and verified_at is null
);

drop policy if exists credentials_admin_read on core.professional_credentials;
create policy credentials_admin_read on core.professional_credentials
for select to authenticated
using (
  core.is_platform_admin()
  or exists (
    select 1 from core.memberships target_m
    join core.memberships admin_m on admin_m.organisation_id=target_m.organisation_id
    where target_m.user_id=core.professional_credentials.user_id
      and target_m.status='active'
      and admin_m.user_id=(select auth.uid())
      and admin_m.status='active'
      and admin_m.role_code='org_admin'
  )
);

drop policy if exists credentials_admin_update on core.professional_credentials;
create policy credentials_admin_update on core.professional_credentials
for update to authenticated
using (
  core.is_platform_admin()
  or exists (
    select 1 from core.memberships target_m
    join core.memberships admin_m on admin_m.organisation_id=target_m.organisation_id
    where target_m.user_id=core.professional_credentials.user_id
      and target_m.status='active'
      and admin_m.user_id=(select auth.uid())
      and admin_m.status='active'
      and admin_m.role_code='org_admin'
  )
)
with check (
  verification_status in ('pending','verified','rejected','expired')
);

grant select, insert, update on core.professional_credentials to authenticated;

create or replace function public.list_workspace_identities(target_organisation_id uuid default null)
returns table(
  user_id uuid,
  email text,
  display_name text,
  phone text,
  memberships jsonb,
  credentials jsonb
)
language sql
stable
security invoker
set search_path=core,public
as $$
  select p.user_id,
         p.email::text,
         p.display_name,
         p.phone,
         coalesce((
           select jsonb_agg(jsonb_build_object(
             'id',m.id,'organisation_id',m.organisation_id,'role_code',m.role_code,'status',m.status
           ) order by m.created_at)
           from core.memberships m
           where m.user_id=p.user_id
             and (target_organisation_id is null or m.organisation_id=target_organisation_id)
         ),'[]'::jsonb) as memberships,
         coalesce((
           select jsonb_agg(jsonb_build_object(
             'id',c.id,'credential_type',c.credential_type,'issuing_body',c.issuing_body,
             'registration_number',c.registration_number,'discipline',c.discipline,
             'valid_from',c.valid_from,'valid_until',c.valid_until,
             'verification_status',c.verification_status,'evidence_uri',c.evidence_uri
           ) order by c.created_at desc)
           from core.professional_credentials c where c.user_id=p.user_id
         ),'[]'::jsonb) as credentials
  from core.profiles p
  where
    core.is_platform_admin()
    or exists (
      select 1
      from core.memberships target_m
      join core.memberships admin_m on admin_m.organisation_id=target_m.organisation_id
      where target_m.user_id=p.user_id
        and target_m.status='active'
        and admin_m.user_id=auth.uid()
        and admin_m.status='active'
        and admin_m.role_code='org_admin'
        and (target_organisation_id is null or target_m.organisation_id=target_organisation_id)
    )
  order by lower(coalesce(p.display_name,p.email::text,p.user_id::text));
$$;

revoke all on function public.list_workspace_identities(uuid) from public,anon;
grant execute on function public.list_workspace_identities(uuid) to authenticated;

create or replace function public.assign_workspace_role(target_user_id uuid,target_organisation_id uuid,target_role_code text)
returns uuid
language plpgsql
security invoker
set search_path=core,public
as $$
declare
  role_code_normalised text := lower(btrim(target_role_code));
  membership_id uuid;
begin
  if auth.uid() is null then raise exception 'authentication_required'; end if;
  if role_code_normalised not in (
    'super_admin','org_admin','sales','project_manager','lead_architect','architect','interior_designer',
    'structural_engineer','mep_engineer','quantity_surveyor','contractor','finance','client','auditor','regulatory_reviewer'
  ) then raise exception 'unsupported_role'; end if;
  if role_code_normalised='super_admin' and not core.is_platform_admin() then raise exception 'platform_admin_required'; end if;
  if role_code_normalised<>'super_admin' and not (
    core.is_platform_admin() or core.has_org_role(target_organisation_id,array['org_admin'])
  ) then raise exception 'organisation_admin_required'; end if;
  if not exists(select 1 from core.profiles where user_id=target_user_id) then raise exception 'unknown_identity'; end if;

  insert into core.memberships(organisation_id,user_id,role_code,status)
  values(target_organisation_id,target_user_id,role_code_normalised,'active')
  on conflict (organisation_id,user_id,role_code)
  do update set status='active'
  returning id into membership_id;
  return membership_id;
end;
$$;

revoke all on function public.assign_workspace_role(uuid,uuid,text) from public,anon;
grant execute on function public.assign_workspace_role(uuid,uuid,text) to authenticated;

create or replace function public.set_workspace_membership_status(target_membership_id uuid,new_status text)
returns void
language plpgsql
security invoker
set search_path=core,public
as $$
declare
  m core.memberships%rowtype;
  active_super_admins integer;
begin
  if new_status not in ('active','suspended') then raise exception 'unsupported_membership_status'; end if;
  select * into m from core.memberships where id=target_membership_id;
  if not found then raise exception 'membership_not_found'; end if;
  if m.role_code='super_admin' and not core.is_platform_admin() then raise exception 'platform_admin_required'; end if;
  if m.role_code<>'super_admin' and not (core.is_platform_admin() or core.has_org_role(m.organisation_id,array['org_admin'])) then
    raise exception 'organisation_admin_required';
  end if;
  if m.role_code='super_admin' and m.status='active' and new_status='suspended' then
    perform pg_advisory_xact_lock(hashtext('concept_spaces_super_admin_floor'));
    select count(*) into active_super_admins from core.memberships where role_code='super_admin' and status='active';
    if active_super_admins <= 1 then raise exception 'cannot_suspend_last_super_admin'; end if;
  end if;
  update core.memberships set status=new_status where id=target_membership_id;
end;
$$;

revoke all on function public.set_workspace_membership_status(uuid,text) from public,anon;
grant execute on function public.set_workspace_membership_status(uuid,text) to authenticated;

create or replace function public.submit_professional_credential(input_payload jsonb)
returns uuid
language plpgsql
security invoker
set search_path=core,public
as $$
declare credential_id uuid;
begin
  if auth.uid() is null then raise exception 'authentication_required'; end if;
  if nullif(btrim(input_payload->>'credential_type'),'') is null
     or nullif(btrim(input_payload->>'issuing_body'),'') is null
     or nullif(btrim(input_payload->>'registration_number'),'') is null then
    raise exception 'credential_type_issuing_body_and_registration_required';
  end if;
  insert into core.professional_credentials(
    user_id,credential_type,issuing_body,registration_number,discipline,valid_from,valid_until,verification_status,evidence_uri
  ) values (
    auth.uid(),btrim(input_payload->>'credential_type'),btrim(input_payload->>'issuing_body'),btrim(input_payload->>'registration_number'),
    nullif(btrim(input_payload->>'discipline'),''),nullif(input_payload->>'valid_from','')::date,nullif(input_payload->>'valid_until','')::date,
    'pending',nullif(btrim(input_payload->>'evidence_uri'),'')
  ) returning id into credential_id;
  return credential_id;
end;
$$;

revoke all on function public.submit_professional_credential(jsonb) from public,anon;
grant execute on function public.submit_professional_credential(jsonb) to authenticated;

create or replace function public.review_professional_credential(target_credential_id uuid,decision text)
returns void
language plpgsql
security invoker
set search_path=core,public
as $$
declare c core.professional_credentials%rowtype;
begin
  if decision not in ('verified','rejected','expired') then raise exception 'unsupported_credential_decision'; end if;
  select * into c from core.professional_credentials where id=target_credential_id;
  if not found then raise exception 'credential_not_found'; end if;
  if not (
    core.is_platform_admin()
    or exists (
      select 1 from core.memberships target_m
      join core.memberships admin_m on admin_m.organisation_id=target_m.organisation_id
      where target_m.user_id=c.user_id and target_m.status='active'
        and admin_m.user_id=auth.uid() and admin_m.status='active' and admin_m.role_code='org_admin'
    )
  ) then raise exception 'credential_reviewer_authority_required'; end if;
  update core.professional_credentials
  set verification_status=decision,
      verified_by=case when decision='verified' then auth.uid() else null end,
      verified_at=case when decision='verified' then now() else null end
  where id=target_credential_id;
end;
$$;

revoke all on function public.review_professional_credential(uuid,text) from public,anon;
grant execute on function public.review_professional_credential(uuid,text) to authenticated;

comment on function public.assign_workspace_role(uuid,uuid,text) is 'Assigns workspace role under RLS. Org admins cannot grant super_admin.';
comment on function public.review_professional_credential(uuid,text) is 'Verifies credential evidence independently from workspace role. Verification does not itself grant project release authority.';

commit;
