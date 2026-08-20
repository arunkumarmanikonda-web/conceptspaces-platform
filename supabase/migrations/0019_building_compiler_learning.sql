begin;

create table if not exists public.intent_commands (
  id uuid primary key default gen_random_uuid(), project_id uuid not null,
  input_mode text not null check (input_mode in ('text','voice','sketch','markup')), raw_input_ref text not null,
  interpreted_intent jsonb not null default '{}'::jsonb, target_object_refs jsonb not null default '[]'::jsonb,
  constraints jsonb not null default '[]'::jsonb, ambiguity_questions jsonb not null default '[]'::jsonb,
  confidence text not null check (confidence in ('A','B','C','D')), interpreted_by text not null, approved_by uuid,
  created_at timestamptz not null default now()
);

create table if not exists public.compiler_input_snapshots (
  id uuid primary key default gen_random_uuid(), project_id uuid not null, branch_id uuid not null,
  project_truth_hash text not null, regulation_hash text not null, programme_hash text not null, requirement_hash text not null,
  design_state_hash text, cost_state_hash text, climate_state_hash text, source_refs jsonb not null default '[]'::jsonb,
  captured_at timestamptz not null default now()
);

create table if not exists public.compilation_runs (
  id uuid primary key default gen_random_uuid(), project_id uuid not null, branch_id uuid not null,
  input_snapshot_id uuid not null references public.compiler_input_snapshots(id), objective text not null,
  status text not null default 'queued' check (status in ('queued','running','blocked','awaiting_review','completed','failed','superseded')),
  requested_by uuid not null, final_artifact_refs jsonb not null default '[]'::jsonb,
  created_at timestamptz not null default now(), completed_at timestamptz
);

create table if not exists public.compiler_stage_runs (
  id uuid primary key default gen_random_uuid(), compilation_run_id uuid not null references public.compilation_runs(id) on delete cascade,
  stage text not null check (stage in ('project_truth','regulatory_context','programme','feasibility','option_generation','architecture','structure','mepf','interiors','quantity_cost','coordination','assurance')),
  status text not null default 'queued' check (status in ('queued','running','blocked','awaiting_review','completed','failed','superseded')),
  criticality text not null check (criticality in ('C0','C1','C2','C3','C4')), engine_refs jsonb not null default '[]'::jsonb,
  agent_run_refs jsonb not null default '[]'::jsonb, input_hash text not null, output_hash text,
  evidence_refs jsonb not null default '[]'::jsonb, assumptions jsonb not null default '[]'::jsonb,
  validation_finding_refs jsonb not null default '[]'::jsonb, started_at timestamptz, completed_at timestamptz,
  unique(compilation_run_id, stage)
);

create table if not exists public.pareto_candidates (
  id uuid primary key default gen_random_uuid(), compilation_run_id uuid not null references public.compilation_runs(id) on delete cascade,
  option_id uuid not null, objective_metrics jsonb not null default '{}'::jsonb, dominated boolean not null default false,
  constraint_violations jsonb not null default '[]'::jsonb,
  compliance_state text not null check (compliance_state in ('pass','conditional','fail','not_verified')),
  human_shortlisted boolean not null default false, created_at timestamptz not null default now()
);

create table if not exists public.project_branches (
  id uuid primary key default gen_random_uuid(), project_id uuid not null, name text not null, parent_branch_id uuid,
  parent_commit_hash text, head_commit_hash text not null, purpose text not null,
  status text not null default 'active' check (status in ('active','merged','abandoned','frozen')),
  created_by uuid not null, created_at timestamptz not null default now(), unique(project_id, name)
);

create table if not exists public.project_commits (
  id uuid primary key default gen_random_uuid(), project_id uuid not null, branch_id uuid not null references public.project_branches(id) on delete cascade,
  parent_commit_hashes jsonb not null default '[]'::jsonb, content_hash text not null, message text not null,
  changed_object_refs jsonb not null default '[]'::jsonb, author_type text not null check (author_type in ('human','ai','hybrid')),
  author_ref text not null, created_at timestamptz not null default now(), unique(project_id, content_hash)
);

