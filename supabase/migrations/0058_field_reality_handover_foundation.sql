begin;

create table if not exists site.site_diaries(
  id uuid primary key default gen_random_uuid(),
  project_id uuid not null references project.projects(id) on delete cascade,
  diary_date date not null,
  weather jsonb not null default '{}'::jsonb,
  manpower jsonb not null default '[]'::jsonb,
  equipment jsonb not null default '[]'::jsonb,
  progress jsonb not null default '[]'::jsonb,
  photos jsonb not null default '[]'::jsonb,
  notes text,
  status text not null default 'draft' check(status in ('draft','submitted','approved')),
  captured_by uuid references auth.users(id),
  approved_by uuid references auth.users(id),
  approved_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique(project_id,diary_date)
);

create table if not exists site.offline_packages(
  id uuid primary key default gen_random_uuid(),
  project_id uuid not null references project.projects(id) on delete cascade,
  user_id uuid not null references auth.users(id) on delete cascade,
  source_snapshot jsonb not null,
  source_hash text not null,
  downloaded_at timestamptz not null default now(),
  expires_at timestamptz,
  status text not null default 'active' check(status in ('active','stale','expired','superseded')),
  created_at timestamptz not null default now()
);

create table if not exists site.offline_changes(
  id uuid primary key default gen_random_uuid(),
  offline_package_id uuid not null references site.offline_packages(id) on delete cascade,
  project_id uuid not null references project.projects(id) on delete cascade,
  user_id uuid not null references auth.users(id) on delete cascade,
  local_change_id text not null,
  entity_type text not null check(entity_type in ('site_diary','observation','inspection','rfi','photo_note')),
  payload jsonb not null,
  client_created_at timestamptz not null,
  status text not null default 'queued' check(status in ('queued','synced','conflict','discarded')),
  conflict_reason text,
  server_resource_id uuid,
  synced_at timestamptz,
  created_at timestamptz not null default now(),
  unique(offline_package_id,local_change_id)
);

create table if not exists site.progress_measurements(
  id uuid primary key default gen_random_uuid(),
  project_id uuid not null references project.projects(id) on delete cascade,
  activity_id uuid references site.activities(id) on delete set null,
  purchase_order_id uuid references procurement.purchase_orders(id) on delete set null,
  boq_line_id uuid references cost.boq_lines(id) on delete set null,
  location_ref text,
  measured_quantity numeric not null check(measured_quantity>=0),
  unit text not null,
  evidence_refs jsonb not null default '[]'::jsonb,
  source_revision_hash text,
  status text not null default 'draft' check(status in ('draft','certified','rejected')),
  measured_by uuid references auth.users(id),
  certified_by uuid references auth.users(id),
  certified_at timestamptz,
  created_at timestamptz not null default now()
);

create table if not exists site.variations(
  id uuid primary key default gen_random_uuid(),
  project_id uuid not null references project.projects(id) on delete cascade,
  purchase_order_id uuid references procurement.purchase_orders(id) on delete set null,
  variation_ref text not null,
  description text not null,
  amount numeric not null default 0,
  affected_boq_refs jsonb not null default '[]'::jsonb,
  evidence_refs jsonb not null default '[]'::jsonb,
  status text not null default 'proposed' check(status in ('proposed','approved','rejected','superseded')),
  decision_hash text,
  proposed_by uuid references auth.users(id),
  approved_by uuid references auth.users(id),
  approved_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique(project_id,variation_ref)
);

alter table site.observations add column if not exists offline_package_id uuid references site.offline_packages(id) on delete set null;
alter table site.observations add column if not exists source_model_id uuid references cde.models(id) on delete set null;
alter table site.observations add column if not exists source_revision_hash text;
alter table public.inspection_records add column if not exists offline_package_id uuid references site.offline_packages(id) on delete set null;
alter table public.inspection_records add column if not exists source_model_id uuid references cde.models(id) on delete set null;
alter table public.inspection_records add column if not exists source_revision_hash text;

