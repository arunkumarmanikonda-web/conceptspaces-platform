begin;

create schema if not exists engineering;
create schema if not exists interiors;

create table if not exists engineering.engines (
  id uuid primary key default gen_random_uuid(),
  code citext not null,
  name text not null,
  discipline text not null,
  engine_type text not null check (engine_type in ('deterministic','parametric','physics_simulation','rules','optimisation','adapter')),
  vendor text,
  version text not null,
  executable_ref text,
  supported_standards jsonb not null default '[]'::jsonb,
  supported_units jsonb not null default '[]'::jsonb,
  certification_status text not null default 'uncertified' check (certification_status in ('uncertified','benchmarking','conditionally_approved','approved','suspended','retired')),
  maximum_criticality text not null default 'C1' check (maximum_criticality in ('C0','C1','C2','C3','C4')),
  checksum text,
  enabled boolean not null default false,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique(code, version)
);

create table if not exists engineering.engine_benchmark_cases (
  id uuid primary key default gen_random_uuid(),
  engine_id uuid not null references engineering.engines(id) on delete cascade,
  suite_code citext not null,
  name text not null,
  standard_reference text,
  input_ref text not null,
  expected_result_ref text not null,
  tolerance jsonb not null default '{}'::jsonb,
  criticality text not null default 'C2' check (criticality in ('C0','C1','C2','C3','C4')),
  active boolean not null default true,
  created_at timestamptz not null default now()
);

create table if not exists engineering.engine_benchmark_results (
  id uuid primary key default gen_random_uuid(),
  benchmark_case_id uuid not null references engineering.engine_benchmark_cases(id) on delete cascade,
  engine_id uuid not null references engineering.engines(id) on delete cascade,
  engine_version text not null,
  passed boolean not null,
  deviation jsonb not null default '{}'::jsonb,
  evidence_refs jsonb not null default '[]'::jsonb,
  executed_at timestamptz not null default now()
);

create table if not exists engineering.calculation_runs (
  id uuid primary key default gen_random_uuid(),
  project_id uuid not null references project.projects(id) on delete cascade,
  discipline text not null,
  calculation_type text not null,
  engine_id uuid not null references engineering.engines(id) on delete restrict,
  engine_version text not null,
  status text not null default 'draft' check (status in ('draft','queued','running','completed','failed','superseded')),
  input_snapshot_ref text not null,
  assumptions jsonb not null default '[]'::jsonb,
  standard_references jsonb not null default '[]'::jsonb,
  unit_system text not null,
  output_ref text,
  result_summary jsonb,
  evidence_refs jsonb not null default '[]'::jsonb,
  input_hash text not null,
  output_hash text,
  created_by uuid references auth.users(id),
  started_at timestamptz,
  finished_at timestamptz,
  created_at timestamptz not null default now()
);

create table if not exists engineering.professional_reviews (
  id uuid primary key default gen_random_uuid(),
  project_id uuid not null references project.projects(id) on delete cascade,
  resource_type text not null check (resource_type in ('calculation','drawing','model','design_package','material_package')),
  resource_id uuid not null,
  resource_hash text not null,
  discipline text not null,
  reviewer_user_id uuid not null references auth.users(id) on delete restrict,
  credential_id uuid not null references core.professional_credentials(id) on delete restrict,
  decision text not null default 'pending' check (decision in ('pending','accepted','accepted_with_comments','rejected')),
  comments text,
  reviewed_at timestamptz,
  created_at timestamptz not null default now()
);

create table if not exists engineering.architecture_packages (
  id uuid primary key default gen_random_uuid(),
  project_id uuid not null references project.projects(id) on delete cascade,
  stage text not null,
  version integer not null,
  space_programme_ref text not null,
  circulation_strategy jsonb,
  zoning_strategy jsonb,
  drawing_refs jsonb not null default '[]'::jsonb,
  model_refs jsonb not null default '[]'::jsonb,
  requirement_coverage_percent numeric(6,3) not null default 0 check (requirement_coverage_percent between 0 and 100),
  design_option_id uuid references aec.design_options(id) on delete set null,
  status text not null default 'draft' check (status in ('draft','coordinating','for_review','approved','issued')),
  created_by uuid references auth.users(id),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique(project_id, stage, version)
);

create table if not exists interiors.design_dna (
  id uuid primary key default gen_random_uuid(),
  project_id uuid not null references project.projects(id) on delete cascade,
  version integer not null,
  language jsonb not null default '[]'::jsonb,
  emotional_attributes jsonb not null default '[]'::jsonb,
  spatial_principles jsonb not null default '[]'::jsonb,
  material_preferences jsonb not null default '[]'::jsonb,
  material_exclusions jsonb not null default '[]'::jsonb,
  colour_direction jsonb not null default '[]'::jsonb,
  lighting_direction jsonb not null default '[]'::jsonb,
  furniture_direction jsonb not null default '[]'::jsonb,
  craft_references jsonb not null default '[]'::jsonb,
  sustainability_preferences jsonb not null default '[]'::jsonb,
  budget_band text,
  source_brief_refs jsonb not null default '[]'::jsonb,
  created_by uuid references auth.users(id),
  created_at timestamptz not null default now(),
  unique(project_id, version)
);

