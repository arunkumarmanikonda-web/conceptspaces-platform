begin;

create table if not exists aec.programme_baselines(
 id uuid primary key default gen_random_uuid(),
 project_id uuid not null references project.projects(id) on delete cascade,
 version integer not null,
 title text not null,
 source_refs jsonb not null default '[]'::jsonb,
 status text not null default 'draft' check(status in ('draft','approved','superseded')),
 programme_hash text not null,
 created_by uuid references auth.users(id),
 approved_by uuid references auth.users(id),
 approved_at timestamptz,
 created_at timestamptz not null default now(),
 updated_at timestamptz not null default now(),
 unique(project_id,version)
);

create table if not exists aec.programme_items(
 id uuid primary key default gen_random_uuid(),
 programme_baseline_id uuid not null references aec.programme_baselines(id) on delete cascade,
 project_id uuid not null references project.projects(id) on delete cascade,
 code text not null,
 space_type text not null,
 zone text,
 quantity numeric not null check(quantity>0),
 target_area_each numeric check(target_area_each is null or target_area_each>=0),
 area_unit text not null default 'sqm',
 capacity numeric check(capacity is null or capacity>=0),
 adjacency jsonb not null default '[]'::jsonb,
 operational_rules jsonb not null default '{}'::jsonb,
 priority text not null default 'must' check(priority in ('must','should','could')),
 source_ref text not null,
 confidence text not null default 'C' check(confidence in ('A','B','C','D')),
 notes text,
 item_hash text not null,
 created_at timestamptz not null default now(),
 unique(programme_baseline_id,code)
);

create table if not exists aec.climate_studies(
 id uuid primary key default gen_random_uuid(),
 project_id uuid not null references project.projects(id) on delete cascade,
 study_type text not null check(study_type in ('sun_path','solar','shadow','daylight','glare','ventilation','wind','energy','water','flood','embodied_carbon','other')),
 title text not null,
 source_model_ref text,
 source_model_hash text,
 weather_source_ref text,
 engine_ref text not null,
 engine_version text not null,
 method_ref text not null,
 input_snapshot jsonb not null default '{}'::jsonb,
 result_summary jsonb not null default '{}'::jsonb,
 evidence_refs jsonb not null default '[]'::jsonb,
 input_hash text not null,
 output_hash text not null,
 confidence text not null default 'C' check(confidence in ('A','B','C','D')),
 status text not null default 'completed' check(status in ('completed','reviewed','approved','rejected','failed','superseded')),
 created_by uuid references auth.users(id),
 reviewed_by uuid references auth.users(id),
 reviewed_at timestamptz,
 approved_by uuid references auth.users(id),
 approved_at timestamptz,
 created_at timestamptz not null default now(),
 updated_at timestamptz not null default now()
);

create table if not exists aec.economic_scenarios(
 id uuid primary key default gen_random_uuid(),
 project_id uuid not null references project.projects(id) on delete cascade,
 name text not null,
 version integer not null,
 assumptions jsonb not null default '{}'::jsonb,
 assumption_sources jsonb not null default '{}'::jsonb,
 metrics jsonb not null default '{}'::jsonb,
 sensitivity jsonb not null default '{}'::jsonb,
 calculation_ref text not null,
 model_version text not null,
 input_hash text not null,
 output_hash text not null,
 confidence text not null default 'C' check(confidence in ('A','B','C','D')),
 status text not null default 'draft' check(status in ('draft','reviewed','selected','superseded','rejected')),
 created_by uuid references auth.users(id),
 reviewed_by uuid references auth.users(id),
 reviewed_at timestamptz,
 selected_by uuid references auth.users(id),
 selected_at timestamptz,
 created_at timestamptz not null default now(),
 updated_at timestamptz not null default now(),
 unique(project_id,name,version)
);

