begin;

grant select on project.truth_records to authenticated;
create or replace function public.list_project_truth_state(target_project_id uuid)
returns table(id uuid,kind text,record_key text,value jsonb,unit text,source_type text,source_reference text,confidence text,status text,criticality text,verified_by uuid,verified_at timestamptz,created_at timestamptz)
language sql stable security invoker set search_path=project,public,auth,pg_temp
as $$
  select t.id,t.kind,t.record_key,t.value,t.unit,t.source_type,t.source_reference,t.confidence,t.status,t.criticality,t.verified_by,t.verified_at,t.created_at
  from project.truth_records t
  where t.project_id=target_project_id and t.valid_until is null and project.can_access_project(target_project_id)
  order by t.record_key,t.created_at desc;
$$;
revoke all on function public.list_project_truth_state(uuid) from public,anon;
grant execute on function public.list_project_truth_state(uuid) to authenticated;

commit;
