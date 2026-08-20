begin;

create schema if not exists cost;
create schema if not exists procurement;
create schema if not exists site;
create schema if not exists asset;

create table if not exists cost.quantity_items (
  id uuid primary key default gen_random_uuid(),
  project_id uuid not null references project.projects(id) on delete cascade,
  code citext not null,
  description text not null,
  discipline text not null,
  unit text not null,
  quantity numeric(20,6) not null,
  source text not null check (source in ('model','drawing','manual','hybrid')),
  source_reference text,
  confidence text not null check (confidence in ('A','B','C','D')),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique(project_id, code)
);

create table if not exists cost.cost_plans (
  id uuid primary key default gen_random_uuid(),
  project_id uuid not null references project.projects(id) on delete cascade,
  version integer not null,
  stage text not null,
  currency text not null default 'INR',
  contingencies numeric(18,2) not null default 0,
  professional_fees numeric(18,2) not null default 0,
  taxes numeric(18,2) not null default 0,
  total numeric(18,2) not null default 0,
  confidence text not null check (confidence in ('A','B','C','D')),
  basis_date date not null,
  status text not null default 'draft' check (status in ('draft','for_review','approved','superseded')),
  created_by uuid references auth.users(id),
  approved_by uuid references auth.users(id),
  approved_at timestamptz,
  created_at timestamptz not null default now(),
  unique(project_id, version)
);

create table if not exists cost.boq_lines (
  id uuid primary key default gen_random_uuid(),
  cost_plan_id uuid not null references cost.cost_plans(id) on delete cascade,
  quantity_item_id uuid references cost.quantity_items(id) on delete set null,
  code citext not null,
  description text not null,
  unit text not null,
  quantity numeric(20,6) not null,
  rate numeric(18,4) not null default 0,
  currency text not null default 'INR',
  material_amount numeric(18,2) not null default 0,
  labour_amount numeric(18,2) not null default 0,
  equipment_amount numeric(18,2) not null default 0,
  wastage_percent numeric(8,4) not null default 0,
  tax_amount numeric(18,2) not null default 0,
  total numeric(18,2) not null default 0,
  confidence text not null check (confidence in ('A','B','C','D'))
);

