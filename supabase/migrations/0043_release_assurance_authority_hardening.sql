begin;

-- Professional reviewers may hold project access without project-management authority.
-- All other release evidence mutation remains manager-controlled.
drop policy if exists release_evidence_governed_insert on governance.release_evidence;
create policy release_evidence_governed_insert on governance.release_evidence
for insert to authenticated with check (
  (
    ((select current_setting('conceptspaces.release_phase',true)) in ('create_case','add_evidence') and project.can_manage_project(project_id))
    or
    ((select current_setting('conceptspaces.release_phase',true))='professional_review' and project.can_access_project(project_id))
  )
  and safety_case_id is not null
  and package_content_hash is not null
  and produced_by=(select auth.uid())
);

create index if not exists release_safety_cases_created_by_idx on governance.release_safety_cases(created_by,created_at desc);
create index if not exists release_safety_cases_approved_by_idx on governance.release_safety_cases(approved_by,approved_at desc);
create index if not exists release_safety_cases_issued_by_idx on governance.release_safety_cases(issued_by,issued_at desc);
create index if not exists release_exceptions_gate_idx on governance.exceptions(gate_id,status,criticality);
create index if not exists release_exceptions_case_idx on governance.exceptions(safety_case_id,status,criticality);
create index if not exists release_package_reviews_project_idx on governance.release_package_reviews(project_id,reviewed_at desc);
create index if not exists release_package_reviews_credential_idx on governance.release_package_reviews(credential_id,reviewed_at desc);

commit;
