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
create index if not exists quantity_items_qto_idx on cost.quantity_items(qto_run_id) where qto_run_id is not null;

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
drop policy if exists qto_runs_insert on cost.qto_runs;
create policy qto_runs_insert on cost.qto_runs for insert to authenticated with check(project.can_manage_project(project_id) and created_by=auth.uid() and current_setting('conceptspaces.cost_phase',true)='qto_create');
drop policy if exists qto_runs_update on cost.qto_runs;
create policy qto_runs_update on cost.qto_runs for update to authenticated using(project.can_manage_project(project_id)) with check(project.can_manage_project(project_id) and current_setting('conceptspaces.cost_phase',true) in ('qto_complete','qto_approve'));

drop policy if exists cost_plans_write_insert on cost.cost_plans;
create policy cost_plans_write_insert on cost.cost_plans for insert to authenticated with check(project.can_manage_project(project_id) and created_by=auth.uid() and current_setting('conceptspaces.cost_phase',true)='plan_create');
drop policy if exists cost_plans_write_update on cost.cost_plans;
create policy cost_plans_write_update on cost.cost_plans for update to authenticated using(project.can_manage_project(project_id)) with check(project.can_manage_project(project_id) and current_setting('conceptspaces.cost_phase',true) in ('plan_transition','plan_approve'));

drop policy if exists quantity_items_write_insert on cost.quantity_items;
create policy quantity_items_write_insert on cost.quantity_items for insert to authenticated with check(project.can_manage_project(project_id) and current_setting('conceptspaces.cost_phase',true)='qto_complete');

drop policy if exists boq_lines_write_insert on cost.boq_lines;
create policy boq_lines_write_insert on cost.boq_lines for insert to authenticated with check(current_setting('conceptspaces.cost_phase',true)='boq_edit' and exists(select 1 from cost.cost_plans p where p.id=cost_plan_id and p.status='draft' and project.can_manage_project(p.project_id)));
drop policy if exists boq_lines_write_update on cost.boq_lines;
create policy boq_lines_write_update on cost.boq_lines for update to authenticated using(exists(select 1 from cost.cost_plans p where p.id=cost_plan_id and p.status='draft' and project.can_manage_project(p.project_id))) with check(current_setting('conceptspaces.cost_phase',true)='boq_edit' and exists(select 1 from cost.cost_plans p where p.id=cost_plan_id and p.status='draft' and project.can_manage_project(p.project_id)));
drop policy if exists boq_lines_write_delete on cost.boq_lines;
create policy boq_lines_write_delete on cost.boq_lines for delete to authenticated using(current_setting('conceptspaces.cost_phase',true)='boq_edit' and exists(select 1 from cost.cost_plans p where p.id=cost_plan_id and p.status='draft' and project.can_manage_project(p.project_id)));

drop policy if exists ve_options_write_insert on feasibility.value_engineering_options;
create policy ve_options_write_insert on feasibility.value_engineering_options for insert to authenticated with check(project.can_manage_project(project_id) and current_setting('conceptspaces.cost_phase',true)='ve_create');
drop policy if exists ve_options_write_update on feasibility.value_engineering_options;
create policy ve_options_write_update on feasibility.value_engineering_options for update to authenticated using(project.can_manage_project(project_id)) with check(project.can_manage_project(project_id) and current_setting('conceptspaces.cost_phase',true)='ve_decide');

grant select,insert,update on cost.qto_runs to authenticated;
grant insert,update on cost.cost_plans to authenticated;
grant insert on cost.quantity_items to authenticated;
grant insert,update,delete on cost.boq_lines to authenticated;
grant insert,update on feasibility.value_engineering_options to authenticated;

commit;