begin;

create table if not exists engagement.professional_profiles(
 id uuid primary key default gen_random_uuid(),
 organisation_id uuid not null references core.organisations(id) on delete cascade,
 user_id uuid not null references auth.users(id) on delete cascade,
 display_name text not null,
 discipline text not null,
 registration_summary text,
 geographies jsonb not null default '[]'::jsonb,
 typologies jsonb not null default '[]'::jsonb,
 skills jsonb not null default '[]'::jsonb,
 years_experience numeric not null default 0 check(years_experience>=0),
 fee_rate numeric check(fee_rate is null or fee_rate>=0),
 fee_currency text not null default 'INR',
 capacity_hours_week numeric not null default 40 check(capacity_hours_week>0),
 availability_status text not null default 'active' check(availability_status in ('active','limited','unavailable','suspended')),
 profile_hash text,
 created_by uuid not null references auth.users(id),
 created_at timestamptz not null default now(),
 updated_at timestamptz not null default now(),
 unique(organisation_id,user_id)
);

create table if not exists engagement.professional_competencies(
 id uuid primary key default gen_random_uuid(),
 profile_id uuid not null references engagement.professional_profiles(id) on delete cascade,
 organisation_id uuid not null references core.organisations(id) on delete cascade,
 competency_code text not null,
 level integer not null check(level between 1 and 5),
 evidence_refs jsonb not null default '[]'::jsonb,
 verified_by uuid references auth.users(id),
 verified_at timestamptz,
 created_at timestamptz not null default now(),
 unique(profile_id,competency_code)
);

create table if not exists engagement.professional_availability(
 id uuid primary key default gen_random_uuid(),
 profile_id uuid not null references engagement.professional_profiles(id) on delete cascade,
 organisation_id uuid not null references core.organisations(id) on delete cascade,
 available_from date not null,
 available_until date,
 capacity_hours_week numeric not null check(capacity_hours_week>0),
 note text,
 created_by uuid not null references auth.users(id),
 created_at timestamptz not null default now(),
 check(available_until is null or available_until>=available_from)
);

create table if not exists engagement.professional_conflicts(
 id uuid primary key default gen_random_uuid(),
 profile_id uuid not null references engagement.professional_profiles(id) on delete cascade,
 project_id uuid not null references project.projects(id) on delete cascade,
 conflict_type text not null,
 details text not null,
 status text not null default 'open' check(status in ('open','cleared','expired')),
 declared_by uuid not null references auth.users(id),
 declared_at timestamptz not null default now(),
 cleared_by uuid references auth.users(id),
 cleared_at timestamptz,
 clearance_reason text
);

create table if not exists engagement.professional_performance_metrics(
 id uuid primary key default gen_random_uuid(),
 organisation_id uuid not null references core.organisations(id) on delete cascade,
 profile_id uuid not null references engagement.professional_profiles(id) on delete cascade,
 project_id uuid not null references project.projects(id) on delete cascade,
 metric_code text not null,
 metric_value numeric not null,
 unit text not null,
 outcome_type text not null check(outcome_type in ('first_pass_quality','correction','schedule','rfi','ncr','cost_impact','review','other')),
 source_ref text not null,
 source_hash text not null,
 notes text,
 review_state text not null default 'recorded' check(review_state in ('recorded','validated','excluded')),
 recorded_by uuid not null references auth.users(id),
 recorded_at timestamptz not null default now(),
 reviewed_by uuid references auth.users(id),
 reviewed_at timestamptz,
 review_reason text
);

alter table engagement.project_professional_assignments
 add column if not exists supersedes_assignment_id uuid references engagement.project_professional_assignments(id) on delete set null,
 add column if not exists replacement_reason text,
 add column if not exists assignment_hash text;

create table if not exists engagement.professional_assignment_events(
 id uuid primary key default gen_random_uuid(),
 assignment_id uuid not null references engagement.project_professional_assignments(id) on delete cascade,
 project_id uuid not null references project.projects(id) on delete cascade,
 event_type text not null,
 from_state text,
 to_state text,
 reason text,
 actor_id uuid not null references auth.users(id),
 snapshot jsonb not null,
 created_at timestamptz not null default now()
);

create index if not exists professional_conflicts_project_idx on engagement.professional_conflicts(project_id,status);
create index if not exists professional_performance_profile_idx on engagement.professional_performance_metrics(profile_id,recorded_at desc);
create index if not exists professional_assignments_user_state_idx on engagement.project_professional_assignments(user_id,state);

alter table engagement.professional_profiles enable row level security;
alter table engagement.professional_competencies enable row level security;
alter table engagement.professional_availability enable row level security;
alter table engagement.professional_conflicts enable row level security;
alter table engagement.professional_performance_metrics enable row level security;
alter table engagement.professional_assignment_events enable row level security;

