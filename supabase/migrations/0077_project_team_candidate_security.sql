begin;

create schema if not exists private;
revoke all on schema private from public, anon;
grant usage on schema private to authenticated;

create or replace function private.list_project_team_candidates_internal(target_organisation_id uuid)
returns jsonb
language plpgsql
security definer
set search_path='public','project','core','auth','pg_temp'
as $$
begin
  if auth.uid() is null or not core.is_internal_org_member(target_organisation_id) then
    raise exception 'organisation_access_required';
  end if;
  return jsonb_build_object(
    'members',coalesce((
      select jsonb_agg(jsonb_build_object(
        'user_id',m.user_id,
        'email',u.email,
        'membership_role',m.role_code,
        'status',m.status
      ) order by lower(coalesce(u.email,'')),m.role_code)
      from core.memberships m
      join auth.users u on u.id=m.user_id
      where m.organisation_id=target_organisation_id and m.status='active'
    ),'[]'::jsonb),
    'project_members',coalesce((
      select jsonb_agg(jsonb_build_object(
        'id',pm.id,
        'project_id',pm.project_id,
        'user_id',pm.user_id,
        'role_code',pm.role_code,
        'discipline',pm.discipline,
        'status',pm.status,
        'email',u.email
      ) order by p.code,pm.role_code,lower(coalesce(u.email,'')))
      from project.project_members pm
      join project.projects p on p.id=pm.project_id
      join auth.users u on u.id=pm.user_id
      where p.organisation_id=target_organisation_id
    ),'[]'::jsonb)
  );
end;
$$;
revoke all on function private.list_project_team_candidates_internal(uuid) from public, anon;
grant execute on function private.list_project_team_candidates_internal(uuid) to authenticated;

create or replace function public.list_project_team_candidates(target_organisation_id uuid)
returns jsonb
language sql
security invoker
set search_path='public','private','core','auth','pg_temp'
as $$
  select private.list_project_team_candidates_internal(target_organisation_id);
$$;
revoke all on function public.list_project_team_candidates(uuid) from public, anon;
grant execute on function public.list_project_team_candidates(uuid) to authenticated;

commit;