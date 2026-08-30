begin;

-- Project creation returns the new row so the intake transaction can continue.
-- During INSERT ... RETURNING, the stable project.can_access_project(id) lookup
-- cannot yet see that row. Keep the existing governed read rule and add the
-- equivalent creator/organisation check that can evaluate the proposed row.
drop policy if exists projects_read on project.projects;
create policy projects_read on project.projects
for select to authenticated
using (
  project.can_access_project(id)
  or (
    created_by = (select auth.uid())
    and core.has_org_role(
      organisation_id,
      array['super_admin','org_admin','sales','lead_architect','project_manager']
    )
  )
);

-- Keep the table policy aligned with submit_project_intake's explicit role
-- allow-list. RLS remains authoritative for every browser-originated insert.
drop policy if exists projects_insert on project.projects;
create policy projects_insert on project.projects
for insert to authenticated
with check (
  created_by = (select auth.uid())
  and core.has_org_role(
    organisation_id,
    array['super_admin','org_admin','sales','lead_architect','project_manager']
  )
);

commit;
