begin;
create schema if not exists ai;

create table if not exists ai.model_profiles (
 id uuid primary key default gen_random_uuid(), provider text not null, model text not null, purpose text not null,
 enabled boolean not null default false, max_criticality text not null default 'C1' check(max_criticality in('C0','C1','C2','C3','C4')),
 supports_structured_output boolean not null default false, supports_vision boolean not null default false, supports_tool_use boolean not null default false,
 data_residency text, cost_policy jsonb not null default '{}'::jsonb, latency_target_ms integer, evaluation_threshold numeric(8,4),
 secret_ref text, created_at timestamptz not null default now(), updated_at timestamptz not null default now(), unique(provider,model,purpose)
);

create table if not exists ai.agent_definitions (
 code citext primary key, name text not null, purpose text not null, max_criticality text not null check(max_criticality in('C0','C1','C2','C3','C4')),
 allowed_autonomy text not null check(allowed_autonomy in('human_only','ai_advisory','ai_draft','execute_after_approval','bounded_autonomous')),
 allowed_tools jsonb not null default '[]'::jsonb, prohibited_actions jsonb not null default '[]'::jsonb,
 no_hallucination_zones jsonb not null default '[]'::jsonb, requires_grounding boolean not null default true,
 requires_human_approval_for jsonb not null default '[]'::jsonb, enabled boolean not null default false, created_at timestamptz not null default now()
);

create table if not exists ai.prompt_versions (
 id uuid primary key default gen_random_uuid(), agent_code citext not null references ai.agent_definitions(code) on delete cascade,
 version integer not null, template text not null, output_schema_ref text, system_policy_ref text,
 status text not null default 'draft' check(status in('draft','review','active','retired')),
 created_by uuid references auth.users(id), approved_by uuid references auth.users(id), created_at timestamptz not null default now(), approved_at timestamptz,
 unique(agent_code,version)
);

create table if not exists ai.agent_runs (
 id uuid primary key default gen_random_uuid(), organisation_id uuid not null references core.organisations(id) on delete cascade,
 project_id uuid references project.projects(id) on delete cascade, agent_code citext not null references ai.agent_definitions(code),
 model_profile_id uuid not null references ai.model_profiles(id), prompt_version_id uuid not null references ai.prompt_versions(id),
 status text not null default 'queued' check(status in('queued','running','awaiting_approval','succeeded','failed','cancelled')),
 criticality text not null check(criticality in('C0','C1','C2','C3','C4')), input_ref text, output_ref text,
 evidence_refs jsonb not null default '[]'::jsonb, tool_calls jsonb not null default '[]'::jsonb,
 input_tokens integer, output_tokens integer, estimated_cost numeric(18,6), correlation_id uuid not null default gen_random_uuid(),
 started_at timestamptz, finished_at timestamptz, created_at timestamptz not null default now()
);

create table if not exists ai.evaluation_cases (
 id uuid primary key default gen_random_uuid(), suite_code citext not null, name text not null, input jsonb not null,
 expected_assertions jsonb not null default '[]'::jsonb, criticality text not null check(criticality in('C0','C1','C2','C3','C4')),
 active boolean not null default true, created_at timestamptz not null default now()
);

create table if not exists ai.evaluation_results (
 id uuid primary key default gen_random_uuid(), case_id uuid not null references ai.evaluation_cases(id) on delete cascade,
 model_profile_id uuid not null references ai.model_profiles(id), prompt_version_id uuid not null references ai.prompt_versions(id),
 score numeric(8,4) not null, passed boolean not null, findings jsonb not null default '[]'::jsonb, run_at timestamptz not null default now()
);

create table if not exists ai.learning_candidates (
 id uuid primary key default gen_random_uuid(), source_project_id uuid references project.projects(id) on delete set null,
 source_type text not null, source_ref text not null, stage text not null default 'observation' check(stage in('observation','evidence','privacy_review','expert_review','benchmark','shadow','controlled_production','retired')),
 privacy_state text not null default 'pending' check(privacy_state in('pending','approved','rejected')),
 evidence_quality text not null default 'low' check(evidence_quality in('low','medium','high')), benchmark_delta numeric(10,6),
 expert_reviewers jsonb not null default '[]'::jsonb, rollback_ref text, created_at timestamptz not null default now(), updated_at timestamptz not null default now()
);

create index if not exists ai_runs_project_idx on ai.agent_runs(project_id,status,created_at desc);
create index if not exists ai_eval_model_idx on ai.evaluation_results(model_profile_id,run_at desc);
create index if not exists ai_learning_stage_idx on ai.learning_candidates(stage,privacy_state);

alter table ai.model_profiles enable row level security;
alter table ai.agent_definitions enable row level security;
alter table ai.prompt_versions enable row level security;
alter table ai.agent_runs enable row level security;
alter table ai.evaluation_cases enable row level security;
alter table ai.evaluation_results enable row level security;
alter table ai.learning_candidates enable row level security;
commit;
