begin;

create table if not exists public.event_definitions (
  id uuid primary key default gen_random_uuid(),
  event_type text not null unique,
  latest_version integer not null default 1,
  owner_domain text not null,
  description text not null,
  pii_classification text not null default 'none' check (pii_classification in ('none','limited','sensitive')),
  default_criticality text not null default 'C1' check (default_criticality in ('C0','C1','C2','C3','C4')),
  retention_days integer not null default 2555,
  replayable boolean not null default true,
  enabled boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists public.domain_events (
  id uuid primary key,
  event_type text not null,
  event_version integer not null,
  occurred_at timestamptz not null,
  organisation_id uuid not null,
  project_id uuid,
  actor_ref text,
  correlation_id uuid not null,
  causation_id uuid,
  criticality text not null check (criticality in ('C0','C1','C2','C3','C4')),
  payload jsonb not null,
  payload_hash text not null,
  created_at timestamptz not null default now()
);

create table if not exists public.event_outbox (
  id uuid primary key default gen_random_uuid(),
  event_id uuid not null references public.domain_events(id) on delete cascade,
  status text not null default 'pending' check (status in ('pending','published','failed')),
  attempt_count integer not null default 0,
  available_at timestamptz not null default now(),
  published_at timestamptz,
  last_error text,
  created_at timestamptz not null default now(),
  unique(event_id)
);

create table if not exists public.event_subscriptions (
  id uuid primary key default gen_random_uuid(),
  organisation_id uuid not null,
  subscriber_key text not null,
  event_pattern text not null,
  endpoint_ref text,
  enabled boolean not null default true,
  max_attempts integer not null default 8,
  backoff_seconds jsonb not null default '[30,120,300,900,3600]'::jsonb,
  allowed_criticalities jsonb not null default '["C0","C1","C2"]'::jsonb,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique(organisation_id, subscriber_key, event_pattern)
);

create table if not exists public.event_deliveries (
  id uuid primary key default gen_random_uuid(),
  event_id uuid not null references public.domain_events(id) on delete cascade,
  subscription_id uuid not null references public.event_subscriptions(id) on delete cascade,
  status text not null default 'pending' check (status in ('pending','processing','delivered','failed','dead_letter','cancelled')),
  attempt_count integer not null default 0,
  idempotency_key text not null,
  next_attempt_at timestamptz,
  delivered_at timestamptz,
  response_code integer,
  error_code text,
  response_hash text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique(subscription_id, idempotency_key)
);

create table if not exists public.webhook_receipts (
  id uuid primary key default gen_random_uuid(),
  provider text not null,
  provider_event_id text,
  received_at timestamptz not null default now(),
  raw_body_hash text not null,
  signature_present boolean not null default false,
  signature_verified boolean not null default false,
  status text not null default 'received' check (status in ('received','verified','rejected','duplicate','processed','failed')),
  idempotency_key text not null,
  correlation_id uuid not null,
  error_code text,
  metadata jsonb not null default '{}'::jsonb,
  unique(provider, idempotency_key)
);

create table if not exists public.api_credentials (
  id uuid primary key default gen_random_uuid(),
  organisation_id uuid not null,
  name text not null,
  key_prefix text not null,
  secret_hash text not null,
  scopes jsonb not null default '[]'::jsonb,
  allowed_ip_cidrs jsonb not null default '[]'::jsonb,
  expires_at timestamptz,
  revoked_at timestamptz,
  created_by uuid not null,
  created_at timestamptz not null default now(),
  last_used_at timestamptz
);

create table if not exists public.api_request_audit (
  id uuid primary key default gen_random_uuid(),
  credential_id uuid references public.api_credentials(id) on delete set null,
  organisation_id uuid,
  method text not null,
  route text not null,
  status_code integer not null,
  request_id text not null,
  correlation_id uuid,
  duration_ms integer not null,
  ip_hash text,
  user_agent_hash text,
  occurred_at timestamptz not null default now()
);

create table if not exists public.provider_health_checks (
  id uuid primary key default gen_random_uuid(),
  provider_key text not null,
  environment text not null default 'production' check (environment in ('sandbox','production')),
  status text not null check (status in ('not_configured','healthy','degraded','down','disabled')),
  latency_ms integer,
  consecutive_failures integer not null default 0,
  last_error_code text,
  checked_at timestamptz not null default now()
);

create index if not exists domain_events_org_time_idx on public.domain_events(organisation_id, occurred_at desc);
create index if not exists domain_events_project_time_idx on public.domain_events(project_id, occurred_at desc);
create index if not exists event_outbox_status_idx on public.event_outbox(status, available_at);
create index if not exists event_deliveries_status_idx on public.event_deliveries(status, next_attempt_at);
create index if not exists webhook_receipts_provider_time_idx on public.webhook_receipts(provider, received_at desc);
create index if not exists api_request_audit_time_idx on public.api_request_audit(occurred_at desc);

alter table public.event_definitions enable row level security;
alter table public.domain_events enable row level security;
alter table public.event_outbox enable row level security;
alter table public.event_subscriptions enable row level security;
alter table public.event_deliveries enable row level security;
alter table public.webhook_receipts enable row level security;
alter table public.api_credentials enable row level security;
alter table public.api_request_audit enable row level security;
alter table public.provider_health_checks enable row level security;

commit;
