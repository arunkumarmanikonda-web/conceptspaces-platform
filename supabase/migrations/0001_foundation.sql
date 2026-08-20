-- Concept Spaces foundation schema
-- Prepared for Supabase/PostgreSQL. Not applied until a dedicated project is provisioned.

create extension if not exists pgcrypto;
create extension if not exists citext;

create schema if not exists core;
create schema if not exists project;
create schema if not exists governance;
create schema if not exists audit;
create schema if not exists workflow;

create table if not exists core.organisations (
  id uuid primary key default gen_random_uuid(),
  name text not null,
  code citext not null unique,
  status text not null default 'active' check (status in ('active','suspended')),
  settings jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists core.profiles (
  user_id uuid primary key references auth.users(id) on delete cascade,
  display_name text,
  phone text,
  timezone text not null default 'Asia/Kolkata',
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists core.memberships (
  id uuid primary key default gen_random_uuid(),
  organisation_id uuid not null references core.organisations(id) on delete cascade,
  user_id uuid not null references auth.users(id) on delete cascade,
  role_code text not null,
  status text not null default 'active' check (status in ('active','invited','suspended')),
  created_at timestamptz not null default now(),
  unique (organisation_id,user_id,role_code)
);

create table if not exists core.professional_credentials (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  credential_type text not null,
  issuing_body text not null,
  registration_number text not null,
  discipline text,
  valid_from date,
  valid_until date,
  verification_status text not null default 'pending' check (verification_status in ('pending','verified','rejected','expired')),
  evidence_uri text,
  verified_at timestamptz,
  verified_by uuid references auth.users(id),
  created_at timestamptz not null default now(),
  unique (credential_type,issuing_body,registration_number)
);

create table if not exists project.projects (
  id uuid primary key default gen_random_uuid(),
  organisation_id uuid not null references core.organisations(id) on delete restrict,
  code citext not null,
  name text not null,
  typology text not null,
  stage text not null default 'intake',
  criticality text not null default 'C1' check (criticality in ('C0','C1','C2','C3','C4')),
  jurisdiction_country text not null default 'IN',
  jurisdiction_state text,
  jurisdiction_city text,
  lead_architect_user_id uuid references auth.users(id),
  status text not null default 'active' check (status in ('active','on_hold','complete','cancelled')),
  created_by uuid references auth.users(id),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (organisation_id,code)
);

create table if not exists project.project_members (
  id uuid primary key default gen_random_uuid(),
  project_id uuid not null references project.projects(id) on delete cascade,
  user_id uuid not null references auth.users(id) on delete cascade,
  role_code text not null,
  discipline text,
  status text not null default 'active',
  created_at timestamptz not null default now(),
  unique (project_id,user_id,role_code)
);

create table if not exists project.truth_records (
  id uuid primary key default gen_random_uuid(),
  project_id uuid not null references project.projects(id) on delete cascade,
  kind text not null check (kind in ('fact','assumption','decision','requirement','constraint','evidence')),
  record_key text not null,
  value jsonb not null,
  unit text,
  source_type text,
  source_reference text,
  confidence text not null check (confidence in ('A','B','C','D')),
  status text not null default 'draft' check (status in ('draft','verified','superseded','rejected','expired')),
  criticality text not null default 'C1' check (criticality in ('C0','C1','C2','C3','C4')),
  valid_from timestamptz,
  valid_until timestamptz,
  supersedes_id uuid references project.truth_records(id),
  created_by uuid references auth.users(id),
  verified_by uuid references auth.users(id),
  verified_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create index if not exists ix_truth_records_project on project.truth_records(project_id);
create index if not exists ix_truth_records_key on project.truth_records(project_id,record_key);
create index if not exists ix_truth_records_status on project.truth_records(project_id,status,criticality);

create table if not exists project.requirements (
  id uuid primary key default gen_random_uuid(),
  project_id uuid not null references project.projects(id) on delete cascade,
  code citext not null,
  statement text not null,
  category text not null,
  source_truth_record_id uuid references project.truth_records(id),
  acceptance_criteria jsonb not null default '[]'::jsonb,
  status text not null default 'open' check (status in ('open','satisfied','waived','rejected')),
  criticality text not null default 'C1' check (criticality in ('C0','C1','C2','C3','C4')),
  owner_user_id uuid references auth.users(id),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique(project_id,code)
);

create table if not exists project.dependencies (
  id uuid primary key default gen_random_uuid(),
  project_id uuid not null references project.projects(id) on delete cascade,
  upstream_type text not null,
  upstream_id uuid not null,
  downstream_type text not null,
  downstream_id uuid not null,
  dependency_kind text not null,
  impact_weight numeric(8,4) not null default 1,
  created_at timestamptz not null default now(),
  unique(project_id,upstream_type,upstream_id,downstream_type,downstream_id,dependency_kind)
);

create table if not exists governance.release_gates (
  id uuid primary key default gen_random_uuid(),
  project_id uuid not null references project.projects(id) on delete cascade,
  gate_code citext not null,
  name text not null,
  discipline text not null,
  criticality text not null check (criticality in ('C0','C1','C2','C3','C4')),
  state text not null default 'not_ready' check (state in ('not_ready','ready_for_review','approved','blocked','released')),
  required_evidence_types jsonb not null default '[]'::jsonb,
  unresolved_critical_defects integer not null default 0 check (unresolved_critical_defects >= 0),
  approved_by uuid references auth.users(id),
  approved_at timestamptz,
  released_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique(project_id,gate_code)
);

create table if not exists governance.release_evidence (
  id uuid primary key default gen_random_uuid(),
  project_id uuid not null references project.projects(id) on delete cascade,
  gate_id uuid not null references governance.release_gates(id) on delete cascade,
  evidence_type text not null check (evidence_type in ('truth_snapshot','regulatory_check','engineering_check','coordination_check','professional_approval','client_approval','document_hash')),
  reference text not null,
  evidence_hash text,
  passed boolean not null default false,
  payload jsonb not null default '{}'::jsonb,
  produced_by uuid references auth.users(id),
  produced_at timestamptz not null default now()
);

create index if not exists ix_release_evidence_gate on governance.release_evidence(gate_id,evidence_type,passed);

create table if not exists governance.exceptions (
  id uuid primary key default gen_random_uuid(),
  project_id uuid not null references project.projects(id) on delete cascade,
  exception_type text not null,
  description text not null,
  criticality text not null check (criticality in ('C0','C1','C2','C3','C4')),
  status text not null default 'open' check (status in ('open','accepted','resolved','rejected')),
  raised_by uuid references auth.users(id),
  accepted_by uuid references auth.users(id),
  rationale text,
  created_at timestamptz not null default now(),
  resolved_at timestamptz
);

create table if not exists workflow.jobs (
  id uuid primary key default gen_random_uuid(),
  organisation_id uuid not null references core.organisations(id) on delete cascade,
  project_id uuid references project.projects(id) on delete cascade,
  job_type text not null,
  status text not null default 'queued' check (status in ('queued','running','awaiting_approval','succeeded','failed','cancelled')),
  criticality text not null default 'C1' check (criticality in ('C0','C1','C2','C3','C4')),
  autonomy_level text not null default 'ai_draft' check (autonomy_level in ('human_only','ai_advisory','ai_draft','execute_after_approval','bounded_autonomous')),
  input jsonb not null default '{}'::jsonb,
  output jsonb,
  error jsonb,
  correlation_id uuid not null default gen_random_uuid(),
  created_by uuid references auth.users(id),
  created_at timestamptz not null default now(),
  started_at timestamptz,
  finished_at timestamptz
);

create table if not exists audit.events (
  id uuid primary key default gen_random_uuid(),
  organisation_id uuid not null references core.organisations(id) on delete restrict,
  project_id uuid references project.projects(id) on delete restrict,
  actor_id uuid,
  actor_type text not null check (actor_type in ('user','agent','system','integration')),
  action text not null,
  resource_type text not null,
  resource_id uuid,
  before_state jsonb,
  after_state jsonb,
  reason text,
  correlation_id uuid,
  previous_hash text,
  event_hash text not null,
  created_at timestamptz not null default now()
);

create index if not exists ix_audit_events_org_created on audit.events(organisation_id,created_at desc);
create index if not exists ix_audit_events_project_created on audit.events(project_id,created_at desc);

create table if not exists audit.outbox (
  id uuid primary key default gen_random_uuid(),
  aggregate_type text not null,
  aggregate_id uuid not null,
  event_type text not null,
  payload jsonb not null,
  correlation_id uuid,
  status text not null default 'pending' check (status in ('pending','published','failed')),
  attempts integer not null default 0,
  created_at timestamptz not null default now(),
  published_at timestamptz
);

create or replace function core.is_org_member(target_org uuid)
returns boolean
language sql
stable
security definer
set search_path = core, public
as $$
  select exists (
    select 1 from core.memberships m
    where m.organisation_id = target_org
      and m.user_id = auth.uid()
      and m.status = 'active'
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
      and core.is_org_member(p.organisation_id)
  );
$$;

alter table core.organisations enable row level security;
alter table core.profiles enable row level security;
alter table core.memberships enable row level security;
alter table core.professional_credentials enable row level security;
alter table project.projects enable row level security;
alter table project.project_members enable row level security;
alter table project.truth_records enable row level security;
alter table project.requirements enable row level security;
alter table project.dependencies enable row level security;
alter table governance.release_gates enable row level security;
alter table governance.release_evidence enable row level security;
alter table governance.exceptions enable row level security;
alter table workflow.jobs enable row level security;
alter table audit.events enable row level security;
alter table audit.outbox enable row level security;

create policy organisations_read on core.organisations
for select using (core.is_org_member(id));

create policy profiles_self on core.profiles
for all using (user_id = auth.uid()) with check (user_id = auth.uid());

create policy memberships_read on core.memberships
for select using (core.is_org_member(organisation_id));

create policy credentials_self_read on core.professional_credentials
for select using (user_id = auth.uid());

create policy projects_org_access on project.projects
for all using (core.is_org_member(organisation_id)) with check (core.is_org_member(organisation_id));

create policy project_members_project_access on project.project_members
for select using (project.can_access_project(project_id));

create policy truth_project_access on project.truth_records
for select using (project.can_access_project(project_id));

create policy requirements_project_access on project.requirements
for select using (project.can_access_project(project_id));

create policy dependencies_project_access on project.dependencies
for select using (project.can_access_project(project_id));

create policy gates_project_access on governance.release_gates
for select using (project.can_access_project(project_id));

create policy evidence_project_access on governance.release_evidence
for select using (project.can_access_project(project_id));

create policy exceptions_project_access on governance.exceptions
for select using (project.can_access_project(project_id));

create policy jobs_org_access on workflow.jobs
for select using (core.is_org_member(organisation_id));

create policy audit_read on audit.events
for select using (core.is_org_member(organisation_id));

-- audit.outbox intentionally has no authenticated client policy.
-- Service-role workers publish events after durable database commit.

comment on table project.truth_records is 'Project Truth Engine canonical facts, assumptions, decisions, requirements, constraints and evidence.';
comment on table project.dependencies is 'Dependency and blast-radius graph edges used for change impact analysis.';
comment on table governance.release_gates is 'Proof Before Publish release gates. Critical defects must be zero before issue.';
comment on table audit.events is 'Append-only audit evidence. Application services must never update/delete rows.';
