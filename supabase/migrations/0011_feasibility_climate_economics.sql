-- Concept Spaces feasibility, typology, climate and development economics
-- Prepared for isolated Supabase activation.

create schema if not exists feasibility;

create table if not exists feasibility.typology_packs (
  id uuid primary key default gen_random_uuid(),
  code citext not null unique,
  name text not null,
  typology text not null,
  version integer not null default 1,
  jurisdiction_scope jsonb not null default '[]'::jsonb,
  programme_categories jsonb not null default '[]'::jsonb,
  amenity_patterns jsonb not null default '[]'::jsonb,
  planning_principles jsonb not null default '[]'::jsonb,
  operational_principles jsonb not null default '[]'::jsonb,
  engineering_considerations jsonb not null default '[]'::jsonb,
  sustainability_considerations jsonb not null default '[]'::jsonb,
  commercial_drivers jsonb not null default '[]'::jsonb,
  benchmark_sources jsonb not null default '[]'::jsonb,
  state text not null default 'draft' check (state in ('draft','review','published','retired')),
  approved_by uuid references auth.users(id),
  approved_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists feasibility.programme_briefs (
  id uuid primary key default gen_random_uuid(),
  project_id uuid not null references project.projects(id) on delete cascade,
  typology_pack_id uuid references feasibility.typology_packs(id) on delete set null,
  version integer not null default 1,
  client_priorities jsonb not null default '[]'::jsonb,
  exclusions jsonb not null default '[]'::jsonb,
  target_efficiency numeric(8,4),
  target_built_up_area numeric(18,4),
  budget_band text,
  status text not null default 'draft' check (status in ('draft','client_review','approved','superseded')),
  created_by uuid references auth.users(id),
  approved_by uuid references auth.users(id),
  approved_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique(project_id,version)
);

create table if not exists feasibility.programme_items (
  id uuid primary key default gen_random_uuid(),
  programme_brief_id uuid not null references feasibility.programme_briefs(id) on delete cascade,
  code citext not null,
  name text not null,
  category text not null,
  quantity numeric(18,4) not null default 1,
  unit_area numeric(18,4) not null,
  area_unit text not null check (area_unit in ('sqm','sqft')),
  net_area numeric(18,4) not null,
  grossing_factor numeric(10,6),
  gross_area numeric(18,4),
  adjacency_tags jsonb not null default '[]'::jsonb,
  mandatory boolean not null default false,
  source_ref text,
  confidence text not null check (confidence in ('A','B','C','D')),
  created_at timestamptz not null default now(),
  unique(programme_brief_id,code)
);

create table if not exists feasibility.climate_contexts (
  id uuid primary key default gen_random_uuid(),
  project_id uuid not null references project.projects(id) on delete cascade,
  latitude numeric(10,7) not null,
  longitude numeric(10,7) not null,
  elevation_m numeric(12,3),
  climate_zone text,
  weather_dataset_ref text,
  design_dry_bulb_c numeric(8,3),
  design_wet_bulb_c numeric(8,3),
  annual_rainfall_mm numeric(12,3),
  prevailing_wind_directions jsonb not null default '[]'::jsonb,
  solar_exposure_notes jsonb not null default '[]'::jsonb,
  flood_risk_class text,
  heat_risk_class text,
  air_quality_context text,
  source_refs jsonb not null default '[]'::jsonb,
  confidence text not null check (confidence in ('A','B','C','D')),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique(project_id)
);

create table if not exists feasibility.environmental_studies (
  id uuid primary key default gen_random_uuid(),
  project_id uuid not null references project.projects(id) on delete cascade,
  study_type text not null check (study_type in ('solar','daylight','shadow','wind','energy','thermal','water','flood','embodied_carbon','operational_carbon','air_quality')),
  state text not null default 'draft' check (state in ('draft','running','complete','failed','superseded')),
  engine_ref text,
  engine_version text,
  input_snapshot_ref text not null,
  assumptions jsonb not null default '[]'::jsonb,
  result_ref text,
  key_metrics jsonb not null default '{}'::jsonb,
  evidence_refs jsonb not null default '[]'::jsonb,
  confidence text not null check (confidence in ('A','B','C','D')),
  created_by uuid references auth.users(id),
  created_at timestamptz not null default now(),
  completed_at timestamptz
);

create table if not exists feasibility.precedent_principles (
  id uuid primary key default gen_random_uuid(),
  project_id uuid not null references project.projects(id) on delete cascade,
  typology text not null,
  source_ref text not null,
  geography text,
  principle text not null,
  rationale text not null,
  transferable boolean not null default true,
  copying_prohibited boolean not null default true,
  evidence_refs jsonb not null default '[]'::jsonb,
  created_at timestamptz not null default now()
);

create table if not exists feasibility.development_scenarios (
  id uuid primary key default gen_random_uuid(),
  project_id uuid not null references project.projects(id) on delete cascade,
  code citext not null,
  name text not null,
  programme_brief_id uuid not null references feasibility.programme_briefs(id) on delete restrict,
  design_option_id uuid,
  saleable_area numeric(18,4),
  leasable_area numeric(18,4),
  built_up_area numeric(18,4) not null,
  far_consumed numeric(18,4),
  ground_coverage_percent numeric(8,4),
  parking_count integer,
  capex_estimate numeric(20,4),
  revenue_estimate numeric(20,4),
  currency char(3) not null default 'INR',
  duration_months integer,
  assumptions_ref text not null,
  status text not null default 'draft' check (status in ('draft','evaluated','shortlisted','selected','rejected')),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique(project_id,code)
);

create table if not exists feasibility.economic_assumptions (
  id uuid primary key default gen_random_uuid(),
  scenario_id uuid not null references feasibility.development_scenarios(id) on delete cascade,
  category text not null check (category in ('land','construction','professional_fees','statutory','finance','marketing','operations','sales','rent','absorption','escalation','tax','other')),
  assumption_key text not null,
  value numeric(24,8) not null,
  unit text not null,
  source_ref text,
  confidence text not null check (confidence in ('A','B','C','D')),
  effective_date date,
  created_at timestamptz not null default now()
);

create table if not exists feasibility.scenario_metrics (
  id uuid primary key default gen_random_uuid(),
  scenario_id uuid not null references feasibility.development_scenarios(id) on delete cascade,
  total_development_cost numeric(20,4),
  gross_development_value numeric(20,4),
  net_operating_income numeric(20,4),
  development_margin_percent numeric(12,6),
  irr_percent numeric(12,6),
  npv numeric(20,4),
  payback_months numeric(12,3),
  residual_land_value numeric(20,4),
  cost_per_built_up_area numeric(20,4),
  value_per_built_up_area numeric(20,4),
  sensitivity_ref text,
  calculated_at timestamptz not null default now(),
  unique(scenario_id)
);

create table if not exists feasibility.value_engineering_options (
  id uuid primary key default gen_random_uuid(),
  project_id uuid not null references project.projects(id) on delete cascade,
  scenario_id uuid references feasibility.development_scenarios(id) on delete cascade,
  discipline text,
  proposal text not null,
  reason text not null,
  capex_impact numeric(20,4) not null default 0,
  opex_impact numeric(20,4),
  programme_impact_days integer,
  quality_impact text not null check (quality_impact in ('positive','neutral','negative')),
  carbon_impact text check (carbon_impact in ('positive','neutral','negative')),
  requirement_impact_refs jsonb not null default '[]'::jsonb,
  decision_state text not null default 'proposed' check (decision_state in ('proposed','review','accepted','rejected')),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

alter table feasibility.typology_packs enable row level security;
alter table feasibility.programme_briefs enable row level security;
alter table feasibility.programme_items enable row level security;
alter table feasibility.climate_contexts enable row level security;
alter table feasibility.environmental_studies enable row level security;
alter table feasibility.precedent_principles enable row level security;
alter table feasibility.development_scenarios enable row level security;
alter table feasibility.economic_assumptions enable row level security;
alter table feasibility.scenario_metrics enable row level security;
alter table feasibility.value_engineering_options enable row level security;

create index if not exists ix_programme_briefs_project on feasibility.programme_briefs(project_id,status);
create index if not exists ix_environmental_studies_project on feasibility.environmental_studies(project_id,study_type,state);
create index if not exists ix_development_scenarios_project on feasibility.development_scenarios(project_id,status);
create index if not exists ix_economic_assumptions_scenario on feasibility.economic_assumptions(scenario_id,category);