create table if not exists aec.interior_dna(
 id uuid primary key default gen_random_uuid(),
 project_id uuid not null references project.projects(id) on delete cascade,
 version integer not null,
 narrative text not null,
 palette jsonb not null default '[]'::jsonb,
 material_rules jsonb not null default '[]'::jsonb,
 lighting_rules jsonb not null default '[]'::jsonb,
 joinery_rules jsonb not null default '[]'::jsonb,
 ffe_rules jsonb not null default '[]'::jsonb,
 prohibited_elements jsonb not null default '[]'::jsonb,
 source_refs jsonb not null default '[]'::jsonb,
 confidence text not null default 'C' check(confidence in ('A','B','C','D')),
 status text not null default 'draft' check(status in ('draft','review','approved','superseded','rejected')),
 dna_hash text not null,
 created_by uuid references auth.users(id),
 approved_by uuid references auth.users(id),
 approved_at timestamptz,
 created_at timestamptz not null default now(),
 updated_at timestamptz not null default now(),
 unique(project_id,version)
);

create table if not exists aec.interior_room_packages(
 id uuid primary key default gen_random_uuid(),
 project_id uuid not null references project.projects(id) on delete cascade,
 dna_id uuid not null references aec.interior_dna(id) on delete restrict,
 space_ref text not null,
 version integer not null,
 design_revision_ref text not null,
 model_revision_hash text not null,
 layout_refs jsonb not null default '[]'::jsonb,
 elevation_refs jsonb not null default '[]'::jsonb,
 finishes jsonb not null default '[]'::jsonb,
 lighting jsonb not null default '[]'::jsonb,
 furniture jsonb not null default '[]'::jsonb,
 visualisation_refs jsonb not null default '[]'::jsonb,
 drawing_refs jsonb not null default '[]'::jsonb,
 boq_refs jsonb not null default '[]'::jsonb,
 coordination_checks jsonb not null default '[]'::jsonb,
 status text not null default 'draft' check(status in ('draft','coordinating','for_review','approved','issued','superseded','rejected')),
 package_hash text not null,
 created_by uuid references auth.users(id),
 approved_by uuid references auth.users(id),
 approved_at timestamptz,
 issued_by uuid references auth.users(id),
 issued_at timestamptz,
 created_at timestamptz not null default now(),
 updated_at timestamptz not null default now(),
 unique(project_id,space_ref,version)
);

create table if not exists aec.interior_material_selections(
 id uuid primary key default gen_random_uuid(),
 project_id uuid not null references project.projects(id) on delete cascade,
 dna_id uuid not null references aec.interior_dna(id) on delete restrict,
 room_package_id uuid references aec.interior_room_packages(id) on delete set null,
 base_selection_id uuid references aec.interior_material_selections(id) on delete set null,
 material_code text not null,
 product_ref text,
 source_ref text not null,
 specification jsonb not null default '{}'::jsonb,
 cost_amount numeric,
 currency text not null default 'INR',
 lead_time_days numeric,
 performance jsonb not null default '{}'::jsonb,
 sustainability jsonb not null default '{}'::jsonb,
 substitution_delta jsonb not null default '{}'::jsonb,
 approved_deviation_ref text,
 status text not null default 'proposed' check(status in ('proposed','approved','rejected','locked','superseded')),
 selection_hash text not null,
 created_by uuid references auth.users(id),
 approved_by uuid references auth.users(id),
 approved_at timestamptz,
 created_at timestamptz not null default now(),
 updated_at timestamptz not null default now()
);

create table if not exists aec.interior_shop_drawings(
 id uuid primary key default gen_random_uuid(),
 project_id uuid not null references project.projects(id) on delete cascade,
 room_package_id uuid not null references aec.interior_room_packages(id) on delete restrict,
 component_ref text not null,
 version integer not null,
 dimensional_source_ref text not null,
 dimensional_source_hash text not null,
 drawing_refs jsonb not null default '[]'::jsonb,
 detail_refs jsonb not null default '[]'::jsonb,
 hardware_refs jsonb not null default '[]'::jsonb,
 tolerances jsonb not null default '{}'::jsonb,
 boq_refs jsonb not null default '[]'::jsonb,
 coordination_checks jsonb not null default '[]'::jsonb,
 status text not null default 'draft' check(status in ('draft','vendor_review','designer_review','approved','issued','superseded','rejected')),
 drawing_hash text not null,
 created_by uuid references auth.users(id),
 approved_by uuid references auth.users(id),
 approved_at timestamptz,
 issued_by uuid references auth.users(id),
 issued_at timestamptz,
 created_at timestamptz not null default now(),
 updated_at timestamptz not null default now(),
 unique(project_id,component_ref,version)
);