create table if not exists interiors.material_selections (
  id uuid primary key default gen_random_uuid(),
  project_id uuid not null references project.projects(id) on delete cascade,
  category text not null,
  material text not null,
  finish text,
  manufacturer text,
  product_code text,
  fire_rating text,
  slip_rating text,
  embodied_carbon numeric(18,6),
  cost_band text,
  source_reference text,
  approval_state text not null default 'proposed' check (approval_state in ('proposed','sample_requested','approved','rejected','substituted')),
  approved_by uuid references auth.users(id),
  approved_at timestamptz,
  created_at timestamptz not null default now()
);

create table if not exists interiors.room_packages (
  id uuid primary key default gen_random_uuid(),
  project_id uuid not null references project.projects(id) on delete cascade,
  room_type text not null,
  room_code citext,
  design_dna_id uuid not null references interiors.design_dna(id) on delete restrict,
  material_selection_ids jsonb not null default '[]'::jsonb,
  drawing_refs jsonb not null default '[]'::jsonb,
  render_refs jsonb not null default '[]'::jsonb,
  joinery_refs jsonb not null default '[]'::jsonb,
  lighting_refs jsonb not null default '[]'::jsonb,
  furniture_refs jsonb not null default '[]'::jsonb,
  status text not null default 'brief' check (status in ('brief','concept','design_development','shop_drawing','approved','installed')),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists engineering.structural_schemes (
  id uuid primary key default gen_random_uuid(),
  project_id uuid not null references project.projects(id) on delete cascade,
  version integer not null,
  system text not null,
  material_system text not null,
  grid_strategy jsonb,
  load_assumptions jsonb not null default '{}'::jsonb,
  design_standards jsonb not null default '[]'::jsonb,
  analysis_model_ref text,
  calculation_run_ids jsonb not null default '[]'::jsonb,
  model_refs jsonb not null default '[]'::jsonb,
  drawing_refs jsonb not null default '[]'::jsonb,
  status text not null default 'concept' check (status in ('concept','analysis','coordination','for_review','approved','issued')),
  created_by uuid references auth.users(id),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique(project_id, version)
);

create table if not exists engineering.mep_systems (
  id uuid primary key default gen_random_uuid(),
  project_id uuid not null references project.projects(id) on delete cascade,
  discipline text not null check (discipline in ('mechanical','electrical','plumbing','fire','elv','bms','vertical_transport')),
  system_code citext not null,
  name text not null,
  design_criteria jsonb not null default '{}'::jsonb,
  load_calculation_run_ids jsonb not null default '[]'::jsonb,
  equipment_selections jsonb not null default '[]'::jsonb,
  model_refs jsonb not null default '[]'::jsonb,
  drawing_refs jsonb not null default '[]'::jsonb,
  status text not null default 'criteria' check (status in ('criteria','sizing','coordination','for_review','approved','issued')),
  created_by uuid references auth.users(id),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique(project_id, system_code)
);

create table if not exists engineering.coordination_matrix (
  id uuid primary key default gen_random_uuid(),
  project_id uuid not null references project.projects(id) on delete cascade,
  source_discipline text not null,
  target_discipline text not null,
  subject text not null,
  requirement_ref text,
  issue_ref text,
  state text not null default 'open' check (state in ('open','coordinating','resolved','accepted_deviation')),
  owner_user_id uuid references auth.users(id),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create index if not exists engineering_runs_project_idx on engineering.calculation_runs(project_id, discipline, status);
create index if not exists engineering_reviews_project_idx on engineering.professional_reviews(project_id, resource_type, decision);
create index if not exists structural_schemes_project_idx on engineering.structural_schemes(project_id, version desc);
create index if not exists mep_systems_project_idx on engineering.mep_systems(project_id, discipline, status);
create index if not exists interiors_rooms_project_idx on interiors.room_packages(project_id, room_type, status);

alter table engineering.engines enable row level security;
alter table engineering.engine_benchmark_cases enable row level security;
alter table engineering.engine_benchmark_results enable row level security;
alter table engineering.calculation_runs enable row level security;
alter table engineering.professional_reviews enable row level security;
alter table engineering.architecture_packages enable row level security;
alter table interiors.design_dna enable row level security;
alter table interiors.material_selections enable row level security;
alter table interiors.room_packages enable row level security;
alter table engineering.structural_schemes enable row level security;
alter table engineering.mep_systems enable row level security;
alter table engineering.coordination_matrix enable row level security;

commit;
