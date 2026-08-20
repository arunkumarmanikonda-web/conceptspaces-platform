begin;

create schema if not exists extensions;
alter extension citext set schema extensions;

create or replace function core.is_org_member(target_org uuid)
returns boolean
language sql
stable
security definer
set search_path = core, public
as $$
  select exists (
    select 1
    from core.memberships m
    where m.organisation_id = target_org
      and m.user_id = (select auth.uid())
      and m.status = 'active'
  );
$$;

create or replace function core.has_org_role(target_org uuid, allowed_roles text[])
returns boolean
language sql
stable
security definer
set search_path = core, public
as $$
  select exists (
    select 1
    from core.memberships m
    where m.organisation_id = target_org
      and m.user_id = (select auth.uid())
      and m.status = 'active'
      and m.role_code = any(allowed_roles)
  );
$$;

create or replace function core.is_internal_org_member(target_org uuid)
returns boolean
language sql
stable
security definer
set search_path = core, public
as $$
  select exists (
    select 1
    from core.memberships m
    where m.organisation_id = target_org
      and m.user_id = (select auth.uid())
      and m.status = 'active'
      and m.role_code <> 'client'
  );
$$;

create or replace function core.is_platform_admin()
returns boolean
language sql
stable
security definer
set search_path = core, public
as $$
  select exists (
    select 1
    from core.memberships m
    where m.user_id = (select auth.uid())
      and m.status = 'active'
      and m.role_code = 'super_admin'
  );
$$;

create or replace function project.can_access_project(target_project uuid)
returns boolean
language sql
stable
security definer
set search_path = core, project, public
as $$
  select exists (
    select 1
    from project.projects p
    where p.id = target_project
      and (
        core.has_org_role(p.organisation_id, array['super_admin','org_admin'])
        or p.lead_architect_user_id = (select auth.uid())
        or p.created_by = (select auth.uid())
        or exists (
          select 1
          from project.project_members pm
          where pm.project_id = p.id
            and pm.user_id = (select auth.uid())
            and pm.status = 'active'
        )
      )
  );
$$;

create or replace function project.can_manage_project(target_project uuid)
returns boolean
language sql
stable
security definer
set search_path = core, project, public
as $$
  select exists (
    select 1
    from project.projects p
    where p.id = target_project
      and (
        core.has_org_role(p.organisation_id, array['super_admin','org_admin'])
        or p.lead_architect_user_id = (select auth.uid())
        or exists (
          select 1 from project.project_members pm
          where pm.project_id = p.id
            and pm.user_id = (select auth.uid())
            and pm.status = 'active'
            and pm.role_code in ('lead_architect','project_manager')
        )
      )
  );
$$;

-- Tighten foundation policies that were intentionally permissive during scaffolding.
drop policy if exists profiles_self on core.profiles;
create policy profiles_self_read on core.profiles for select to authenticated
  using (user_id = (select auth.uid()));
create policy profiles_self_insert on core.profiles for insert to authenticated
  with check (user_id = (select auth.uid()));
create policy profiles_self_update on core.profiles for update to authenticated
  using (user_id = (select auth.uid())) with check (user_id = (select auth.uid()));

drop policy if exists credentials_self_read on core.professional_credentials;
create policy credentials_self_read on core.professional_credentials for select to authenticated
  using (user_id = (select auth.uid()));

drop policy if exists memberships_read on core.memberships;
create policy memberships_self_or_admin_read on core.memberships for select to authenticated
  using (
    user_id = (select auth.uid())
    or core.has_org_role(organisation_id, array['super_admin','org_admin'])
  );

drop policy if exists projects_org_access on project.projects;
create policy projects_read on project.projects for select to authenticated
  using (project.can_access_project(id));
create policy projects_insert on project.projects for insert to authenticated
  with check (core.has_org_role(organisation_id, array['super_admin','org_admin','sales','lead_architect']));
