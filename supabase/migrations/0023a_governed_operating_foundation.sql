begin;

alter table public.proposals add column if not exists created_by uuid references auth.users(id);
alter table public.proposals add column if not exists submitted_at timestamptz;
alter table public.contracts add column if not exists created_by uuid references auth.users(id);
alter table public.invoices add column if not exists created_by uuid references auth.users(id);

create or replace function audit.append_event(
  target_organisation_id uuid,
  target_project_id uuid,
  target_action text,
  target_resource_type text,
  target_resource_id uuid,
  target_before_state jsonb default null,
  target_after_state jsonb default null,
  target_reason text default null,
  target_correlation_id uuid default gen_random_uuid()
)
returns uuid
language plpgsql
security definer
set search_path = audit, public, extensions
as $$
declare
  previous text;
  event_id uuid := gen_random_uuid();
  event_time timestamptz := clock_timestamp();
  payload text;
  computed text;
begin
  if target_organisation_id is null then raise exception 'audit_organisation_required'; end if;
  if nullif(btrim(target_action),'') is null then raise exception 'audit_action_required'; end if;
  if nullif(btrim(target_resource_type),'') is null then raise exception 'audit_resource_type_required'; end if;

  perform pg_advisory_xact_lock(hashtext('concept_spaces_audit_' || target_organisation_id::text));
  select event_hash into previous
  from audit.events
  where organisation_id = target_organisation_id
  order by created_at desc, id desc
  limit 1;

  payload := concat_ws('|',
    coalesce(previous,''), event_id::text, target_organisation_id::text,
    coalesce(target_project_id::text,''), coalesce(auth.uid()::text,''),
    target_action, target_resource_type, coalesce(target_resource_id::text,''),
    coalesce(target_before_state::text,''), coalesce(target_after_state::text,''),
    coalesce(target_reason,''), target_correlation_id::text, event_time::text
  );
  computed := encode(extensions.digest(payload,'sha256'),'hex');

  insert into audit.events(
    id, organisation_id, project_id, actor_id, actor_type, action, resource_type,
    resource_id, before_state, after_state, reason, correlation_id, previous_hash,
    event_hash, created_at
  ) values (
    event_id, target_organisation_id, target_project_id, auth.uid(),
    case when auth.uid() is null then 'system' else 'human' end,
    target_action, target_resource_type, target_resource_id, target_before_state,
    target_after_state, target_reason, target_correlation_id, previous, computed,
    event_time
  );
  return event_id;
end;
$$;

revoke all on function audit.append_event(uuid,uuid,text,text,uuid,jsonb,jsonb,text,uuid) from public, anon;
grant execute on function audit.append_event(uuid,uuid,text,text,uuid,jsonb,jsonb,text,uuid) to authenticated, service_role;

create or replace function core.has_verified_professional_eligibility(target_user uuid, target_role text)
returns boolean
language sql
stable
security definer
set search_path = core, public
as $$
  select exists (
    select 1
    from core.professional_credentials c
    where c.user_id = target_user
      and c.verification_status = 'verified'
      and (c.valid_from is null or c.valid_from <= current_date)
      and (c.valid_until is null or c.valid_until >= current_date)
      and (
        (target_role in ('architect','lead_architect') and (lower(coalesce(c.discipline,'')) like '%arch%' or lower(c.credential_type) like '%architect%'))
        or (target_role = 'structural_engineer' and (lower(coalesce(c.discipline,'')) like '%struct%' or lower(c.credential_type) like '%struct%'))
        or (target_role = 'mep_engineer' and (lower(coalesce(c.discipline,'')) like '%mep%' or lower(c.credential_type) like '%mep%'))
        or (target_role = 'quantity_surveyor' and (lower(coalesce(c.discipline,'')) like '%quant%' or lower(c.credential_type) like '%quantity%'))
        or (target_role = 'regulatory_reviewer' and (lower(coalesce(c.discipline,'')) like '%regulat%' or lower(c.credential_type) like '%regulat%'))
      )
  );
$$;
revoke all on function core.has_verified_professional_eligibility(uuid,text) from public, anon;
grant execute on function core.has_verified_professional_eligibility(uuid,text) to authenticated;

grant usage on schema operations, coordination, audit to authenticated;
grant select, insert, update on public.contacts, public.leads, public.opportunities,
  public.proposals, public.proposal_lines, public.contracts, public.contract_obligations,
  public.invoices, public.invoice_lines to authenticated;
grant select, insert, update on operations.tasks to authenticated;
grant select, insert, update on coordination.issues, coordination.issue_comments,
  coordination.approval_requests to authenticated;