alter table engineering.architecture_packages add column if not exists supersedes_package_id uuid references engineering.architecture_packages(id) on delete set null;
alter table engineering.architecture_packages add column if not exists package_hash text;
alter table engineering.architecture_packages add column if not exists source_model_hash text;
alter table engineering.architecture_packages add column if not exists review_evidence_refs jsonb not null default '[]'::jsonb;
alter table engineering.architecture_packages add column if not exists approved_by uuid references auth.users(id);
alter table engineering.architecture_packages add column if not exists approved_at timestamptz;
alter table engineering.architecture_packages add column if not exists issued_by uuid references auth.users(id);
alter table engineering.architecture_packages add column if not exists issued_at timestamptz;

alter table engineering.structural_schemes add column if not exists supersedes_scheme_id uuid references engineering.structural_schemes(id) on delete set null;
alter table engineering.structural_schemes add column if not exists source_architecture_package_id uuid references engineering.architecture_packages(id) on delete restrict;
alter table engineering.structural_schemes add column if not exists source_architecture_hash text;
alter table engineering.structural_schemes add column if not exists scheme_hash text;
alter table engineering.structural_schemes add column if not exists convergence_status text not null default 'not_run' check(convergence_status in ('not_run','converged','non_converged','failed'));
alter table engineering.structural_schemes add column if not exists review_evidence_refs jsonb not null default '[]'::jsonb;
alter table engineering.structural_schemes add column if not exists approved_by uuid references auth.users(id);
alter table engineering.structural_schemes add column if not exists approved_at timestamptz;
alter table engineering.structural_schemes add column if not exists issued_by uuid references auth.users(id);
alter table engineering.structural_schemes add column if not exists issued_at timestamptz;

alter table aec.programme_baselines enable row level security;
alter table aec.programme_items enable row level security;
alter table aec.climate_studies enable row level security;
alter table aec.economic_scenarios enable row level security;
alter table aec.interior_dna enable row level security;
alter table aec.interior_room_packages enable row level security;
alter table aec.interior_material_selections enable row level security;
alter table aec.interior_shop_drawings enable row level security;

grant select,insert,update on aec.programme_baselines,aec.programme_items,aec.climate_studies,aec.economic_scenarios,aec.interior_dna,aec.interior_room_packages,aec.interior_material_selections,aec.interior_shop_drawings to authenticated;
grant insert,update on engineering.architecture_packages,engineering.structural_schemes to authenticated;

create policy programme_baselines_read on aec.programme_baselines for select to authenticated using(project.can_access_project(project_id));
create policy programme_baselines_insert on aec.programme_baselines for insert to authenticated with check(project.can_manage_project(project_id) and current_setting('conceptspaces.design_phase',true)='programme');
create policy programme_baselines_update on aec.programme_baselines for update to authenticated using(project.can_manage_project(project_id)) with check(project.can_manage_project(project_id) and current_setting('conceptspaces.design_phase',true)='programme');
create policy programme_items_read on aec.programme_items for select to authenticated using(project.can_access_project(project_id));
create policy programme_items_insert on aec.programme_items for insert to authenticated with check(project.can_manage_project(project_id) and current_setting('conceptspaces.design_phase',true)='programme');

