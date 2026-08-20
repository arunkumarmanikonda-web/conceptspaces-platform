begin;

-- Restore the narrow execute permission required by authenticated SECURITY INVOKER
-- operating RPCs. The helper itself remains in the non-exposed audit schema and
-- validates all writes through the calling RPC's organisation/project authority.
grant execute on function audit.append_event(uuid,uuid,text,text,uuid,jsonb,jsonb,text,uuid) to authenticated;

-- Cover actor foreign keys introduced by governed operating mutations.
create index if not exists proposals_created_by_idx on public.proposals(created_by) where created_by is not null;
create index if not exists contracts_created_by_idx on public.contracts(created_by) where created_by is not null;
create index if not exists invoices_created_by_idx on public.invoices(created_by) where created_by is not null;
create index if not exists invoices_issued_by_idx on public.invoices(issued_by) where issued_by is not null;

-- Keep the existing cs_read SELECT policies. Split write authority from the old
-- FOR ALL policies so each SELECT is evaluated once rather than through two
-- permissive policies.
drop policy if exists contacts_operate on public.contacts;
create policy contacts_operate_insert on public.contacts for insert to authenticated
with check (core.has_org_role(organisation_id,array['super_admin','org_admin','sales','project_manager']));
create policy contacts_operate_update on public.contacts for update to authenticated
using (core.has_org_role(organisation_id,array['super_admin','org_admin','sales','project_manager']))
with check (core.has_org_role(organisation_id,array['super_admin','org_admin','sales','project_manager']));

drop policy if exists leads_operate on public.leads;
create policy leads_operate_insert on public.leads for insert to authenticated
with check (core.has_org_role(organisation_id,array['super_admin','org_admin','sales','project_manager']));
create policy leads_operate_update on public.leads for update to authenticated
using (core.has_org_role(organisation_id,array['super_admin','org_admin','sales','project_manager']))
with check (core.has_org_role(organisation_id,array['super_admin','org_admin','sales','project_manager']));

drop policy if exists opportunities_operate on public.opportunities;
create policy opportunities_operate_insert on public.opportunities for insert to authenticated
with check (core.has_org_role(organisation_id,array['super_admin','org_admin','sales','project_manager']));
create policy opportunities_operate_update on public.opportunities for update to authenticated
using (core.has_org_role(organisation_id,array['super_admin','org_admin','sales','project_manager']))
with check (core.has_org_role(organisation_id,array['super_admin','org_admin','sales','project_manager']));

drop policy if exists proposals_operate on public.proposals;
create policy proposals_operate_insert on public.proposals for insert to authenticated
with check (core.has_org_role(organisation_id,array['super_admin','org_admin','sales','finance']));
create policy proposals_operate_update on public.proposals for update to authenticated
using (core.has_org_role(organisation_id,array['super_admin','org_admin','sales','finance']))
with check (core.has_org_role(organisation_id,array['super_admin','org_admin','sales','finance']));

drop policy if exists proposal_lines_operate on public.proposal_lines;
create policy proposal_lines_operate_insert on public.proposal_lines for insert to authenticated
with check (exists(select 1 from public.proposals p where p.id=proposal_id and core.has_org_role(p.organisation_id,array['super_admin','org_admin','sales','finance']) and p.status in ('draft','internal_review')));
create policy proposal_lines_operate_update on public.proposal_lines for update to authenticated
using (exists(select 1 from public.proposals p where p.id=proposal_id and core.has_org_role(p.organisation_id,array['super_admin','org_admin','sales','finance'])))
with check (exists(select 1 from public.proposals p where p.id=proposal_id and core.has_org_role(p.organisation_id,array['super_admin','org_admin','sales','finance']) and p.status in ('draft','internal_review')));

drop policy if exists contracts_operate on public.contracts;
create policy contracts_operate_insert on public.contracts for insert to authenticated
with check (core.has_org_role(organisation_id,array['super_admin','org_admin','finance']));
create policy contracts_operate_update on public.contracts for update to authenticated
using (core.has_org_role(organisation_id,array['super_admin','org_admin','finance']))
with check (core.has_org_role(organisation_id,array['super_admin','org_admin','finance']));

drop policy if exists contract_obligations_operate on public.contract_obligations;
create policy contract_obligations_operate_insert on public.contract_obligations for insert to authenticated
with check (exists(select 1 from public.contracts c where c.id=contract_id and core.has_org_role(c.organisation_id,array['super_admin','org_admin','finance','project_manager'])));
create policy contract_obligations_operate_update on public.contract_obligations for update to authenticated
using (exists(select 1 from public.contracts c where c.id=contract_id and core.has_org_role(c.organisation_id,array['super_admin','org_admin','finance','project_manager'])))
with check (exists(select 1 from public.contracts c where c.id=contract_id and core.has_org_role(c.organisation_id,array['super_admin','org_admin','finance','project_manager'])));

