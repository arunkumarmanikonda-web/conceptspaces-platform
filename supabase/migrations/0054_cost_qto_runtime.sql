begin;

alter table cost.quantity_items drop constraint if exists quantity_items_project_id_code_key;
alter table cost.quantity_items add column if not exists revision integer not null default 1;
alter table cost.quantity_items add column if not exists qto_run_id uuid;
alter table cost.quantity_items add column if not exists source_object_refs jsonb not null default '[]'::jsonb;
alter table cost.quantity_items add column if not exists measurement_rule_ref text;
alter table cost.quantity_items add column if not exists formula text;
alter table cost.quantity_items add column if not exists source_revision_hash text;
alter table cost.quantity_items add column if not exists supersedes_quantity_item_id uuid references cost.quantity_items(id) on delete set null;
alter table cost.quantity_items add column if not exists quantity_hash text;
create unique index if not exists quantity_items_project_code_revision_uq on cost.quantity_items(project_id,code,revision);
create index if not exists quantity_items_qto_idx on cost.quantity_items(qto_run_id) where qto_run_id is not null;

alter table cost.boq_lines add column if not exists specification_ref text;
alter table cost.boq_lines add column if not exists rate_source text;
alter table cost.boq_lines add column if not exists rate_date date;
alter table cost.boq_lines add column if not exists package_category text;
alter table cost.boq_lines add column if not exists revision text not null default 'P01';
alter table cost.boq_lines add column if not exists notes text;
alter table cost.boq_lines add column if not exists manual_item boolean not null default false;
alter table cost.boq_lines add column if not exists source_hash text;

alter table cost.cost_plans add column if not exists qto_run_id uuid;
alter table cost.cost_plans add column if not exists baseline_plan_id uuid references cost.cost_plans(id) on delete set null;
alter table cost.cost_plans add column if not exists configuration_hash text;
alter table cost.cost_plans add column if not exists approved_hash text;

create table if not exists cost.qto_runs(
  id uuid primary key default gen_random_uuid(),
  project_id uuid not null references project.projects(id) on delete cascade,
  model_id uuid not null references cde.models(id) on delete restrict,
  model_checksum text not null,
  measurement_rule_set_ref text not null,
  classification_ref text,
  exclusions jsonb not null default '[]'::jsonb,
  tolerance jsonb not null default '{}'::jsonb,
  input_hash text not null,
  output_hash text,
  status text not null default 'queued' check(status in ('queued','running','completed','failed','approved')),
  error_code text,
  created_by uuid references auth.users(id),
  approved_by uuid references auth.users(id),
  approved_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
alter table cost.quantity_items drop constraint if exists quantity_items_qto_run_id_fkey;
alter table cost.quantity_items add constraint quantity_items_qto_run_id_fkey foreign key(qto_run_id) references cost.qto_runs(id) on delete set null;
alter table cost.cost_plans drop constraint if exists cost_plans_qto_run_id_fkey;
alter table cost.cost_plans add constraint cost_plans_qto_run_id_fkey foreign key(qto_run_id) references cost.qto_runs(id) on delete set null;
create index if not exists qto_runs_project_idx on cost.qto_runs(project_id,created_at desc);

alter table feasibility.value_engineering_options add column if not exists source_boq_line_id uuid references cost.boq_lines(id) on delete set null;
alter table feasibility.value_engineering_options add column if not exists alternative_ref text;
alter table feasibility.value_engineering_options add column if not exists lifecycle_impact jsonb not null default '{}'::jsonb;
alter table feasibility.value_engineering_options add column if not exists performance_impact jsonb not null default '{}'::jsonb;
alter table feasibility.value_engineering_options add column if not exists lead_time_impact_days integer;
alter table feasibility.value_engineering_options add column if not exists approved_deviation_ref text;
alter table feasibility.value_engineering_options add column if not exists decided_by uuid references auth.users(id);
alter table feasibility.value_engineering_options add column if not exists decided_at timestamptz;
alter table feasibility.value_engineering_options add column if not exists decision_hash text;

alter table cost.qto_runs enable row level security;
drop policy if exists qto_runs_read on cost.qto_runs;
create policy qto_runs_read on cost.qto_runs for select to authenticated using(project.can_access_project(project_id));
drop policy if exists qto_runs_mutate_insert on cost.qto_runs;
create policy qto_runs_mutate_insert on cost.qto_runs for insert to authenticated with check(project.can_manage_project(project_id) and created_by=auth.uid() and current_setting('conceptspaces.cost_phase',true)='qto_create');
drop policy if exists qto_runs_mutate_update on cost.qto_runs;
create policy qto_runs_mutate_update on cost.qto_runs for update to authenticated using(project.can_manage_project(project_id)) with check(project.can_manage_project(project_id) and current_setting('conceptspaces.cost_phase',true) in ('qto_complete','qto_approve'));
grant select,insert,update on cost.qto_runs to authenticated;

foreach_policy: begin end;

commit;