create policy climate_studies_read on aec.climate_studies for select to authenticated using(project.can_access_project(project_id));
create policy climate_studies_insert on aec.climate_studies for insert to authenticated with check(project.can_manage_project(project_id) and current_setting('conceptspaces.design_phase',true)='climate');
create policy climate_studies_update on aec.climate_studies for update to authenticated using(project.can_manage_project(project_id)) with check(project.can_manage_project(project_id) and current_setting('conceptspaces.design_phase',true)='climate');

create policy economic_scenarios_read on aec.economic_scenarios for select to authenticated using(project.can_access_project(project_id));
create policy economic_scenarios_insert on aec.economic_scenarios for insert to authenticated with check(project.can_manage_project(project_id) and current_setting('conceptspaces.design_phase',true)='economics');
create policy economic_scenarios_update on aec.economic_scenarios for update to authenticated using(project.can_manage_project(project_id)) with check(project.can_manage_project(project_id) and current_setting('conceptspaces.design_phase',true)='economics');

create policy interior_dna_read on aec.interior_dna for select to authenticated using(project.can_access_project(project_id));
create policy interior_dna_insert on aec.interior_dna for insert to authenticated with check(project.can_manage_project(project_id) and current_setting('conceptspaces.design_phase',true)='interiors');
create policy interior_dna_update on aec.interior_dna for update to authenticated using(project.can_manage_project(project_id)) with check(project.can_manage_project(project_id) and current_setting('conceptspaces.design_phase',true)='interiors');
create policy interior_rooms_read on aec.interior_room_packages for select to authenticated using(project.can_access_project(project_id));
create policy interior_rooms_insert on aec.interior_room_packages for insert to authenticated with check(project.can_manage_project(project_id) and current_setting('conceptspaces.design_phase',true)='interiors');
create policy interior_rooms_update on aec.interior_room_packages for update to authenticated using(project.can_manage_project(project_id)) with check(project.can_manage_project(project_id) and current_setting('conceptspaces.design_phase',true)='interiors');
create policy interior_materials_read on aec.interior_material_selections for select to authenticated using(project.can_access_project(project_id));
create policy interior_materials_insert on aec.interior_material_selections for insert to authenticated with check(project.can_manage_project(project_id) and current_setting('conceptspaces.design_phase',true)='interiors');
create policy interior_materials_update on aec.interior_material_selections for update to authenticated using(project.can_manage_project(project_id)) with check(project.can_manage_project(project_id) and current_setting('conceptspaces.design_phase',true)='interiors');
create policy interior_shop_read on aec.interior_shop_drawings for select to authenticated using(project.can_access_project(project_id));
create policy interior_shop_insert on aec.interior_shop_drawings for insert to authenticated with check(project.can_manage_project(project_id) and current_setting('conceptspaces.design_phase',true)='interiors');
create policy interior_shop_update on aec.interior_shop_drawings for update to authenticated using(project.can_manage_project(project_id)) with check(project.can_manage_project(project_id) and current_setting('conceptspaces.design_phase',true)='interiors');

drop policy if exists architecture_packages_insert on engineering.architecture_packages;
create policy architecture_packages_insert on engineering.architecture_packages for insert to authenticated with check(project.can_manage_project(project_id) and current_setting('conceptspaces.design_phase',true)='architecture');
drop policy if exists architecture_packages_update on engineering.architecture_packages;
create policy architecture_packages_update on engineering.architecture_packages for update to authenticated using(project.can_manage_project(project_id)) with check(project.can_manage_project(project_id) and current_setting('conceptspaces.design_phase',true)='architecture');
drop policy if exists structural_schemes_insert on engineering.structural_schemes;
create policy structural_schemes_insert on engineering.structural_schemes for insert to authenticated with check(project.can_manage_project(project_id) and current_setting('conceptspaces.design_phase',true)='structure');
drop policy if exists structural_schemes_update on engineering.structural_schemes;
create policy structural_schemes_update on engineering.structural_schemes for update to authenticated using(project.can_manage_project(project_id)) with check(project.can_manage_project(project_id) and current_setting('conceptspaces.design_phase',true)='structure');

commit;