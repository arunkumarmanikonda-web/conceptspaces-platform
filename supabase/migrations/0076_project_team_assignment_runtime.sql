begin;

-- Project team writes are allowed only for project managers/administrators under existing project authority.
grant insert, update, delete on project.project_members to authenticated;

drop policy if exists project_members_manage_insert on project.project_members;
create policy project_members_manage_insert on project.project_members
for insert to authenticated
with check (
  project.can_manage_project(project_id)
  and exists (
    select 1
    from project.projects p
    join core.memberships m on m.organisation_id=p.organisation_id
    where p.id=project_id
      and m.user_id=project_members.user_id
      and m.status='active'
  )
);

drop policy if exists project_members_manage_update on project.project_members;
create policy project_members_manage_update on project.project_members
for update to authenticated
using (project.can_manage_project(project_id))
with check (
  project.can_manage_project(project_id)
  and exists (
    select 1
    from project.projects p
    join core.memberships m on m.organisation_id=p.organisation_id
    where p.id=project_id
      and m.user_id=project_members.user_id
      and m.status='active'
  )
);

drop policy if exists project_members_manage_delete on project.project_members;
create policy project_members_manage_delete on project.project_members
for delete to authenticated
using (project.can_manage_project(project_id));

create or replace function public.list_project_team_candidates(target_organisation_id uuid)
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
revoke all on function public.list_project_team_candidates(uuid) from public;
grant execute on function public.list_project_team_candidates(uuid) to authenticated;

create or replace function public.assign_project_member(
  target_project_id uuid,
  target_user_id uuid,
  target_role_code text,
  target_discipline text default null,
  target_reason text default null
)
returns uuid
language plpgsql
security invoker
set search_path='public','project','core','audit','auth','pg_temp'
as $$
declare
  p project.projects%rowtype;
  member project.project_members%rowtype;
  role_value text:=lower(btrim(target_role_code));
  before_state jsonb;
begin
  select * into p from project.projects where id=target_project_id for update;
  if not found or auth.uid() is null or not project.can_manage_project(p.id) then
    raise exception 'project_team_authority_required';
  end if;
  if role_value not in (
    'lead_architect','design_architect','project_architect','bim_manager','interior_designer',
    'structural_engineer','mep_lead','hvac_engineer','electrical_engineer','plumbing_engineer',
    'fire_specialist','sustainability_consultant','qs_cost_manager','procurement_manager',
    'project_manager','site_engineer','quality_manager','contractor','vendor','client','client_user',
    'client_reviewer','client_approver','client_admin','auditor'
  ) then raise exception 'project_role_invalid'; end if;
  if not exists(select 1 from core.memberships m where m.organisation_id=p.organisation_id and m.user_id=target_user_id and m.status='active') then
    raise exception 'target_user_not_active_org_member';
  end if;

  select to_jsonb(pm) into before_state
  from project.project_members pm
  where pm.project_id=p.id and pm.user_id=target_user_id and pm.role_code=role_value;

  insert into project.project_members(project_id,user_id,role_code,discipline,status)
  values(p.id,target_user_id,role_value,nullif(btrim(target_discipline),''),'active')
  on conflict(project_id,user_id,role_code) do update
    set discipline=excluded.discipline,status='active'
  returning * into member;

  if role_value='lead_architect' then
    update project.projects set lead_architect_user_id=target_user_id,updated_at=now() where id=p.id;
  end if;

  perform audit.append_event(
    p.organisation_id,p.id,'project.member.assigned','project_member',member.id,
    before_state,to_jsonb(member),coalesce(nullif(btrim(target_reason),''),'Project team assignment'),gen_random_uuid()
  );
  return member.id;
end;
$$;
revoke all on function public.assign_project_member(uuid,uuid,text,text,text) from public;
grant execute on function public.assign_project_member(uuid,uuid,text,text,text) to authenticated;

create or replace function public.remove_project_member(target_project_member_id uuid,target_reason text)
returns text
language plpgsql
security invoker
set search_path='public','project','audit','auth','pg_temp'
as $$
declare
  member project.project_members%rowtype;
  p project.projects%rowtype;
  before_state jsonb;
begin
  select * into member from project.project_members where id=target_project_member_id for update;
  if not found then raise exception 'project_member_not_found'; end if;
  select * into p from project.projects where id=member.project_id for update;
  if auth.uid() is null or not project.can_manage_project(p.id) then raise exception 'project_team_authority_required'; end if;
  if nullif(btrim(target_reason),'') is null then raise exception 'project_member_removal_reason_required'; end if;
  before_state:=to_jsonb(member);
  update project.project_members set status='inactive' where id=member.id returning * into member;
  if member.role_code='lead_architect' and p.lead_architect_user_id=member.user_id then
    update project.projects set lead_architect_user_id=null,updated_at=now() where id=p.id;
  end if;
  perform audit.append_event(p.organisation_id,p.id,'project.member.removed','project_member',member.id,before_state,to_jsonb(member),target_reason,gen_random_uuid());
  return member.status;
end;
$$;
revoke all on function public.remove_project_member(uuid,text) from public;
grant execute on function public.remove_project_member(uuid,text) to authenticated;

create or replace function public.set_project_data_classification(target_project_id uuid,target_classification text,target_reason text)
returns text
language plpgsql
security invoker
set search_path='public','project','audit','auth','pg_temp'
as $$
declare p project.projects%rowtype; before_state jsonb; value text:=lower(btrim(target_classification));
begin
  select * into p from project.projects where id=target_project_id for update;
  if not found or auth.uid() is null or not project.can_manage_project(p.id) then raise exception 'project_classification_authority_required'; end if;
  if value not in ('public','internal','confidential','restricted') then raise exception 'project_classification_invalid'; end if;
  if nullif(btrim(target_reason),'') is null then raise exception 'project_classification_reason_required'; end if;
  before_state:=to_jsonb(p);
  update project.projects set data_classification=value,updated_at=now() where id=p.id returning * into p;
  perform audit.append_event(p.organisation_id,p.id,'project.classification.changed','project',p.id,before_state,to_jsonb(p),target_reason,gen_random_uuid());
  return p.data_classification;
end;
$$;
revoke all on function public.set_project_data_classification(uuid,text,text) from public;
grant execute on function public.set_project_data_classification(uuid,text,text) to authenticated;

commit;