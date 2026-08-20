-- Concept Spaces integration registry
-- Prepared for Supabase/PostgreSQL. Not applied until a dedicated project is provisioned.

create schema if not exists integration;

create table if not exists integration.providers (
  provider_key text primary key,
  display_name text not null,
  category text not null,
  supports_sandbox boolean not null default false,
  webhook_capable boolean not null default false,
  metadata jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists integration.instances (
  id uuid primary key default gen_random_uuid(),
  organisation_id uuid not null references core.organisations(id) on delete cascade,
  provider_key text not null references integration.providers(provider_key),
  environment text not null check (environment in ('sandbox','production')),
  status text not null default 'not_configured' check (status in ('not_configured','configured','verified','degraded','disabled')),
  enabled boolean not null default false,
  config jsonb not null default '{}'::jsonb,
  secret_refs jsonb not null default '{}'::jsonb,
  verified_at timestamptz,
  last_health_check_at timestamptz,
  last_health_status text,
  created_by uuid references auth.users(id),
  updated_by uuid references auth.users(id),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (organisation_id, provider_key, environment)
);

create table if not exists integration.webhook_events (
  id uuid primary key default gen_random_uuid(),
  organisation_id uuid references core.organisations(id) on delete cascade,
  provider_key text not null,
  environment text not null check (environment in ('sandbox','production')),
  provider_event_id text,
  event_type text,
  signature_valid boolean not null default false,
  headers_redacted jsonb not null default '{}'::jsonb,
  payload jsonb,
  payload_hash text not null,
  processing_status text not null default 'received' check (processing_status in ('received','verified','processing','processed','rejected','failed')),
  error jsonb,
  correlation_id uuid not null default gen_random_uuid(),
  received_at timestamptz not null default now(),
  processed_at timestamptz,
  unique nulls not distinct (provider_key, environment, provider_event_id)
);

create table if not exists integration.outbound_messages (
  id uuid primary key default gen_random_uuid(),
  organisation_id uuid not null references core.organisations(id) on delete cascade,
  project_id uuid references project.projects(id) on delete set null,
  channel text not null check (channel in ('email','whatsapp','sms')),
  provider_key text not null,
  environment text not null check (environment in ('sandbox','production')),
  idempotency_key text not null,
  recipient text not null,
  purpose text not null,
  template_key text,
  template_version text,
  subject text,
  body_hash text,
  variables jsonb not null default '{}'::jsonb,
  status text not null default 'queued' check (status in ('queued','accepted','sent','delivered','failed','cancelled')),
  provider_message_id text,
  error jsonb,
  created_by uuid references auth.users(id),
  created_at timestamptz not null default now(),
  sent_at timestamptz,
  delivered_at timestamptz,
  unique (organisation_id, channel, idempotency_key)
);

create table if not exists integration.payment_transactions (
  id uuid primary key default gen_random_uuid(),
  organisation_id uuid not null references core.organisations(id) on delete cascade,
  project_id uuid references project.projects(id) on delete set null,
  provider_key text not null,
  environment text not null check (environment in ('sandbox','production')),
  idempotency_key text not null,
  reference text not null,
  amount_minor bigint not null check (amount_minor >= 0),
  currency char(3) not null,
  provider_payment_id text,
  status text not null default 'created' check (status in ('created','authorized','captured','failed','refunded','partially_refunded','cancelled')),
  metadata jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (organisation_id, provider_key, idempotency_key)
);

create table if not exists integration.ai_model_profiles (
  id uuid primary key default gen_random_uuid(),
  organisation_id uuid not null references core.organisations(id) on delete cascade,
  provider_key text not null,
  model text not null,
  purpose text not null check (purpose in ('orchestration','vision','reasoning','speech','embedding','rendering','document','code')),
  enabled boolean not null default false,
  max_autonomy text not null default 'ai_draft' check (max_autonomy in ('human_only','ai_advisory','ai_draft','execute_after_approval','bounded_autonomous')),
  allowed_criticalities jsonb not null default '["C0","C1"]'::jsonb,
  data_classification text not null default 'project_confidential',
  config jsonb not null default '{}'::jsonb,
  secret_ref text,
  created_by uuid references auth.users(id),
  updated_by uuid references auth.users(id),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (organisation_id, provider_key, model, purpose)
);

alter table integration.providers enable row level security;
alter table integration.instances enable row level security;
alter table integration.webhook_events enable row level security;
alter table integration.outbound_messages enable row level security;
alter table integration.payment_transactions enable row level security;
alter table integration.ai_model_profiles enable row level security;

create policy providers_authenticated_read on integration.providers
for select to authenticated using (true);

create policy instances_org_read on integration.instances
for select using (core.is_org_member(organisation_id));

create policy outbound_messages_org_read on integration.outbound_messages
for select using (core.is_org_member(organisation_id));

create policy payment_transactions_org_read on integration.payment_transactions
for select using (core.is_org_member(organisation_id));

create policy ai_model_profiles_org_read on integration.ai_model_profiles
for select using (core.is_org_member(organisation_id));

-- webhook_events intentionally has no authenticated client policy.
-- Inbound handlers use service-role/server credentials after signature verification.

insert into integration.providers(provider_key,display_name,category,supports_sandbox,webhook_capable)
values
  ('godaddy','GoDaddy','dns',false,false),
  ('resend','Resend','email',true,true),
  ('razorpay','Razorpay','payments',true,true),
  ('aisensy','AiSensy','whatsapp',false,true),
  ('fast2sms','Fast2SMS','sms',false,false)
on conflict (provider_key) do update set
  display_name = excluded.display_name,
  category = excluded.category,
  supports_sandbox = excluded.supports_sandbox,
  webhook_capable = excluded.webhook_capable,
  updated_at = now();
