begin;

create table if not exists public.inspection_test_plans (
  id uuid primary key default gen_random_uuid(), project_id uuid not null, code text not null, work_package text not null,
  activity text not null, acceptance_criteria jsonb not null default '[]'::jsonb, reference_documents jsonb not null default '[]'::jsonb,
  hold_points jsonb not null default '[]'::jsonb, witness_points jsonb not null default '[]'::jsonb, responsible_party text not null,
  approved_by uuid, status text not null default 'draft' check (status in ('draft','approved','superseded')),
  created_at timestamptz not null default now(), updated_at timestamptz not null default now(), unique(project_id, code)
);

create table if not exists public.inspection_records (
  id uuid primary key default gen_random_uuid(), project_id uuid not null, itp_id uuid not null references public.inspection_test_plans(id),
  activity_ref text, location_ref text, inspected_at timestamptz not null, inspector_user_id uuid not null,
  result text not null check (result in ('pass','pass_with_comments','fail')), measurements jsonb not null default '{}'::jsonb,
  media_refs jsonb not null default '[]'::jsonb, evidence_refs jsonb not null default '[]'::jsonb,
  non_conformance_id uuid, reviewer_user_id uuid, verified_at timestamptz, created_at timestamptz not null default now()
);

create table if not exists public.non_conformances (
  id uuid primary key default gen_random_uuid(), project_id uuid not null, number text not null, title text not null, description text not null,
  criticality text not null check (criticality in ('C0','C1','C2','C3','C4')), location_ref text, source_observation_id uuid,
  source_inspection_id uuid references public.inspection_records(id) on delete set null, affected_object_refs jsonb not null default '[]'::jsonb,
  contractor_id uuid, disposition text not null default 'pending' check (disposition in ('pending','repair','replace','use_as_is','redesign')),
  status text not null default 'open' check (status in ('open','corrective_action','verification','closed')), root_cause text,
  corrective_action text, approved_deviation_by uuid, closed_by uuid, closed_at timestamptz,
  created_at timestamptz not null default now(), updated_at timestamptz not null default now(), unique(project_id, number)
);

create table if not exists public.site_changes (
  id uuid primary key default gen_random_uuid(), project_id uuid not null, number text not null, title text not null, reason text not null,
  source text not null, affected_requirement_refs jsonb not null default '[]'::jsonb, affected_document_refs jsonb not null default '[]'::jsonb,
  affected_model_object_refs jsonb not null default '[]'::jsonb, cost_impact numeric(18,2), schedule_impact_days integer,
  criticality text not null check (criticality in ('C0','C1','C2','C3','C4')),
  status text not null default 'raised' check (status in ('raised','impact_assessment','approval','approved','rejected','implemented')),
  approved_by uuid, created_at timestamptz not null default now(), updated_at timestamptz not null default now(), unique(project_id, number)
);

create table if not exists public.progress_claims (
  id uuid primary key default gen_random_uuid(), project_id uuid not null, contractor_id uuid not null, period_from date not null, period_to date not null,
  currency text not null default 'INR', gross_claim numeric(18,2) not null default 0, certified_work numeric(18,2) not null default 0,
  material_on_site numeric(18,2) not null default 0, retention numeric(18,2) not null default 0, deductions numeric(18,2) not null default 0,
  tax numeric(18,2) not null default 0, certified_payable numeric(18,2) not null default 0, evidence_refs jsonb not null default '[]'::jsonb,
  status text not null default 'draft' check (status in ('draft','submitted','review','certified','rejected','paid')), certified_by uuid,
  created_at timestamptz not null default now(), updated_at timestamptz not null default now()
);

create table if not exists public.reality_captures (
  id uuid primary key default gen_random_uuid(), project_id uuid not null, capture_type text not null check (capture_type in ('photo','360','drone','point_cloud','lidar')),
  capture_ref text not null, model_ref text, coordinate_system text, comparison_status text not null default 'queued' check (comparison_status in ('queued','processing','review_required','accepted','failed')),
  captured_at timestamptz not null, captured_by uuid, reviewed_by uuid, reviewed_at timestamptz, created_at timestamptz not null default now()
);

create table if not exists public.reality_deviations (
  id uuid primary key default gen_random_uuid(), comparison_id uuid not null references public.reality_captures(id) on delete cascade, project_id uuid not null,
  model_object_ref text, location_ref text, deviation_type text not null check (deviation_type in ('position','dimension','missing','unexpected','finish','progress','quality')),
  measured_value numeric, permitted_tolerance numeric, unit text, severity text not null check (severity in ('informational','minor','major','critical')),
  status text not null default 'detected' check (status in ('detected','review','accepted','ncr_raised','resolved')), evidence_refs jsonb not null default '[]'::jsonb,
  disposition_by uuid, created_at timestamptz not null default now(), updated_at timestamptz not null default now()
);

