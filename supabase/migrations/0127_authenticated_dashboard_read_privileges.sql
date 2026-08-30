begin;

-- The authenticated command-centre RPCs run as SECURITY INVOKER. RLS decides
-- which rows are visible, while these table grants provide only the read
-- privileges required to reach those policies.
grant select on core.organisations to authenticated;
grant select on operations.risks to authenticated;

drop policy if exists risks_governed_read on operations.risks;
create policy risks_governed_read on operations.risks
for select to authenticated
using (
  (project_id is not null and project.can_access_project(project_id))
  or (project_id is null and core.is_internal_org_member(organisation_id))
);

commit;
