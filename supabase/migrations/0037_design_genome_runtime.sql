begin;

create table if not exists public.design_genome_stage_events (
  id uuid primary key default gen_random_uuid(),
  candidate_id uuid not null references public.design_genome_candidates(id) on delete cascade,
  actor_id uuid not null references auth.users(id),
  from_stage text,
  to_stage text not null check (to_stage in ('observation','evidence','privacy_review','expert_review','benchmark','shadow','controlled_production','retired')),
  reason text not null,
  evidence_snapshot jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now()
);

create index if not exists design_genome_stage_events_candidate_idx
  on public.design_genome_stage_events(candidate_id, created_at desc);

alter table public.design_genome_stage_events enable row level security;

drop policy if exists cs_read_admin on public.design_genome_stage_events;
create policy cs_read_admin on public.design_genome_stage_events
for select to authenticated using (core.is_platform_admin());

grant select on public.design_genome_stage_events to authenticated;

comment on table public.design_genome_stage_events is
  'Append-only human governance ledger for Design Genome stage transitions. Promotion cannot skip stages and controlled production requires rollback evidence.';

create or replace function public.record_outcome_signal(
  target_project_id uuid,
  target_signal_type text,
  target_source_ref text,
  target_value jsonb default '{}'::jsonb,
  target_confidence text default 'C',
  target_captured_at timestamptz default now(),
  target_reason text default 'Outcome evidence recorded'
)
returns uuid
language plpgsql
security definer
set search_path = public, project, core, audit, auth, pg_temp
as $$
declare
  project_org_id uuid;
  new_signal public.outcome_signals%rowtype;
begin
  if auth.uid() is null or not project.can_manage_project(target_project_id) then
    raise exception 'project_manage_authority_required';
  end if;
  if nullif(btrim(target_source_ref),'') is null then raise exception 'source_reference_required'; end if;
  if lower(target_signal_type) not in ('client_approval','design_change','coordination_issue','site_ncr','cost_variance','schedule_variance','energy_outcome','maintenance_outcome','post_occupancy') then
    raise exception 'invalid_outcome_signal_type';
  end if;
  if upper(target_confidence) not in ('A','B','C','D') then raise exception 'invalid_confidence'; end if;
  if jsonb_typeof(coalesce(target_value,'{}'::jsonb)) <> 'object' then raise exception 'outcome_value_must_be_object'; end if;

  select organisation_id into project_org_id from project.projects where id = target_project_id;
  if project_org_id is null then raise exception 'project_not_found'; end if;

  insert into public.outcome_signals(project_id,signal_type,source_ref,value,confidence,privacy_state,captured_at)
  values(target_project_id,lower(target_signal_type),btrim(target_source_ref),coalesce(target_value,'{}'::jsonb),upper(target_confidence),'pending',coalesce(target_captured_at,now()))
  returning * into new_signal;

  perform audit.append_event(
    project_org_id,target_project_id,'outcome_signal.recorded','outcome_signal',new_signal.id,
    null,to_jsonb(new_signal),coalesce(nullif(btrim(target_reason),''),'Outcome evidence recorded')
  );
  return new_signal.id;
end;
$$;
revoke all on function public.record_outcome_signal(uuid,text,text,jsonb,text,timestamptz,text) from public, anon;
grant execute on function public.record_outcome_signal(uuid,text,text,jsonb,text,timestamptz,text) to authenticated;

create or replace function public.set_outcome_signal_privacy(
  target_signal_id uuid,
  target_privacy_state text,
  target_reason text
)
returns void
language plpgsql
security definer
set search_path = public, project, core, audit, auth, pg_temp
as $$
declare
  before_signal public.outcome_signals%rowtype;
  after_signal public.outcome_signals%rowtype;
  project_org_id uuid;
begin
  if auth.uid() is null or not core.is_platform_admin() then raise exception 'platform_admin_required'; end if;
  if lower(target_privacy_state) not in ('pending','approved','excluded') then raise exception 'invalid_privacy_state'; end if;
  if nullif(btrim(target_reason),'') is null then raise exception 'privacy_review_reason_required'; end if;

  select * into before_signal from public.outcome_signals where id = target_signal_id for update;
  if not found then raise exception 'outcome_signal_not_found'; end if;
  select organisation_id into project_org_id from project.projects where id = before_signal.project_id;

  update public.outcome_signals
  set privacy_state = lower(target_privacy_state)
  where id = target_signal_id
  returning * into after_signal;

  perform audit.append_event(
    project_org_id,before_signal.project_id,'outcome_signal.privacy_reviewed','outcome_signal',target_signal_id,
    to_jsonb(before_signal),to_jsonb(after_signal),btrim(target_reason)
  );
end;
$$;
revoke all on function public.set_outcome_signal_privacy(uuid,text,text) from public, anon;
grant execute on function public.set_outcome_signal_privacy(uuid,text,text) to authenticated;