create table if not exists public.commissioning_records (
  id uuid primary key default gen_random_uuid(), project_id uuid not null, system_code text not null, asset_code text, test_type text not null,
  procedure_ref text not null, test_date date not null, result text not null check (result in ('pass','conditional','fail')),
  readings jsonb not null default '{}'::jsonb, witness_user_ids jsonb not null default '[]'::jsonb, evidence_refs jsonb not null default '[]'::jsonb,
  defects jsonb not null default '[]'::jsonb, accepted_by uuid, accepted_at timestamptz, created_at timestamptz not null default now()
);

create table if not exists public.asset_passports (
  id uuid primary key default gen_random_uuid(), project_id uuid not null, asset_code text not null, asset_type text not null, manufacturer text,
  model text, serial_number text, install_location text, model_object_ref text, warranty_from date, warranty_until date,
  maintenance_plan jsonb not null default '{}'::jsonb, document_refs jsonb not null default '[]'::jsonb, commissioning_refs jsonb not null default '[]'::jsonb,
  operational_status text not null default 'planned' check (operational_status in ('planned','installed','commissioned','active','retired')),
  created_at timestamptz not null default now(), updated_at timestamptz not null default now(), unique(project_id, asset_code)
);

create table if not exists public.material_passports (
  id uuid primary key default gen_random_uuid(), project_id uuid not null, material_code text not null, name text not null, manufacturer text,
  product_code text, batch_ref text, install_locations jsonb not null default '[]'::jsonb, quantity numeric, unit text, embodied_carbon numeric,
  recycled_content_percent numeric, warranty_until date, maintenance_requirements jsonb not null default '[]'::jsonb, end_of_life_route text,
  evidence_refs jsonb not null default '[]'::jsonb, created_at timestamptz not null default now(), unique(project_id, material_code)
);

create table if not exists public.twin_bindings (
  id uuid primary key default gen_random_uuid(), project_id uuid not null, asset_passport_id uuid not null references public.asset_passports(id) on delete cascade,
  provider_key text not null, external_asset_ref text not null, telemetry_schema jsonb not null default '{}'::jsonb,
  status text not null default 'configured' check (status in ('configured','verified','degraded','disabled')), last_seen_at timestamptz,
  created_at timestamptz not null default now(), updated_at timestamptz not null default now(), unique(asset_passport_id, provider_key)
);

create table if not exists public.maintenance_work_orders (
  id uuid primary key default gen_random_uuid(), project_id uuid not null, asset_passport_id uuid references public.asset_passports(id) on delete set null,
  title text not null, type text not null check (type in ('preventive','predictive','corrective','statutory')),
  priority text not null default 'medium' check (priority in ('low','medium','high','critical')), due_at timestamptz, assignee_ref text,
  status text not null default 'open' check (status in ('open','scheduled','in_progress','verification','closed')),
  evidence_refs jsonb not null default '[]'::jsonb, closed_at timestamptz, created_at timestamptz not null default now(), updated_at timestamptz not null default now()
);

create index if not exists inspections_project_time_idx on public.inspection_records(project_id, inspected_at desc);
create index if not exists ncr_project_status_idx on public.non_conformances(project_id, status, criticality);
create index if not exists site_changes_project_status_idx on public.site_changes(project_id, status);
create index if not exists reality_captures_project_time_idx on public.reality_captures(project_id, captured_at desc);
create index if not exists reality_deviations_project_status_idx on public.reality_deviations(project_id, status, severity);
create index if not exists commissioning_project_asset_idx on public.commissioning_records(project_id, asset_code);
create index if not exists maintenance_project_status_idx on public.maintenance_work_orders(project_id, status, due_at);

alter table public.inspection_test_plans enable row level security;
alter table public.inspection_records enable row level security;
alter table public.non_conformances enable row level security;
alter table public.site_changes enable row level security;
alter table public.progress_claims enable row level security;
alter table public.reality_captures enable row level security;
alter table public.reality_deviations enable row level security;
alter table public.commissioning_records enable row level security;
alter table public.asset_passports enable row level security;
alter table public.material_passports enable row level security;
alter table public.twin_bindings enable row level security;
alter table public.maintenance_work_orders enable row level security;

commit;