create table if not exists public.change_impacts (
  id uuid primary key default gen_random_uuid(), project_id uuid not null, change_ref text not null,
  source_object_refs jsonb not null default '[]'::jsonb, affected_requirements jsonb not null default '[]'::jsonb,
  affected_rules jsonb not null default '[]'::jsonb, affected_disciplines jsonb not null default '[]'::jsonb,
  affected_documents jsonb not null default '[]'::jsonb, affected_model_objects jsonb not null default '[]'::jsonb,
  affected_boq_lines jsonb not null default '[]'::jsonb, affected_contracts jsonb not null default '[]'::jsonb,
  estimated_cost_delta numeric(18,2), estimated_schedule_delta_days integer, decision_reversal_cost numeric(18,2),
  criticality text not null check (criticality in ('C0','C1','C2','C3','C4')), confidence text not null check (confidence in ('A','B','C','D')),
  analysis_evidence_refs jsonb not null default '[]'::jsonb, created_at timestamptz not null default now()
);

create table if not exists public.design_lint_findings (
  id uuid primary key default gen_random_uuid(), project_id uuid not null, branch_id uuid not null, rule_code text not null,
  discipline text not null, title text not null, message text not null,
  severity text not null check (severity in ('info','warning','error','critical')),
  criticality text not null check (criticality in ('C0','C1','C2','C3','C4')), object_refs jsonb not null default '[]'::jsonb,
  source_ref text not null, status text not null default 'open' check (status in ('open','accepted','fixed','false_positive')),
  waiver_ref text, created_at timestamptz not null default now(), updated_at timestamptz not null default now()
);

create table if not exists public.adversarial_reviews (
  id uuid primary key default gen_random_uuid(), project_id uuid not null, resource_ref text not null,
  review_type text not null check (review_type in ('design_council','red_team','constructability','operability','maintainability')),
  reviewer_agent_refs jsonb not null default '[]'::jsonb, human_reviewer_refs jsonb not null default '[]'::jsonb,
  attack_questions jsonb not null default '[]'::jsonb, findings jsonb not null default '[]'::jsonb,
  unresolved_critical_findings integer not null default 0, evidence_refs jsonb not null default '[]'::jsonb,
  status text not null default 'running' check (status in ('running','review_required','accepted','rejected')),
  created_at timestamptz not null default now(), updated_at timestamptz not null default now()
);

create table if not exists public.outcome_signals (
  id uuid primary key default gen_random_uuid(), project_id uuid not null,
  signal_type text not null check (signal_type in ('client_approval','design_change','coordination_issue','site_ncr','cost_variance','schedule_variance','energy_outcome','maintenance_outcome','post_occupancy')),
  source_ref text not null, value jsonb not null default '{}'::jsonb, confidence text not null check (confidence in ('A','B','C','D')),
  privacy_state text not null default 'pending' check (privacy_state in ('pending','approved','excluded')), captured_at timestamptz not null,
  created_at timestamptz not null default now()
);

create table if not exists public.design_genome_candidates (
  id uuid primary key default gen_random_uuid(), pattern_code text not null unique, source_signal_refs jsonb not null default '[]'::jsonb,
  proposed_principle text not null, applicable_typologies jsonb not null default '[]'::jsonb, applicable_climates jsonb not null default '[]'::jsonb,
  stage text not null default 'observation' check (stage in ('observation','evidence','privacy_review','expert_review','benchmark','shadow','controlled_production','retired')),
  evidence_score numeric not null default 0, expert_reviewer_refs jsonb not null default '[]'::jsonb,
  benchmark_refs jsonb not null default '[]'::jsonb, rollback_ref text, promoted_at timestamptz,
  created_at timestamptz not null default now(), updated_at timestamptz not null default now()
);

create index if not exists compilation_runs_project_idx on public.compilation_runs(project_id, created_at desc);
create index if not exists compiler_stages_run_idx on public.compiler_stage_runs(compilation_run_id, stage);
create index if not exists project_commits_branch_idx on public.project_commits(branch_id, created_at desc);
create index if not exists change_impacts_project_idx on public.change_impacts(project_id, created_at desc);
create index if not exists design_lint_project_status_idx on public.design_lint_findings(project_id, status, severity);
create index if not exists outcome_signals_project_idx on public.outcome_signals(project_id, captured_at desc);

alter table public.intent_commands enable row level security;
alter table public.compiler_input_snapshots enable row level security;
alter table public.compilation_runs enable row level security;
alter table public.compiler_stage_runs enable row level security;
alter table public.pareto_candidates enable row level security;
alter table public.project_branches enable row level security;
alter table public.project_commits enable row level security;
alter table public.change_impacts enable row level security;
alter table public.design_lint_findings enable row level security;
alter table public.adversarial_reviews enable row level security;
alter table public.outcome_signals enable row level security;
alter table public.design_genome_candidates enable row level security;

commit;