create or replace function public.propose_design_genome_candidate(
  target_pattern_code text,
  target_source_signal_refs jsonb,
  target_proposed_principle text,
  target_applicable_typologies jsonb default '[]'::jsonb,
  target_applicable_climates jsonb default '[]'::jsonb,
  target_reason text default 'Learning candidate observed from project outcomes'
)
returns uuid
language plpgsql
security definer
set search_path = public, core, auth, pg_temp
as $$
declare
  new_candidate public.design_genome_candidates%rowtype;
  signal_count integer;
begin
  if auth.uid() is null or not core.is_platform_admin() then raise exception 'platform_admin_required'; end if;
  if nullif(btrim(target_pattern_code),'') is null then raise exception 'pattern_code_required'; end if;
  if nullif(btrim(target_proposed_principle),'') is null then raise exception 'proposed_principle_required'; end if;
  if jsonb_typeof(target_source_signal_refs) <> 'array' then raise exception 'source_signal_refs_must_be_array'; end if;
  if jsonb_typeof(coalesce(target_applicable_typologies,'[]'::jsonb)) <> 'array' then raise exception 'typologies_must_be_array'; end if;
  if jsonb_typeof(coalesce(target_applicable_climates,'[]'::jsonb)) <> 'array' then raise exception 'climates_must_be_array'; end if;

  select count(*) into signal_count from jsonb_array_elements_text(target_source_signal_refs);
  if signal_count = 0 then raise exception 'source_signal_required'; end if;
  if exists (
    select 1
    from jsonb_array_elements_text(target_source_signal_refs) r(value)
    left join public.outcome_signals s on s.id::text = r.value
    where s.id is null
  ) then raise exception 'unknown_source_signal'; end if;

  insert into public.design_genome_candidates(
    pattern_code,source_signal_refs,proposed_principle,applicable_typologies,applicable_climates,stage,evidence_score
  ) values (
    lower(regexp_replace(btrim(target_pattern_code),'[^a-zA-Z0-9_-]+','_','g')),
    target_source_signal_refs,btrim(target_proposed_principle),coalesce(target_applicable_typologies,'[]'::jsonb),
    coalesce(target_applicable_climates,'[]'::jsonb),'observation',0
  ) returning * into new_candidate;

  insert into public.design_genome_stage_events(candidate_id,actor_id,from_stage,to_stage,reason,evidence_snapshot)
  values(new_candidate.id,auth.uid(),null,'observation',coalesce(nullif(btrim(target_reason),''),'Learning candidate observed from project outcomes'),
    jsonb_build_object('source_signal_refs',new_candidate.source_signal_refs,'evidence_score',new_candidate.evidence_score));

  return new_candidate.id;
end;
$$;
revoke all on function public.propose_design_genome_candidate(text,jsonb,text,jsonb,jsonb,text) from public, anon;
grant execute on function public.propose_design_genome_candidate(text,jsonb,text,jsonb,jsonb,text) to authenticated;

create or replace function public.advance_design_genome_candidate(
  target_candidate_id uuid,
  target_stage text,
  target_reason text,
  target_evidence_score numeric default null,
  target_expert_reviewer_refs jsonb default null,
  target_benchmark_refs jsonb default null,
  target_rollback_ref text default null
)
returns void
language plpgsql
security definer
set search_path = public, core, auth, pg_temp
as $$
declare
  candidate public.design_genome_candidates%rowtype;
  next_stage text := lower(target_stage);
  next_score numeric;
  next_experts jsonb;
  next_benchmarks jsonb;
  next_rollback text;
  source_project_count integer;
  privacy_block_count integer;