grant select,insert,update on engagement.professional_profiles,engagement.professional_competencies,engagement.professional_availability,engagement.professional_conflicts,engagement.professional_performance_metrics to authenticated;
grant select,insert on engagement.professional_assignment_events to authenticated;
grant insert,update on engagement.project_professional_assignments to authenticated;

do $$ declare t text; begin
 foreach t in array array['professional_profiles','professional_competencies','professional_availability','professional_performance_metrics'] loop
  execute format('drop policy if exists %I on engagement.%I','professional_org_read_'||t,t);
  execute format('create policy %I on engagement.%I for select to authenticated using (core.is_internal_org_member(organisation_id))','professional_org_read_'||t,t);
 end loop;
end $$;

drop policy if exists professional_conflict_read on engagement.professional_conflicts;
create policy professional_conflict_read on engagement.professional_conflicts for select to authenticated using(project.can_access_project(project_id));
drop policy if exists professional_assignment_event_read on engagement.professional_assignment_events;
create policy professional_assignment_event_read on engagement.professional_assignment_events for select to authenticated using(project.can_access_project(project_id));

drop policy if exists professional_profiles_write on engagement.professional_profiles;
create policy professional_profiles_write on engagement.professional_profiles for insert to authenticated
with check(core.is_internal_org_member(organisation_id) and created_by=auth.uid() and current_setting('conceptspaces.professional_phase',true)='profile');
drop policy if exists professional_profiles_update on engagement.professional_profiles;
create policy professional_profiles_update on engagement.professional_profiles for update to authenticated
using(core.is_internal_org_member(organisation_id))
with check(core.is_internal_org_member(organisation_id) and current_setting('conceptspaces.professional_phase',true)='profile');

drop policy if exists professional_competencies_write on engagement.professional_competencies;
create policy professional_competencies_write on engagement.professional_competencies for insert to authenticated
with check(core.is_internal_org_member(organisation_id) and current_setting('conceptspaces.professional_phase',true)='competency');
drop policy if exists professional_competencies_update on engagement.professional_competencies;
create policy professional_competencies_update on engagement.professional_competencies for update to authenticated
using(core.is_internal_org_member(organisation_id))
with check(core.is_internal_org_member(organisation_id) and current_setting('conceptspaces.professional_phase',true)='competency');

drop policy if exists professional_availability_write on engagement.professional_availability;
create policy professional_availability_write on engagement.professional_availability for insert to authenticated
with check(core.is_internal_org_member(organisation_id) and created_by=auth.uid() and current_setting('conceptspaces.professional_phase',true)='availability');
drop policy if exists professional_availability_update on engagement.professional_availability;
create policy professional_availability_update on engagement.professional_availability for update to authenticated
using(core.is_internal_org_member(organisation_id))
with check(core.is_internal_org_member(organisation_id) and current_setting('conceptspaces.professional_phase',true)='availability');

drop policy if exists professional_conflicts_write on engagement.professional_conflicts;
create policy professional_conflicts_write on engagement.professional_conflicts for insert to authenticated
with check(project.can_access_project(project_id) and declared_by=auth.uid() and current_setting('conceptspaces.professional_phase',true)='conflict');
drop policy if exists professional_conflicts_update on engagement.professional_conflicts;
create policy professional_conflicts_update on engagement.professional_conflicts for update to authenticated
using(project.can_manage_project(project_id))
with check(project.can_manage_project(project_id) and current_setting('conceptspaces.professional_phase',true)='conflict_clear');

drop policy if exists professional_performance_write on engagement.professional_performance_metrics;
create policy professional_performance_write on engagement.professional_performance_metrics for insert to authenticated
with check(project.can_access_project(project_id) and recorded_by=auth.uid() and current_setting('conceptspaces.professional_phase',true)='performance');
drop policy if exists professional_performance_update on engagement.professional_performance_metrics;
create policy professional_performance_update on engagement.professional_performance_metrics for update to authenticated
using(project.can_manage_project(project_id))
with check(project.can_manage_project(project_id) and current_setting('conceptspaces.professional_phase',true)='performance_review');

drop policy if exists professional_assignment_event_write on engagement.professional_assignment_events;
create policy professional_assignment_event_write on engagement.professional_assignment_events for insert to authenticated
with check(project.can_manage_project(project_id) and actor_id=auth.uid() and current_setting('conceptspaces.professional_phase',true) in ('assign','replace'));

drop policy if exists professional_assignments_governed_insert on engagement.project_professional_assignments;
create policy professional_assignments_governed_insert on engagement.project_professional_assignments for insert to authenticated
with check(project.can_manage_project(project_id) and assigned_by=auth.uid() and current_setting('conceptspaces.professional_phase',true) in ('assign','replace'));
drop policy if exists professional_assignments_governed_update on engagement.project_professional_assignments;
create policy professional_assignments_governed_update on engagement.project_professional_assignments for update to authenticated
using(project.can_manage_project(project_id))
with check(project.can_manage_project(project_id) and current_setting('conceptspaces.professional_phase',true)='replace');

commit;
