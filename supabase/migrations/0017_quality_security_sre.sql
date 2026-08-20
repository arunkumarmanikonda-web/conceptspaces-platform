begin;

create table if not exists public.quality_gate_definitions (
  id uuid primary key default gen_random_uuid(), code text not null unique, name text not null,
  stage text not null check (stage in ('commit','pull_request','preview','production','release')), description text not null,
  blocking boolean not null default true, criticalities jsonb not null default '[]'::jsonb, evidence_required jsonb not null default '[]'::jsonb,
  enabled boolean not null default true, created_at timestamptz not null default now(), updated_at timestamptz not null default now()
);

create table if not exists public.quality_gate_runs (
  id uuid primary key default gen_random_uuid(), gate_code text not null, release_ref text not null,
  status text not null check (status in ('pending','pass','fail','waived')), evidence_refs jsonb not null default '[]'::jsonb,
  automated boolean not null default false, executed_at timestamptz not null default now(), executed_by uuid,
  waiver_id uuid, details jsonb not null default '{}'::jsonb
);

create table if not exists public.test_cases (
  id uuid primary key default gen_random_uuid(), suite text not null, code text not null unique, title text not null,
  type text not null check (type in ('unit','integration','contract','e2e','security','performance','accessibility','restore')),
  criticality text not null check (criticality in ('C0','C1','C2','C3','C4')), requirement_refs jsonb not null default '[]'::jsonb,
  automated boolean not null default false, expected_result text not null, enabled boolean not null default true,
  created_at timestamptz not null default now(), updated_at timestamptz not null default now()
);

create table if not exists public.test_executions (
  id uuid primary key default gen_random_uuid(), test_case_id uuid not null references public.test_cases(id) on delete cascade,
  release_ref text not null, status text not null check (status in ('pass','fail','blocked','skipped')), duration_ms integer,
  evidence_refs jsonb not null default '[]'::jsonb, error_code text, executed_at timestamptz not null default now()
);

create table if not exists public.product_defects (
  id uuid primary key default gen_random_uuid(), project_or_product_ref text not null, title text not null,
  severity text not null check (severity in ('info','low','medium','high','critical')),
  source text not null check (source in ('test','production','security','user','audit')), affected_routes jsonb not null default '[]'::jsonb,
  affected_criticalities jsonb not null default '[]'::jsonb,
  status text not null default 'open' check (status in ('open','triage','fixing','verification','closed','accepted_risk')),
  owner_user_id uuid, due_at timestamptz, evidence_refs jsonb not null default '[]'::jsonb,
  created_at timestamptz not null default now(), updated_at timestamptz not null default now()
);

create table if not exists public.service_level_objectives (
  id uuid primary key default gen_random_uuid(), service text not null, indicator text not null, target numeric not null,
  unit text not null check (unit in ('percent','milliseconds','count')), window_days integer not null,
  error_budget_policy text not null, criticality text not null check (criticality in ('C1','C2','C3','C4')),
  active boolean not null default true, created_at timestamptz not null default now(), unique(service, indicator)
);

create table if not exists public.slo_measurements (
  id uuid primary key default gen_random_uuid(), slo_id uuid not null references public.service_level_objectives(id) on delete cascade,
  window_start timestamptz not null, window_end timestamptz not null, achieved numeric not null,
  error_budget_remaining_percent numeric not null, evidence_ref text not null, created_at timestamptz not null default now()
);

create table if not exists public.incidents (
  id uuid primary key default gen_random_uuid(), number text not null unique, title text not null,
  severity text not null check (severity in ('SEV0','SEV1','SEV2','SEV3')),
  status text not null default 'declared' check (status in ('declared','mitigating','monitoring','resolved','postmortem','closed')),
  service_refs jsonb not null default '[]'::jsonb, started_at timestamptz not null, detected_at timestamptz not null,
  mitigated_at timestamptz, resolved_at timestamptz, commander_user_id uuid, customer_impact text not null,
  regulatory_impact text, timeline_refs jsonb not null default '[]'::jsonb, postmortem_ref text,
  created_at timestamptz not null default now(), updated_at timestamptz not null default now()
);

create table if not exists public.security_findings (
  id uuid primary key default gen_random_uuid(), source text not null check (source in ('sast','dependency','secret_scan','penetration_test','configuration','advisory')),
  title text not null, severity text not null check (severity in ('info','low','medium','high','critical')), cwe text,
  affected_component text not null, status text not null default 'open' check (status in ('open','remediating','verified','accepted_risk','false_positive')),
  detected_at timestamptz not null default now(), due_at timestamptz, owner_user_id uuid, evidence_refs jsonb not null default '[]'::jsonb,
  risk_acceptance_id uuid, created_at timestamptz not null default now(), updated_at timestamptz not null default now()
);

create table if not exists public.risk_acceptances (
  id uuid primary key default gen_random_uuid(), finding_or_defect_ref text not null, rationale text not null,
  compensating_controls jsonb not null default '[]'::jsonb, expires_at timestamptz not null, approved_by uuid not null,
  approved_at timestamptz not null default now(), review_frequency_days integer not null default 30,
  created_at timestamptz not null default now()
);

create table if not exists public.backup_restore_drills (
  id uuid primary key default gen_random_uuid(), service text not null, backup_ref text not null,
  environment text not null check (environment in ('test','staging')), started_at timestamptz not null, completed_at timestamptz,
  rpo_minutes_target integer not null, rto_minutes_target integer not null, achieved_rpo_minutes integer, achieved_rto_minutes integer,
  integrity_checks jsonb not null default '[]'::jsonb, status text not null check (status in ('running','pass','fail')),
  evidence_refs jsonb not null default '[]'::jsonb, created_at timestamptz not null default now()
);

create table if not exists public.feature_flags (
  id uuid primary key default gen_random_uuid(), flag_key text not null, description text not null, owner_domain text not null,
  enabled boolean not null default false, environment text not null, percentage numeric, allow_list_refs jsonb not null default '[]'::jsonb,
  expires_at timestamptz, kill_switch boolean not null default true, created_at timestamptz not null default now(), updated_at timestamptz not null default now(),
  unique(flag_key, environment)
);

create index if not exists quality_gate_runs_release_idx on public.quality_gate_runs(release_ref, executed_at desc);
create index if not exists test_executions_release_idx on public.test_executions(release_ref, executed_at desc);
create index if not exists defects_status_severity_idx on public.product_defects(status, severity);
create index if not exists incidents_status_time_idx on public.incidents(status, started_at desc);
create index if not exists security_findings_status_severity_idx on public.security_findings(status, severity);

alter table public.quality_gate_definitions enable row level security;
alter table public.quality_gate_runs enable row level security;
alter table public.test_cases enable row level security;
alter table public.test_executions enable row level security;
alter table public.product_defects enable row level security;
alter table public.service_level_objectives enable row level security;
alter table public.slo_measurements enable row level security;
alter table public.incidents enable row level security;
alter table public.security_findings enable row level security;
alter table public.risk_acceptances enable row level security;
alter table public.backup_restore_drills enable row level security;
alter table public.feature_flags enable row level security;

commit;