drop policy if exists invoices_operate on public.invoices;
create policy invoices_operate_insert on public.invoices for insert to authenticated
with check (core.has_org_role(organisation_id,array['super_admin','org_admin','finance']));
create policy invoices_operate_update on public.invoices for update to authenticated
using (core.has_org_role(organisation_id,array['super_admin','org_admin','finance']))
with check (core.has_org_role(organisation_id,array['super_admin','org_admin','finance']));

drop policy if exists invoice_lines_operate on public.invoice_lines;
create policy invoice_lines_operate_insert on public.invoice_lines for insert to authenticated
with check (exists(select 1 from public.invoices i where i.id=invoice_id and core.has_org_role(i.organisation_id,array['super_admin','org_admin','finance']) and i.status='draft'));
create policy invoice_lines_operate_update on public.invoice_lines for update to authenticated
using (exists(select 1 from public.invoices i where i.id=invoice_id and core.has_org_role(i.organisation_id,array['super_admin','org_admin','finance'])))
with check (exists(select 1 from public.invoices i where i.id=invoice_id and core.has_org_role(i.organisation_id,array['super_admin','org_admin','finance']) and i.status='draft'));

drop policy if exists tasks_operate on operations.tasks;
create policy tasks_operate_insert on operations.tasks for insert to authenticated
with check (((project_id is not null) and project.can_access_project(project_id)) or ((project_id is null) and core.is_internal_org_member(organisation_id)));
create policy tasks_operate_update on operations.tasks for update to authenticated
using (((project_id is not null) and project.can_access_project(project_id)) or ((project_id is null) and core.is_internal_org_member(organisation_id)))
with check (((project_id is not null) and project.can_access_project(project_id)) or ((project_id is null) and core.is_internal_org_member(organisation_id)));

drop policy if exists issues_operate on coordination.issues;
create policy issues_operate_insert on coordination.issues for insert to authenticated
with check (project.can_access_project(project_id));
create policy issues_operate_update on coordination.issues for update to authenticated
using (project.can_access_project(project_id)) with check (project.can_access_project(project_id));

drop policy if exists issue_comments_operate on coordination.issue_comments;
create policy issue_comments_operate_insert on coordination.issue_comments for insert to authenticated
with check (exists(select 1 from coordination.issues i where i.id=issue_id and project.can_access_project(i.project_id)));
create policy issue_comments_operate_update on coordination.issue_comments for update to authenticated
using (exists(select 1 from coordination.issues i where i.id=issue_id and project.can_access_project(i.project_id)))
with check (exists(select 1 from coordination.issues i where i.id=issue_id and project.can_access_project(i.project_id)));

drop policy if exists approvals_operate on coordination.approval_requests;
create policy approvals_operate_insert on coordination.approval_requests for insert to authenticated
with check (project.can_access_project(project_id));
create policy approvals_operate_update on coordination.approval_requests for update to authenticated
using (project.can_access_project(project_id)) with check (project.can_access_project(project_id));

-- Consolidate self and admin directory reads into one policy each.
drop policy if exists profiles_self_read on core.profiles;
drop policy if exists profiles_admin_read on core.profiles;
create policy profiles_authorised_read on core.profiles for select to authenticated
using (
  user_id=(select auth.uid()) or core.is_platform_admin() or exists(
    select 1 from core.memberships target_m
    join core.memberships admin_m on admin_m.organisation_id=target_m.organisation_id
    where target_m.user_id=core.profiles.user_id and target_m.status='active'
      and admin_m.user_id=(select auth.uid()) and admin_m.status='active' and admin_m.role_code='org_admin'
  )
);

drop policy if exists credentials_self_read on core.professional_credentials;
drop policy if exists credentials_admin_read on core.professional_credentials;
create policy credentials_authorised_read on core.professional_credentials for select to authenticated
using (
  user_id=(select auth.uid()) or core.is_platform_admin() or exists(
    select 1 from core.memberships target_m
    join core.memberships admin_m on admin_m.organisation_id=target_m.organisation_id
    where target_m.user_id=core.professional_credentials.user_id and target_m.status='active'
      and admin_m.user_id=(select auth.uid()) and admin_m.status='active' and admin_m.role_code='org_admin'
  )
);

commit;