alter table public.reality_captures add column if not exists model_id uuid references cde.models(id) on delete set null;
alter table public.reality_captures add column if not exists model_checksum text;
alter table public.reality_captures add column if not exists tolerance jsonb not null default '{}'::jsonb;
alter table public.reality_captures add column if not exists capture_provenance jsonb not null default '{}'::jsonb;
alter table public.reality_captures add column if not exists registration_hash text;
alter table public.reality_captures add column if not exists comparison_hash text;
alter table public.reality_deviations add column if not exists confidence numeric check(confidence is null or (confidence>=0 and confidence<=1));
alter table public.reality_deviations add column if not exists reviewed_by uuid references auth.users(id);
alter table public.reality_deviations add column if not exists reviewed_at timestamptz;
alter table public.reality_deviations add column if not exists linked_issue_id uuid references coordination.issues(id) on delete set null;

create table if not exists public.handover_items(
  id uuid primary key default gen_random_uuid(),
  project_id uuid not null references project.projects(id) on delete cascade,
  item_code text not null,
  category text not null check(category in ('as_built','document','commissioning','warranty','training','certificate','asset_data','material_passport','other')),
  title text not null,
  mandatory boolean not null default true,
  evidence_refs jsonb not null default '[]'::jsonb,
  status text not null default 'open' check(status in ('open','submitted','accepted','not_applicable')),
  submitted_by uuid references auth.users(id),
  accepted_by uuid references auth.users(id),
  accepted_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique(project_id,item_code)
);

create table if not exists public.handover_exceptions(
  id uuid primary key default gen_random_uuid(),
  project_id uuid not null references project.projects(id) on delete cascade,
  handover_item_id uuid not null references public.handover_items(id) on delete cascade,
  reason text not null,
  evidence_refs jsonb not null default '[]'::jsonb,
  status text not null default 'requested' check(status in ('requested','approved','rejected','withdrawn')),
  requested_by uuid references auth.users(id),
  decided_by uuid references auth.users(id),
  decided_at timestamptz,
  created_at timestamptz not null default now()
);

create table if not exists public.building_passports(
  id uuid primary key default gen_random_uuid(),
  project_id uuid not null references project.projects(id) on delete cascade,
  version integer not null,
  handover_snapshot jsonb not null,
  snapshot_hash text not null,
  mandatory_gap_refs jsonb not null default '[]'::jsonb,
  exception_refs jsonb not null default '[]'::jsonb,
  status text not null default 'compiled' check(status in ('compiled','issued','superseded')),
  compiled_by uuid references auth.users(id),
  issued_by uuid references auth.users(id),
  compiled_at timestamptz not null default now(),
  issued_at timestamptz,
  created_at timestamptz not null default now(),
  unique(project_id,version)
);

alter table public.asset_passports add column if not exists system_code text;
alter table public.asset_passports add column if not exists verified_by uuid references auth.users(id);
alter table public.asset_passports add column if not exists verified_at timestamptz;
alter table public.asset_passports add column if not exists source_building_passport_hash text;

create index if not exists offline_packages_project_user_idx on site.offline_packages(project_id,user_id,downloaded_at desc);
create index if not exists offline_changes_package_status_idx on site.offline_changes(offline_package_id,status);
create index if not exists progress_measurements_project_idx on site.progress_measurements(project_id,status,created_at desc);
create index if not exists variations_project_idx on site.variations(project_id,status,created_at desc);
create index if not exists reality_deviations_project_status_idx on public.reality_deviations(project_id,status,created_at desc);
create index if not exists handover_items_project_idx on public.handover_items(project_id,status,mandatory);
create index if not exists building_passports_project_idx on public.building_passports(project_id,version desc);

alter table site.site_diaries enable row level security;
alter table site.offline_packages enable row level security;
alter table site.offline_changes enable row level security;
alter table site.progress_measurements enable row level security;
alter table site.variations enable row level security;
alter table public.handover_items enable row level security;
alter table public.handover_exceptions enable row level security;
alter table public.building_passports enable row level security;

