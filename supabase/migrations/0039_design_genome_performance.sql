begin;

create index if not exists design_genome_stage_events_actor_idx
  on public.design_genome_stage_events(actor_id, created_at desc);

drop policy if exists outcome_signal_governed_insert on public.outcome_signals;
create policy outcome_signal_governed_insert on public.outcome_signals
for insert to authenticated
with check (
  (select current_setting('conceptspaces.learning_phase',true))='record_signal'
  and project.can_manage_project(project_id)
  and privacy_state='pending'
);

drop policy if exists outcome_signal_governed_privacy_update on public.outcome_signals;
create policy outcome_signal_governed_privacy_update on public.outcome_signals
for update to authenticated
using (
  (select current_setting('conceptspaces.learning_phase',true))='privacy_review'
  and core.is_platform_admin()
)
with check (
  (select current_setting('conceptspaces.learning_phase',true))='privacy_review'
  and core.is_platform_admin()
  and privacy_state in ('pending','approved','excluded')
);

drop policy if exists design_genome_governed_insert on public.design_genome_candidates;
create policy design_genome_governed_insert on public.design_genome_candidates
for insert to authenticated
with check (
  (select current_setting('conceptspaces.learning_phase',true))='propose_candidate'
  and core.is_platform_admin()
  and stage='observation'
  and evidence_score=0
);

drop policy if exists design_genome_governed_update on public.design_genome_candidates;
create policy design_genome_governed_update on public.design_genome_candidates
for update to authenticated
using (
  (select current_setting('conceptspaces.learning_phase',true))='advance_candidate'
  and core.is_platform_admin()
)
with check (
  (select current_setting('conceptspaces.learning_phase',true))='advance_candidate'
  and core.is_platform_admin()
);

drop policy if exists design_genome_event_governed_insert on public.design_genome_stage_events;
create policy design_genome_event_governed_insert on public.design_genome_stage_events
for insert to authenticated
with check (
  core.is_platform_admin()
  and actor_id=(select auth.uid())
  and (select current_setting('conceptspaces.learning_phase',true)) in ('propose_candidate','advance_candidate')
);

commit;