create table if not exists procurement.vendors (
  id uuid primary key default gen_random_uuid(),
  organisation_id uuid not null references core.organisations(id) on delete cascade,
  legal_name text not null,
  display_name text,
  gstin text,
  pan text,
  udyam_number text,
  categories jsonb not null default '[]'::jsonb,
  kyc_status text not null default 'pending' check (kyc_status in ('pending','verified','rejected','expired')),
  status text not null default 'active' check (status in ('active','suspended','blacklisted')),
  metadata jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists procurement.tender_packages (
  id uuid primary key default gen_random_uuid(),
  project_id uuid not null references project.projects(id) on delete cascade,
  package_code citext not null,
  title text not null,
  scope_refs jsonb not null default '[]'::jsonb,
  status text not null default 'draft' check (status in ('draft','rfq','bid_received','evaluation','awarded','contracted','closed')),
  bid_due_at timestamptz,
  created_by uuid references auth.users(id),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique(project_id, package_code)
);

create table if not exists procurement.tender_boq_lines (
  tender_package_id uuid not null references procurement.tender_packages(id) on delete cascade,
  boq_line_id uuid not null references cost.boq_lines(id) on delete restrict,
  primary key(tender_package_id, boq_line_id)
);

create table if not exists procurement.tender_invites (
  id uuid primary key default gen_random_uuid(),
  tender_package_id uuid not null references procurement.tender_packages(id) on delete cascade,
  vendor_id uuid not null references procurement.vendors(id) on delete restrict,
  invited_at timestamptz not null default now(),
  viewed_at timestamptz,
  declined_at timestamptz,
  unique(tender_package_id, vendor_id)
);

create table if not exists procurement.bids (
  id uuid primary key default gen_random_uuid(),
  tender_package_id uuid not null references procurement.tender_packages(id) on delete cascade,
  vendor_id uuid not null references procurement.vendors(id) on delete restrict,
  currency text not null default 'INR',
  total numeric(18,2) not null default 0,
  commercial_deviations jsonb not null default '[]'::jsonb,
  technical_deviations jsonb not null default '[]'::jsonb,
  status text not null default 'submitted' check (status in ('draft','submitted','clarification','evaluated','selected','rejected','withdrawn')),
  submitted_at timestamptz,
  created_at timestamptz not null default now()
);

create table if not exists procurement.bid_lines (
  id uuid primary key default gen_random_uuid(),
  bid_id uuid not null references procurement.bids(id) on delete cascade,
  boq_line_id uuid not null references cost.boq_lines(id) on delete restrict,
  quantity numeric(20,6) not null,
  rate numeric(18,4) not null,
  total numeric(18,2) not null,
  exclusions jsonb not null default '[]'::jsonb,
  unique(bid_id, boq_line_id)
);

create table if not exists site.activities (
  id uuid primary key default gen_random_uuid(),
  project_id uuid not null references project.projects(id) on delete cascade,
  wbs_code citext not null,
  title text not null,
  state text not null default 'not_started' check (state in ('not_started','in_progress','blocked','complete')),
  planned_start date,
  planned_finish date,
  actual_start date,
  actual_finish date,
  progress_percent numeric(6,3) not null default 0 check (progress_percent between 0 and 100),
  contractor_vendor_id uuid references procurement.vendors(id) on delete set null,
  evidence_refs jsonb not null default '[]'::jsonb,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique(project_id, wbs_code)
);

create table if not exists site.observations (
  id uuid primary key default gen_random_uuid(),
  project_id uuid not null references project.projects(id) on delete cascade,
  observation_number citext not null,
  observation_type text not null check (observation_type in ('progress','quality','safety','material','non_conformance','inspection')),
  title text not null,
  description text not null,
  location_ref text,
  media_refs jsonb not null default '[]'::jsonb,
  related_model_object_refs jsonb not null default '[]'::jsonb,
  criticality text not null default 'C1' check (criticality in ('C0','C1','C2','C3','C4')),
  status text not null default 'open' check (status in ('open','actioned','verified','closed')),
  observed_by uuid references auth.users(id),
  observed_at timestamptz not null default now(),
  verified_by uuid references auth.users(id),
  verified_at timestamptz,
  unique(project_id, observation_number)
);

create table if not exists site.reality_captures (
  id uuid primary key default gen_random_uuid(),
  project_id uuid not null references project.projects(id) on delete cascade,
  capture_type text not null check (capture_type in ('photo','360','drone','point_cloud','lidar')),
  capture_ref text not null,
  model_ref text,
  comparison_status text not null default 'queued' check (comparison_status in ('queued','processing','review_required','accepted','failed')),
  deviations jsonb not null default '[]'::jsonb,
  captured_by uuid references auth.users(id),
  captured_at timestamptz not null,
  created_at timestamptz not null default now()
);

create table if not exists asset.passports (
  id uuid primary key default gen_random_uuid(),
  project_id uuid not null references project.projects(id) on delete cascade,
  asset_code citext not null,
  asset_type text not null,
  manufacturer text,
  model text,
  serial_number text,
  install_location text,
  warranty_from date,
  warranty_until date,
  maintenance_plan jsonb,
  document_refs jsonb not null default '[]'::jsonb,
  commissioning_refs jsonb not null default '[]'::jsonb,
  metadata jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique(project_id, asset_code)
);

create index if not exists quantity_items_project_idx on cost.quantity_items(project_id, discipline);
create index if not exists cost_plans_project_idx on cost.cost_plans(project_id, version desc);
create index if not exists tender_packages_project_idx on procurement.tender_packages(project_id, status);
create index if not exists site_activities_project_idx on site.activities(project_id, state);
create index if not exists site_observations_project_idx on site.observations(project_id, status, criticality);
create index if not exists asset_passports_project_idx on asset.passports(project_id, asset_type);

alter table cost.quantity_items enable row level security;
alter table cost.cost_plans enable row level security;
alter table cost.boq_lines enable row level security;
alter table procurement.vendors enable row level security;
alter table procurement.tender_packages enable row level security;
alter table procurement.tender_boq_lines enable row level security;
alter table procurement.tender_invites enable row level security;
alter table procurement.bids enable row level security;
alter table procurement.bid_lines enable row level security;
alter table site.activities enable row level security;
alter table site.observations enable row level security;
alter table site.reality_captures enable row level security;
alter table asset.passports enable row level security;

commit;
