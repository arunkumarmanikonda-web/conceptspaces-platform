begin;

alter function public.generate_preliminary_layout_set(uuid)
  rename to generate_preliminary_layout_set_core;

create or replace function public.generate_preliminary_layout_set(target_project_id uuid)
returns uuid
language plpgsql
security definer
set search_path='public','project','aec','auth','pg_temp'
as $$
begin
  if auth.uid() is null or not project.can_access_project(target_project_id) then
    raise exception 'project_access_required';
  end if;

  insert into aec.design_branches(project_id,code,title,branch_reason,status,created_by)
  values(target_project_id,'main','Main','Architecture bridge for the governed compiler main branch','active',auth.uid())
  on conflict(project_id,code) do nothing;

  return public.generate_preliminary_layout_set_core(target_project_id);
end;
$$;

revoke all on function public.generate_preliminary_layout_set(uuid) from public,anon;
grant execute on function public.generate_preliminary_layout_set(uuid) to authenticated;

commit;