begin
  if auth.uid() is null or not core.is_platform_admin() then raise exception 'platform_admin_required'; end if;
  if nullif(btrim(target_reason),'') is null then raise exception 'promotion_reason_required'; end if;

  select * into candidate from public.design_genome_candidates where id = target_candidate_id for update;
  if not found then raise exception 'design_genome_candidate_not_found'; end if;
  if candidate.stage = 'retired' then raise exception 'retired_candidate_is_terminal'; end if;

  if next_stage <> 'retired' and not (
    (candidate.stage='observation' and next_stage='evidence') or
    (candidate.stage='evidence' and next_stage='privacy_review') or
    (candidate.stage='privacy_review' and next_stage='expert_review') or
    (candidate.stage='expert_review' and next_stage='benchmark') or
    (candidate.stage='benchmark' and next_stage='shadow') or
    (candidate.stage='shadow' and next_stage='controlled_production')
  ) then raise exception 'invalid_learning_stage_transition'; end if;

  next_score := coalesce(target_evidence_score,candidate.evidence_score);
  next_experts := coalesce(target_expert_reviewer_refs,candidate.expert_reviewer_refs,'[]'::jsonb);
  next_benchmarks := coalesce(target_benchmark_refs,candidate.benchmark_refs,'[]'::jsonb);
  next_rollback := coalesce(nullif(btrim(target_rollback_ref),''),candidate.rollback_ref);

  if next_score < 0 then raise exception 'evidence_score_must_be_nonnegative'; end if;
  if jsonb_typeof(next_experts) <> 'array' then raise exception 'expert_reviewer_refs_must_be_array'; end if;
  if jsonb_typeof(next_benchmarks) <> 'array' then raise exception 'benchmark_refs_must_be_array'; end if;

  if next_stage = 'evidence' then
    select count(distinct s.project_id) into source_project_count
    from public.outcome_signals s
    join jsonb_array_elements_text(candidate.source_signal_refs) r(value) on s.id::text = r.value;
    if source_project_count < 2 then raise exception 'cross_project_evidence_required'; end if;
  end if;

  if next_stage = 'expert_review' then
    select count(*) into privacy_block_count
    from jsonb_array_elements_text(candidate.source_signal_refs) r(value)
    left join public.outcome_signals s on s.id::text = r.value
    where s.id is null or s.privacy_state <> 'approved';
    if privacy_block_count > 0 then raise exception 'privacy_approval_required_for_all_sources'; end if;
  end if;

  if next_stage = 'benchmark' and jsonb_array_length(next_experts) = 0 then
    raise exception 'expert_review_evidence_required';
  end if;
  if next_stage = 'shadow' then
    if jsonb_array_length(next_benchmarks) = 0 then raise exception 'benchmark_evidence_required'; end if;
    if next_score <= 0 then raise exception 'measurable_evidence_score_required'; end if;
  end if;
  if next_stage = 'controlled_production' then
    if jsonb_array_length(next_experts) = 0 then raise exception 'expert_review_evidence_required'; end if;
    if jsonb_array_length(next_benchmarks) = 0 then raise exception 'benchmark_evidence_required'; end if;
    if nullif(btrim(next_rollback),'') is null then raise exception 'rollback_reference_required'; end if;
  end if;

  update public.design_genome_candidates
  set stage = next_stage,
      evidence_score = next_score,
      expert_reviewer_refs = next_experts,
      benchmark_refs = next_benchmarks,
      rollback_ref = next_rollback,
      promoted_at = case when next_stage='controlled_production' then now() else promoted_at end,
      updated_at = now()
  where id = candidate.id;

  insert into public.design_genome_stage_events(candidate_id,actor_id,from_stage,to_stage,reason,evidence_snapshot)
  values(candidate.id,auth.uid(),candidate.stage,next_stage,btrim(target_reason),
    jsonb_build_object(
      'evidence_score',next_score,
      'expert_reviewer_refs',next_experts,
      'benchmark_refs',next_benchmarks,
      'rollback_ref',next_rollback,
      'source_signal_refs',candidate.source_signal_refs
    ));
end;
$$;
revoke all on function public.advance_design_genome_candidate(uuid,text,text,numeric,jsonb,jsonb,text) from public, anon;
grant execute on function public.advance_design_genome_candidate(uuid,text,text,numeric,jsonb,jsonb,text) to authenticated;

create or replace function public.list_learning_workspace()
returns jsonb
language plpgsql
stable
security invoker
set search_path = public, project, core, auth, pg_temp
as $$
declare
  admin_mode boolean;
begin
  if auth.uid() is null then raise exception 'authentication_required'; end if;
  admin_mode := core.is_platform_admin();

  return jsonb_build_object(
    'is_platform_admin',admin_mode,
    'signals',coalesce((
      select jsonb_agg(jsonb_build_object(
        'id',s.id,'project_id',s.project_id,'project_code',p.code::text,'project_name',p.name,
        'signal_type',s.signal_type,'source_ref',s.source_ref,'value',s.value,'confidence',s.confidence,
        'privacy_state',s.privacy_state,'captured_at',s.captured_at,'created_at',s.created_at
      ) order by s.created_at desc)
      from public.outcome_signals s
      join project.projects p on p.id=s.project_id
      where project.can_access_project(s.project_id)
    ),'[]'::jsonb),
    'candidates',case when admin_mode then coalesce((
      select jsonb_agg(to_jsonb(c) order by c.updated_at desc,c.created_at desc)
      from public.design_genome_candidates c
    ),'[]'::jsonb) else '[]'::jsonb end,
    'events',case when admin_mode then coalesce((
      select jsonb_agg(jsonb_build_object(
        'id',e.id,'candidate_id',e.candidate_id,'actor_id',e.actor_id,'from_stage',e.from_stage,
        'to_stage',e.to_stage,'reason',e.reason,'evidence_snapshot',e.evidence_snapshot,'created_at',e.created_at
      ) order by e.created_at desc)
      from public.design_genome_stage_events e
    ),'[]'::jsonb) else '[]'::jsonb end
  );
end;
$$;
revoke all on function public.list_learning_workspace() from public, anon;
grant execute on function public.list_learning_workspace() to authenticated;

commit;