drop policy if exists contacts_operate on public.contacts;
create policy contacts_operate on public.contacts for all to authenticated
using (core.has_org_role(organisation_id,array['super_admin','org_admin','sales','project_manager']))
with check (core.has_org_role(organisation_id,array['super_admin','org_admin','sales','project_manager']));

drop policy if exists leads_operate on public.leads;
create policy leads_operate on public.leads for all to authenticated
using (core.has_org_role(organisation_id,array['super_admin','org_admin','sales','project_manager']))
with check (core.has_org_role(organisation_id,array['super_admin','org_admin','sales','project_manager']));

drop policy if exists opportunities_operate on public.opportunities;
create policy opportunities_operate on public.opportunities for all to authenticated
using (core.has_org_role(organisation_id,array['super_admin','org_admin','sales','project_manager']))
with check (core.has_org_role(organisation_id,array['super_admin','org_admin','sales','project_manager']));

drop policy if exists proposals_operate on public.proposals;
create policy proposals_operate on public.proposals for all to authenticated
using (core.has_org_role(organisation_id,array['super_admin','org_admin','sales','finance']))
with check (core.has_org_role(organisation_id,array['super_admin','org_admin','sales','finance']));

drop policy if exists proposal_lines_operate on public.proposal_lines;
create policy proposal_lines_operate on public.proposal_lines for all to authenticated
using (
  exists (
    select 1 from public.proposals p
    where p.id = proposal_id
      and core.has_org_role(p.organisation_id,array['super_admin','org_admin','sales','finance'])
  )
)
with check (
  exists (
    select 1 from public.proposals p
    where p.id = proposal_id
      and core.has_org_role(p.organisation_id,array['super_admin','org_admin','sales','finance'])
      and p.status in ('draft','internal_review')
  )
);

drop policy if exists contracts_operate on public.contracts;
create policy contracts_operate on public.contracts for all to authenticated
using (core.has_org_role(organisation_id,array['super_admin','org_admin','finance']))
with check (core.has_org_role(organisation_id,array['super_admin','org_admin','finance']));

drop policy if exists contract_obligations_operate on public.contract_obligations;
create policy contract_obligations_operate on public.contract_obligations for all to authenticated
using (
  exists (
    select 1 from public.contracts c
    where c.id = contract_id
      and core.has_org_role(c.organisation_id,array['super_admin','org_admin','finance','project_manager'])
  )
)
with check (
  exists (
    select 1 from public.contracts c
    where c.id = contract_id
      and core.has_org_role(c.organisation_id,array['super_admin','org_admin','finance','project_manager'])
  )
);

drop policy if exists invoices_operate on public.invoices;
create policy invoices_operate on public.invoices for all to authenticated
using (core.has_org_role(organisation_id,array['super_admin','org_admin','finance']))
with check (core.has_org_role(organisation_id,array['super_admin','org_admin','finance']));

drop policy if exists invoice_lines_operate on public.invoice_lines;
create policy invoice_lines_operate on public.invoice_lines for all to authenticated
using (
  exists (
    select 1 from public.invoices i
    where i.id = invoice_id
      and core.has_org_role(i.organisation_id,array['super_admin','org_admin','finance'])
  )
)
with check (
  exists (
    select 1 from public.invoices i
    where i.id = invoice_id
      and core.has_org_role(i.organisation_id,array['super_admin','org_admin','finance'])
      and i.status = 'draft'
  )
);

drop policy if exists tasks_operate on operations.tasks;
create policy tasks_operate on operations.tasks for all to authenticated
using (
  ((project_id is not null) and project.can_access_project(project_id))
  or ((project_id is null) and core.is_internal_org_member(organisation_id))
)
with check (
  ((project_id is not null) and project.can_access_project(project_id))
  or ((project_id is null) and core.is_internal_org_member(organisation_id))
);

drop policy if exists issues_operate on coordination.issues;
create policy issues_operate on coordination.issues for all to authenticated
using (project.can_access_project(project_id))
with check (project.can_access_project(project_id));

drop policy if exists issue_comments_operate on coordination.issue_comments;
create policy issue_comments_operate on coordination.issue_comments for all to authenticated
using (
  exists (select 1 from coordination.issues i where i.id = issue_id and project.can_access_project(i.project_id))
)
with check (
  exists (select 1 from coordination.issues i where i.id = issue_id and project.can_access_project(i.project_id))
);

drop policy if exists approvals_operate on coordination.approval_requests;
create policy approvals_operate on coordination.approval_requests for all to authenticated
using (project.can_access_project(project_id))
with check (project.can_access_project(project_id));

commit;
