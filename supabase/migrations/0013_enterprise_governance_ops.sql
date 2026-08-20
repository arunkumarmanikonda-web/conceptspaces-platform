-- Concept Spaces workflow automation, maker-checker, risk, compliance, audit and KPI operations

create schema if not exists operations;
create schema if not exists compliance;
create schema if not exists analytics;

create table if not exists operations.workflow_definitions (
  id uuid primary key default gen_random_uuid(),
  code citext not null,
  name text not null,
  version integer not null default 1,
  domain text not null,
  state text not null default 'draft' check (state in ('draft','published','retired')),
  trigger_type text not null check (trigger_type in ('manual','event','schedule','condition')),
  sla_minutes integer,
  escalation_policy_ref text,
  definition jsonb not null default '{}'::jsonb,
  created_by uuid,
  approved_by uuid,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique(code,version)
);

create table if not exists operations.workflow_instances (
  id uuid primary key default gen_random_uuid(),
  definition_id uuid not null references operations.workflow_definitions(id) on delete restrict,
  definition_version integer not null,
  organisation_id uuid not null,
  project_id uuid,
  subject_type text not null,
  subject_id uuid,
  state text not null default 'queued' check (state in ('queued','running','waiting','completed','failed','cancelled')),
  current_step_code text,
  correlation_id uuid not null default gen_random_uuid(),
  started_at timestamptz,
  completed_at timestamptz,
  created_at timestamptz not null default now()
);

