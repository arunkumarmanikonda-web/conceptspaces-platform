begin;

create index client_accounts_created_by_idx
  on public.client_accounts(created_by);
create index projects_org_client_account_idx
  on project.projects(organisation_id,client_account_id)
  where client_account_id is not null;

commit;