-- Read policies.
create policy site_diaries_read on site.site_diaries for select to authenticated using(project.can_access_project(project_id));
create policy offline_packages_read on site.offline_packages for select to authenticated using(user_id=auth.uid() or project.can_manage_project(project_id));
create policy offline_changes_read on site.offline_changes for select to authenticated using(user_id=auth.uid() or project.can_manage_project(project_id));
create policy progress_measurements_read on site.progress_measurements for select to authenticated using(project.can_access_project(project_id));
create policy variations_read on site.variations for select to authenticated using(project.can_access_project(project_id));
create policy handover_items_read on public.handover_items for select to authenticated using(project.can_access_project(project_id));
create policy handover_exceptions_read on public.handover_exceptions for select to authenticated using(project.can_access_project(project_id));
create policy building_passports_read on public.building_passports for select to authenticated using(project.can_access_project(project_id));

-- Guarded writes for existing and new field tables.
create policy site_diaries_insert on site.site_diaries for insert to authenticated with check(project.can_access_project(project_id) and captured_by=auth.uid() and current_setting('conceptspaces.site_phase',true)='diary');
create policy site_diaries_update on site.site_diaries for update to authenticated using(project.can_manage_project(project_id)) with check(project.can_manage_project(project_id) and current_setting('conceptspaces.site_phase',true)='diary_review');
create policy offline_packages_insert on site.offline_packages for insert to authenticated with check(project.can_access_project(project_id) and user_id=auth.uid() and current_setting('conceptspaces.site_phase',true)='offline_package');
create policy offline_packages_update on site.offline_packages for update to authenticated using(user_id=auth.uid() or project.can_manage_project(project_id)) with check(current_setting('conceptspaces.site_phase',true)='offline_sync');
create policy offline_changes_insert on site.offline_changes for insert to authenticated with check(user_id=auth.uid() and project.can_access_project(project_id) and current_setting('conceptspaces.site_phase',true)='offline_sync');
create policy offline_changes_update on site.offline_changes for update to authenticated using(user_id=auth.uid() or project.can_manage_project(project_id)) with check(current_setting('conceptspaces.site_phase',true)='offline_sync');
create policy progress_measurements_insert on site.progress_measurements for insert to authenticated with check(project.can_access_project(project_id) and measured_by=auth.uid() and current_setting('conceptspaces.site_phase',true)='progress');
create policy progress_measurements_update on site.progress_measurements for update to authenticated using(project.can_manage_project(project_id)) with check(project.can_manage_project(project_id) and current_setting('conceptspaces.site_phase',true)='progress_certify');
create policy variations_insert on site.variations for insert to authenticated with check(project.can_manage_project(project_id) and proposed_by=auth.uid() and current_setting('conceptspaces.site_phase',true)='variation');
create policy variations_update on site.variations for update to authenticated using(project.can_manage_project(project_id)) with check(project.can_manage_project(project_id) and current_setting('conceptspaces.site_phase',true)='variation_decide');

create policy activities_site_update on site.activities for update to authenticated using(project.can_manage_project(project_id)) with check(project.can_manage_project(project_id) and current_setting('conceptspaces.site_phase',true)='activity');
create policy activities_site_insert on site.activities for insert to authenticated with check(project.can_manage_project(project_id) and current_setting('conceptspaces.site_phase',true)='activity');
create policy observations_site_insert on site.observations for insert to authenticated with check(project.can_access_project(project_id) and observed_by=auth.uid() and current_setting('conceptspaces.site_phase',true) in ('observation','offline_sync'));
create policy observations_site_update on site.observations for update to authenticated using(project.can_manage_project(project_id)) with check(project.can_manage_project(project_id) and current_setting('conceptspaces.site_phase',true)='observation_review');