create policy projects_update on project.projects for update to authenticated
  using (project.can_manage_project(id))
  with check (core.is_internal_org_member(organisation_id));

-- Establish an explicit SELECT policy on every remaining RLS table. Project-scoped
-- rows are visible only through project membership/authority. Organisation-scoped
-- rows are restricted to internal organisation members. Everything else defaults
-- to platform-admin-only until a narrower product rule is defined.
do $$
declare
  r record;
  has_project boolean;
  has_org boolean;
  predicate text;
begin
  for r in
    select n.nspname as schema_name, c.relname as table_name, c.oid
    from pg_class c
    join pg_namespace n on n.oid = c.relnamespace
    where c.relkind = 'r'
      and c.relrowsecurity
      and n.nspname not in ('pg_catalog','information_schema','auth','storage','realtime','vault','extensions','supabase_migrations')
      and not exists (select 1 from pg_policy p where p.polrelid = c.oid)
  loop
    select exists (
      select 1 from pg_attribute a
      where a.attrelid = r.oid and a.attname = 'project_id' and not a.attisdropped
    ) into has_project;
    select exists (
      select 1 from pg_attribute a
      where a.attrelid = r.oid and a.attname = 'organisation_id' and not a.attisdropped
    ) into has_org;

    if has_project and has_org then
      predicate := '(project_id is not null and project.can_access_project(project_id)) or (project_id is null and core.is_internal_org_member(organisation_id))';
    elsif has_project then
      predicate := 'project.can_access_project(project_id)';
    elsif has_org then
      predicate := 'core.is_internal_org_member(organisation_id)';
    else
      predicate := 'core.is_platform_admin()';
    end if;

    execute format('create policy cs_read on %I.%I for select to authenticated using (%s)', r.schema_name, r.table_name, predicate);
  end loop;
end $$;

-- Public/reference catalogues that are intentionally safe for authenticated users.
drop policy if exists cs_read on engagement.scope_catalogue;
create policy cs_read on engagement.scope_catalogue for select to authenticated using (active);

drop policy if exists cs_read on feasibility.typology_packs;
create policy cs_read on feasibility.typology_packs for select to authenticated using (state = 'published');

drop policy if exists cs_read on regula.packs;
create policy cs_read on regula.packs for select to authenticated using (publication_status = 'published');

drop policy if exists cs_read on regula.rules;
create policy cs_read on regula.rules for select to authenticated
  using (exists (select 1 from regula.packs p where p.id = pack_id and p.publication_status = 'published'));

-- Sensitive control-plane data remains admin-only even when it carries organisation ids.
drop policy if exists cs_read on public.api_credentials;
create policy cs_read on public.api_credentials for select to authenticated using (core.is_platform_admin());
drop policy if exists cs_read on public.api_request_audit;
create policy cs_read on public.api_request_audit for select to authenticated using (core.is_platform_admin());
drop policy if exists cs_read on public.event_subscriptions;
create policy cs_read on public.event_subscriptions for select to authenticated using (core.is_platform_admin());
drop policy if exists cs_read on public.domain_events;
create policy cs_read on public.domain_events for select to authenticated using (core.is_platform_admin());
drop policy if exists cs_read on public.webhook_receipts;
create policy cs_read on public.webhook_receipts for select to authenticated using (core.is_platform_admin());
drop policy if exists cs_read on integration.webhook_events;
create policy cs_read on integration.webhook_events for select to authenticated using (core.is_platform_admin());