create table if not exists operations.tasks (
  id uuid primary key default gen_random_uuid(),
  workflow_instance_id uuid references operations.workflow_instances(id) on delete cascade,
  organisation_id uuid not null,
  project_id uuid,
  title text not null,
  task_type text not null,
  state text not null default 'open' check (state in ('open','in_progress','submitted','approved','rejected','cancelled')),
  priority text not null default 'normal' check (priority in ('low','normal','high','urgent')),
  assignee_user_id uuid,
  assignee_role_code text,
  due_at timestamptz,
  sla_breached boolean not null default false,
  maker_user_id uuid,
  checker_user_id uuid,
  evidence_refs jsonb not null default '[]'::jsonb,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists operations.maker_checker_decisions (
  id uuid primary key default gen_random_uuid(),
  subject_type text not null,
  subject_id uuid not null,
  action text not null,
  maker_user_id uuid not null,
  checker_user_id uuid,
  maker_submitted_at timestamptz not null default now(),
  checker_decision text check (checker_decision in ('approved','rejected')),
  checker_reason text,
  checker_decided_at timestamptz,
  created_at timestamptz not null default now()
);

create table if not exists operations.risks (
  id uuid primary key default gen_random_uuid(),
  organisation_id uuid not null,
  project_id uuid,
  code citext not null,
  title text not null,
  category text not null,
  description text not null,
  probability integer not null check (probability between 1 and 5),
  impact integer not null check (impact between 1 and 5),
  inherent_level text not null check (inherent_level in ('low','medium','high','critical')),
  owner_user_id uuid,
  treatment text not null,
  residual_level text check (residual_level in ('low','medium','high','critical')),
  status text not null default 'open' check (status in ('open','mitigating','accepted','closed')),
  source_refs jsonb not null default '[]'::jsonb,
  review_due_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique(organisation_id,project_id,code)
);

create table if not exists compliance.controls (
  id uuid primary key default gen_random_uuid(),
  code citext not null unique,
  name text not null,
  domain text not null,
  objective text not null,
  state text not null default 'designed' check (state in ('designed','implemented','tested','ineffective','retired')),
  owner_role_code text,
  frequency text,
  evidence_required jsonb not null default '[]'::jsonb,
  linked_risk_codes jsonb not null default '[]'::jsonb,
  linked_obligation_codes jsonb not null default '[]'::jsonb,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists compliance.obligations (
  id uuid primary key default gen_random_uuid(),
  code citext not null,
  jurisdiction text not null,
  authority text,
  domain text not null,
  title text not null,
  description text not null,
  source_ref text not null,
  effective_from date not null,
  effective_until date,
  applicability_expression text,
  owner_role_code text,
  evidence_requirements jsonb not null default '[]'::jsonb,
  version integer not null default 1,
  state text not null default 'draft' check (state in ('draft','review','published','retired')),
  created_at timestamptz not null default now(),
  unique(code,version)
);

create table if not exists compliance.assessments (
  id uuid primary key default gen_random_uuid(),
  obligation_id uuid not null references compliance.obligations(id) on delete restrict,
  organisation_id uuid not null,
  project_id uuid,
  state text not null default 'not_assessed' check (state in ('not_assessed','compliant','partial','non_compliant','not_applicable')),
  rationale text not null default '',
  evidence_refs jsonb not null default '[]'::jsonb,
  assessed_by uuid,
  assessed_at timestamptz,
  next_review_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists compliance.audit_findings (
  id uuid primary key default gen_random_uuid(),
  audit_code citext not null,
  organisation_id uuid not null,
  project_id uuid,
  finding_type text not null check (finding_type in ('observation','minor','major','critical')),
  title text not null,
  description text not null,
  control_code text,
  obligation_code text,
  owner_user_id uuid,
  corrective_action text,
  due_at timestamptz,
  state text not null default 'open' check (state in ('open','actioned','verified','closed')),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists analytics.kpi_definitions (
  id uuid primary key default gen_random_uuid(),
  code citext not null unique,
  name text not null,
  domain text not null,
  unit text not null,
  direction text not null check (direction in ('higher_is_better','lower_is_better','target_band')),
  target numeric(20,6),
  warning_threshold numeric(20,6),
  critical_threshold numeric(20,6),
  calculation_ref text not null,
  refresh_cadence text not null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists analytics.kpi_observations (
  id uuid primary key default gen_random_uuid(),
  kpi_id uuid not null references analytics.kpi_definitions(id) on delete cascade,
  organisation_id uuid not null,
  project_id uuid,
  observed_at timestamptz not null,
  value numeric(24,8) not null,
  source_ref text not null,
  confidence text not null check (confidence in ('A','B','C','D')),
  created_at timestamptz not null default now()
);

create table if not exists operations.platform_incidents (
  id uuid primary key default gen_random_uuid(),
  code citext not null unique,
  severity text not null check (severity in ('SEV0','SEV1','SEV2','SEV3')),
  title text not null,
  state text not null default 'open' check (state in ('open','mitigating','resolved','postmortem')),
  service text not null,
  detected_at timestamptz not null,
  resolved_at timestamptz,
  owner_user_id uuid,
  customer_impact text,
  timeline_refs jsonb not null default '[]'::jsonb,
  root_cause text,
  corrective_actions jsonb not null default '[]'::jsonb,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create index if not exists ix_workflow_instances_state on operations.workflow_instances(organisation_id,state,created_at desc);
create index if not exists ix_tasks_queue on operations.tasks(organisation_id,state,priority,due_at);
create index if not exists ix_risks_project on operations.risks(organisation_id,project_id,status,inherent_level);
create index if not exists ix_compliance_assessments_project on compliance.assessments(organisation_id,project_id,state);
create index if not exists ix_audit_findings_state on compliance.audit_findings(organisation_id,state,finding_type);
create index if not exists ix_kpi_observations on analytics.kpi_observations(kpi_id,organisation_id,project_id,observed_at desc);

alter table operations.workflow_definitions enable row level security;
alter table operations.workflow_instances enable row level security;
alter table operations.tasks enable row level security;
alter table operations.maker_checker_decisions enable row level security;
alter table operations.risks enable row level security;
alter table operations.platform_incidents enable row level security;
alter table compliance.controls enable row level security;
alter table compliance.obligations enable row level security;
alter table compliance.assessments enable row level security;
alter table compliance.audit_findings enable row level security;
alter table analytics.kpi_definitions enable row level security;
alter table analytics.kpi_observations enable row level security;
