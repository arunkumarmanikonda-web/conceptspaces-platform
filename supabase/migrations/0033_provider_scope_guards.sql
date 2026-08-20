begin;

create or replace function integration.guard_outbound_message_scope()
returns trigger
language plpgsql
security definer
set search_path=integration,project,pg_temp
as $$
begin
  if new.project_id is not null and not exists(select 1 from project.projects p where p.id=new.project_id and p.organisation_id=new.organisation_id) then
    raise exception 'outbound_message_project_organisation_mismatch';
  end if;
  return new;
end;
$$;
drop trigger if exists concept_spaces_outbound_scope_guard on integration.outbound_messages;
create trigger concept_spaces_outbound_scope_guard before insert or update of organisation_id,project_id on integration.outbound_messages for each row execute function integration.guard_outbound_message_scope();

create or replace function public.list_accessible_projects_for_org(target_organisation_id uuid)
returns table(id uuid,code text,name text,typology text,stage text,criticality text,status text)
language sql stable security invoker
set search_path=project,core,public,auth,pg_temp
as $$
  select p.id,p.code::text,p.name,p.typology,p.stage,p.criticality,p.status from project.projects p
  where p.organisation_id=target_organisation_id and core.is_org_member(target_organisation_id) and project.can_access_project(p.id)
  order by p.created_at desc;
$$;
revoke all on function public.list_accessible_projects_for_org(uuid) from public,anon;
grant execute on function public.list_accessible_projects_for_org(uuid) to authenticated;

commit;