-- Child-table policies inherit access from their governed parent instead of becoming
-- globally readable simply because the child does not repeat project/org columns.
drop policy if exists cs_read on public.proposal_lines;
create policy cs_read on public.proposal_lines for select to authenticated using (
  exists (select 1 from public.proposals p where p.id = proposal_id and core.is_internal_org_member(p.organisation_id))
);
drop policy if exists cs_read on public.contract_obligations;
create policy cs_read on public.contract_obligations for select to authenticated using (
  exists (select 1 from public.contracts c where c.id = contract_id and core.is_internal_org_member(c.organisation_id))
);
drop policy if exists cs_read on public.invoice_lines;
create policy cs_read on public.invoice_lines for select to authenticated using (
  exists (select 1 from public.invoices i where i.id = invoice_id and core.is_internal_org_member(i.organisation_id))
);
drop policy if exists cs_read on public.content_versions;
create policy cs_read on public.content_versions for select to authenticated using (
  exists (select 1 from public.content_entries e where e.id = content_entry_id and core.is_internal_org_member(e.organisation_id))
);
drop policy if exists cs_read on public.template_versions;
create policy cs_read on public.template_versions for select to authenticated using (
  exists (select 1 from public.document_templates t where t.id = template_id and core.is_internal_org_member(t.organisation_id))
);
drop policy if exists cs_read on public.publication_set_items;
create policy cs_read on public.publication_set_items for select to authenticated using (
  exists (select 1 from public.publication_sets s where s.id = publication_set_id and project.can_access_project(s.project_id))
);
drop policy if exists cs_read on public.generated_artifacts;
create policy cs_read on public.generated_artifacts for select to authenticated using (
  (project_id is not null and project.can_access_project(project_id))
  or exists (
    select 1 from public.generation_jobs j
    where j.id = generation_job_id and core.is_internal_org_member(j.organisation_id)
  )
);

drop policy if exists cs_read on cde.file_versions;
create policy cs_read on cde.file_versions for select to authenticated using (
  exists (select 1 from cde.documents d where d.id = document_id and project.can_access_project(d.project_id))
);
drop policy if exists cs_read on cde.transmittal_items;
create policy cs_read on cde.transmittal_items for select to authenticated using (
  exists (select 1 from cde.transmittals t where t.id = transmittal_id and project.can_access_project(t.project_id))
);
drop policy if exists cs_read on coordination.issue_links;
create policy cs_read on coordination.issue_links for select to authenticated using (
  exists (select 1 from coordination.issues i where i.id = issue_id and project.can_access_project(i.project_id))
);
drop policy if exists cs_read on coordination.issue_comments;
create policy cs_read on coordination.issue_comments for select to authenticated using (
  exists (select 1 from coordination.issues i where i.id = issue_id and project.can_access_project(i.project_id))
);
drop policy if exists cs_read on cost.boq_lines;
create policy cs_read on cost.boq_lines for select to authenticated using (
  exists (select 1 from cost.cost_plans p where p.id = cost_plan_id and project.can_access_project(p.project_id))
);
drop policy if exists cs_read on procurement.tender_boq_lines;
create policy cs_read on procurement.tender_boq_lines for select to authenticated using (
  exists (select 1 from procurement.tender_packages p where p.id = tender_package_id and project.can_access_project(p.project_id))
);
drop policy if exists cs_read on procurement.tender_invites;
create policy cs_read on procurement.tender_invites for select to authenticated using (
  exists (select 1 from procurement.tender_packages p where p.id = tender_package_id and project.can_access_project(p.project_id))
);
drop policy if exists cs_read on procurement.bids;
create policy cs_read on procurement.bids for select to authenticated using (
  exists (select 1 from procurement.tender_packages p where p.id = tender_package_id and project.can_access_project(p.project_id))
);
drop policy if exists cs_read on procurement.bid_lines;
create policy cs_read on procurement.bid_lines for select to authenticated using (
  exists (
    select 1 from procurement.bids b
    join procurement.tender_packages p on p.id = b.tender_package_id
    where b.id = bid_id and project.can_access_project(p.project_id)
  )
);

