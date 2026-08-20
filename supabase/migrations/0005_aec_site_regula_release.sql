begin;

create schema if not exists aec;
create schema if not exists regula;

create table if not exists aec.site_geometries (
  id uuid primary key default gen_random_uuid(),
  project_id uuid not null references project.projects(id) on delete cascade,
  coordinate_system text,
  georeferenced boolean not null default false,
  unit text not null check (unit in ('m','ft')),
  source_type text not null check (source_type in ('survey','cadastral','dwg','dxf','point_cloud','lidar','manual')),
  source_reference text,
  verification text not null default 'unverified' check (verification in ('unverified','source_verified','professionally_verified','authority_verified')),
  geometry jsonb not null default '{}'::jsonb,
  area numeric(18,4),
  created_by uuid references auth.users(id),
  verified_by uuid references auth.users(id),
  verified_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists aec.site_constraints (
  id uuid primary key default gen_random_uuid(),
  project_id uuid not null references project.projects(id) on delete cascade,
  code citext not null,
  label text not null,
  value jsonb not null,
  unit text,
  source_reference text,
  verification text not null default 'unverified' check (verification in ('unverified','source_verified','professionally_verified','authority_verified')),
  critical boolean not null default false,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique(project_id, code)
);

create table if not exists regula.packs (
  id uuid primary key default gen_random_uuid(),
  jurisdiction_country text not null,
  jurisdiction_state text,
  jurisdiction_city text,
  authority text,
  code citext not null,
  title text not null,
  effective_from date not null,
  effective_until date,
  supersedes_pack_id uuid references regula.packs(id),
  publication_status text not null default 'draft' check (publication_status in ('draft','technical_review','legal_review','published','retired')),
  source_uri text,
  source_hash text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique(code, effective_from)
);

create table if not exists regula.rules (
  id uuid primary key default gen_random_uuid(),
  pack_id uuid not null references regula.packs(id) on delete cascade,
  rule_code citext not null,
  subject text not null,
  expression text,
  narrative text not null,
  source_reference text not null,
  effective_from date not null,
  disposition text not null default 'amber' check (disposition in ('green','amber','red')),
  requires_professional_interpretation boolean not null default false,
  metadata jsonb not null default '{}'::jsonb,
  unique(pack_id, rule_code)
);

create table if not exists regula.project_applicability (
  id uuid primary key default gen_random_uuid(),
  project_id uuid not null references project.projects(id) on delete cascade,
  pack_id uuid not null references regula.packs(id) on delete restrict,
  applicability_reason text not null,
  precedence integer not null default 100,
  status text not null default 'proposed' check (status in ('proposed','confirmed','superseded','rejected')),
  confirmed_by uuid references auth.users(id),
  confirmed_at timestamptz,
  unique(project_id, pack_id)
);

create table if not exists regula.compliance_findings (
  id uuid primary key default gen_random_uuid(),
  project_id uuid not null references project.projects(id) on delete cascade,
  rule_id uuid not null references regula.rules(id) on delete restrict,
  disposition text not null check (disposition in ('green','amber','red')),
  status text not null check (status in ('pass','fail','not_verified','requires_interpretation')),
  observed_value jsonb,
  required_value jsonb,
  evidence_refs jsonb not null default '[]'::jsonb,
  explanation text not null,
  checked_by_type text not null default 'system' check (checked_by_type in ('system','agent','professional','authority')),
  checked_by uuid,
  checked_at timestamptz not null default now()
);

create table if not exists aec.design_intents (
  id uuid primary key default gen_random_uuid(),
  project_id uuid not null references project.projects(id) on delete cascade,
  version integer not null default 1,
  typology text not null,
  optimisation_mode text not null check (optimisation_mode in ('commercial_yield','environmental','architecture','capex','balanced')),
  programme jsonb not null default '{}'::jsonb,
  mandatory_requirements jsonb not null default '[]'::jsonb,
  preferences jsonb not null default '{}'::jsonb,
  exclusions jsonb not null default '[]'::jsonb,
  created_by uuid references auth.users(id),
  created_at timestamptz not null default now(),
  unique(project_id, version)
);

create table if not exists aec.design_branches (
  id uuid primary key default gen_random_uuid(),
  project_id uuid not null references project.projects(id) on delete cascade,
  parent_branch_id uuid references aec.design_branches(id),
  code citext not null,
  title text not null,
  branch_reason text,
  status text not null default 'active' check (status in ('active','merged','abandoned','superseded')),
  created_by uuid references auth.users(id),
  created_at timestamptz not null default now(),
  unique(project_id, code)
);

create table if not exists aec.design_options (
  id uuid primary key default gen_random_uuid(),
  project_id uuid not null references project.projects(id) on delete cascade,
  branch_id uuid not null references aec.design_branches(id) on delete cascade,
  intent_id uuid references aec.design_intents(id) on delete restrict,
  name text not null,
  status text not null default 'generated' check (status in ('generated','validated','shortlisted','client_selected','superseded')),
  generated_by text not null check (generated_by in ('human','ai','hybrid')),
  geometry_artifact_ref text,
  metrics jsonb not null default '[]'::jsonb,
  assumptions jsonb not null default '[]'::jsonb,
  validation_summary jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists governance.release_safety_cases (
  id uuid primary key default gen_random_uuid(),
  project_id uuid not null references project.projects(id) on delete cascade,
  gate_id uuid references governance.release_gates(id) on delete cascade,
  package_type text not null,
  package_reference text,
  content_hash text,
  state text not null default 'draft' check (state in ('draft','blocked','ready_for_review','approved','issued')),
  unresolved_critical_defects integer not null default 0 check (unresolved_critical_defects >= 0),
  checks jsonb not null default '[]'::jsonb,
  professional_approvals jsonb not null default '[]'::jsonb,
  client_approval_ref text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create index if not exists site_geometries_project_idx on aec.site_geometries(project_id, created_at desc);
create index if not exists site_constraints_project_idx on aec.site_constraints(project_id, critical);
create index if not exists regula_packs_jurisdiction_idx on regula.packs(jurisdiction_country, jurisdiction_state, jurisdiction_city, effective_from);
create index if not exists regula_findings_project_idx on regula.compliance_findings(project_id, status, disposition);
create index if not exists design_options_project_idx on aec.design_options(project_id, status);
create index if not exists release_safety_cases_project_idx on governance.release_safety_cases(project_id, state);

alter table aec.site_geometries enable row level security;
alter table aec.site_constraints enable row level security;
alter table regula.packs enable row level security;
alter table regula.rules enable row level security;
alter table regula.project_applicability enable row level security;
alter table regula.compliance_findings enable row level security;
alter table aec.design_intents enable row level security;
alter table aec.design_branches enable row level security;
alter table aec.design_options enable row level security;
alter table governance.release_safety_cases enable row level security;

commit;
