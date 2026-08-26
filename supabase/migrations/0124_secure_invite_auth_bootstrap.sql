begin;

-- Public identities must never acquire platform authority merely by being first.
-- Initial and subsequent memberships are provisioned deliberately by a database
-- administrator or an already-authorised organisation administrator.
create or replace function core.handle_auth_user_authority()
returns trigger
language plpgsql
security definer
set search_path = core, public, auth, extensions
as $$
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

  return new;
end;
$$;

revoke all on function core.handle_auth_user_authority() from public, anon, authenticated;

comment on function core.handle_auth_user_authority() is
'Synchronises the private identity profile only. Platform and organisation authority is always provisioned explicitly; first-user bootstrap is forbidden.';

commit;