drop policy if exists cs_read on finance.journal_lines;
create policy cs_read on finance.journal_lines for select to authenticated using (
  (project_id is not null and project.can_access_project(project_id))
  or exists (select 1 from finance.journals j where j.id = journal_id and core.is_internal_org_member(j.organisation_id))
);
drop policy if exists cs_read on finance.bank_transactions;
create policy cs_read on finance.bank_transactions for select to authenticated using (
  exists (select 1 from finance.bank_accounts a where a.id = bank_account_id and core.is_internal_org_member(a.organisation_id))
);
drop policy if exists cs_read on finance.budget_lines;
create policy cs_read on finance.budget_lines for select to authenticated using (
  exists (select 1 from finance.budgets b where b.id = budget_id and core.is_internal_org_member(b.organisation_id))
);

drop policy if exists cs_read on feasibility.programme_items;
create policy cs_read on feasibility.programme_items for select to authenticated using (
  exists (select 1 from feasibility.programme_briefs b where b.id = programme_brief_id and project.can_access_project(b.project_id))
);
drop policy if exists cs_read on feasibility.economic_assumptions;
create policy cs_read on feasibility.economic_assumptions for select to authenticated using (
  exists (select 1 from feasibility.development_scenarios s where s.id = scenario_id and project.can_access_project(s.project_id))
);
drop policy if exists cs_read on feasibility.scenario_metrics;
create policy cs_read on feasibility.scenario_metrics for select to authenticated using (
  exists (select 1 from feasibility.development_scenarios s where s.id = scenario_id and project.can_access_project(s.project_id))
);

drop policy if exists cs_read on engagement.scope_selections;
create policy cs_read on engagement.scope_selections for select to authenticated using (
  exists (
    select 1 from engagement.intake_sessions s
    where s.id = intake_session_id
      and (
        (s.project_id is not null and project.can_access_project(s.project_id))
        or (s.organisation_id is not null and core.is_internal_org_member(s.organisation_id))
      )
  )
);
drop policy if exists cs_read on engagement.proposal_negotiation_events;
create policy cs_read on engagement.proposal_negotiation_events for select to authenticated using (
  exists (select 1 from public.proposals p where p.id = proposal_id and core.is_internal_org_member(p.organisation_id))
);
drop policy if exists cs_read on engagement.activations;
create policy cs_read on engagement.activations for select to authenticated using (
  (project_id is not null and project.can_access_project(project_id))
  or exists (select 1 from public.opportunities o where o.id = opportunity_id and core.is_internal_org_member(o.organisation_id))
);

-- Every foreign key receives a covering index. Names are deterministic and compact.
do $$
declare
  r record;
  index_name text;
  columns_sql text;
begin
  for r in
    select
      con.oid as constraint_oid,
      con.conname,
      ns.nspname as schema_name,
      tbl.relname as table_name,
      con.conrelid,
      con.conkey
    from pg_constraint con
    join pg_class tbl on tbl.oid = con.conrelid
    join pg_namespace ns on ns.oid = tbl.relnamespace
    where con.contype = 'f'
      and ns.nspname not in ('pg_catalog','information_schema','auth','storage','realtime','vault','extensions','supabase_migrations')
  loop
    select string_agg(format('%I', a.attname), ', ' order by u.ordinality)
      into columns_sql
    from unnest(r.conkey) with ordinality u(attnum, ordinality)
    join pg_attribute a on a.attrelid = r.conrelid and a.attnum = u.attnum;

    if not exists (
      select 1
      from pg_index i
      where i.indrelid = r.conrelid
        and i.indisvalid
        and (i.indkey::smallint[])[0:cardinality(r.conkey)-1] = r.conkey
    ) then
      index_name := 'ix_fk_' || left(r.table_name, 28) || '_' || substr(md5(r.conname), 1, 8);
      execute format('create index if not exists %I on %I.%I (%s)', index_name, r.schema_name, r.table_name, columns_sql);
    end if;
  end loop;
end $$;

comment on function core.is_platform_admin() is 'Platform-admin authority check used by control-plane RLS policies.';
comment on function project.can_access_project(uuid) is 'Project access is limited to org administrators, assigned project members, lead architect or creator.';

commit;