create policy itp_site_insert on public.inspection_test_plans for insert to authenticated with check(project.can_manage_project(project_id) and current_setting('conceptspaces.site_phase',true)='itp');
create policy itp_site_update on public.inspection_test_plans for update to authenticated using(project.can_manage_project(project_id)) with check(project.can_manage_project(project_id) and current_setting('conceptspaces.site_phase',true)='itp');
create policy inspection_site_insert on public.inspection_records for insert to authenticated with check(project.can_access_project(project_id) and inspector_user_id=auth.uid() and current_setting('conceptspaces.site_phase',true) in ('inspection','offline_sync'));
create policy inspection_site_update on public.inspection_records for update to authenticated using(project.can_manage_project(project_id)) with check(project.can_manage_project(project_id) and current_setting('conceptspaces.site_phase',true)='inspection_review');
create policy ncr_site_insert on public.non_conformances for insert to authenticated with check(project.can_access_project(project_id) and current_setting('conceptspaces.site_phase',true) in ('ncr','inspection','reality'));
create policy ncr_site_update on public.non_conformances for update to authenticated using(project.can_manage_project(project_id)) with check(project.can_manage_project(project_id) and current_setting('conceptspaces.site_phase',true)='ncr');

create policy reality_capture_insert on public.reality_captures for insert to authenticated with check(project.can_access_project(project_id) and captured_by=auth.uid() and current_setting('conceptspaces.reality_phase',true)='capture');
create policy reality_capture_update on public.reality_captures for update to authenticated using(project.can_manage_project(project_id)) with check(project.can_manage_project(project_id) and current_setting('conceptspaces.reality_phase',true)='compare');
create policy reality_deviation_insert on public.reality_deviations for insert to authenticated with check(project.can_manage_project(project_id) and current_setting('conceptspaces.reality_phase',true)='compare');
create policy reality_deviation_update on public.reality_deviations for update to authenticated using(project.can_manage_project(project_id)) with check(project.can_manage_project(project_id) and current_setting('conceptspaces.reality_phase',true)='review');

create policy handover_items_insert on public.handover_items for insert to authenticated with check(project.can_manage_project(project_id) and current_setting('conceptspaces.handover_phase',true)='item');
create policy handover_items_update on public.handover_items for update to authenticated using(project.can_manage_project(project_id)) with check(project.can_manage_project(project_id) and current_setting('conceptspaces.handover_phase',true)='item');
create policy handover_exceptions_insert on public.handover_exceptions for insert to authenticated with check(project.can_access_project(project_id) and requested_by=auth.uid() and current_setting('conceptspaces.handover_phase',true)='exception');
create policy handover_exceptions_update on public.handover_exceptions for update to authenticated using(project.can_manage_project(project_id)) with check(project.can_manage_project(project_id) and current_setting('conceptspaces.handover_phase',true)='exception_decide');
create policy building_passports_insert on public.building_passports for insert to authenticated with check(project.can_manage_project(project_id) and compiled_by=auth.uid() and current_setting('conceptspaces.handover_phase',true)='compile');
create policy building_passports_update on public.building_passports for update to authenticated using(project.can_manage_project(project_id)) with check(project.can_manage_project(project_id) and current_setting('conceptspaces.handover_phase',true)='issue');
create policy asset_passports_write on public.asset_passports for all to authenticated using(project.can_manage_project(project_id)) with check(project.can_manage_project(project_id) and current_setting('conceptspaces.handover_phase',true) in ('asset','asset_verify'));
create policy commissioning_records_write on public.commissioning_records for all to authenticated using(project.can_manage_project(project_id)) with check(project.can_manage_project(project_id) and current_setting('conceptspaces.handover_phase',true)='commissioning');
create policy maintenance_work_orders_write on public.maintenance_work_orders for all to authenticated using(project.can_access_project(project_id)) with check(project.can_access_project(project_id) and current_setting('conceptspaces.handover_phase',true)='maintenance');
create policy twin_bindings_write on public.twin_bindings for all to authenticated using(project.can_manage_project(project_id)) with check(project.can_manage_project(project_id) and current_setting('conceptspaces.handover_phase',true)='twin');

grant select,insert,update on site.site_diaries,site.offline_packages,site.offline_changes,site.progress_measurements,site.variations to authenticated;
grant insert,update on site.activities,site.observations to authenticated;
grant insert,update on public.inspection_test_plans,public.inspection_records,public.non_conformances,public.reality_captures,public.reality_deviations,public.handover_items,public.handover_exceptions,public.building_passports,public.asset_passports,public.commissioning_records,public.maintenance_work_orders,public.twin_bindings to authenticated;
grant select on public.handover_items,public.handover_exceptions,public.building_passports to authenticated;

commit;