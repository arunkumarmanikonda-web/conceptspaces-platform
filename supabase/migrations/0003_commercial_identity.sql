begin;

create table if not exists public.contacts (
  id uuid primary key default gen_random_uuid(),
  organisation_id uuid not null,
  full_name text not null,
  company_name text,
  email text,
  phone text,
  role_title text,
  consent_email boolean not null default false,
  consent_whatsapp boolean not null default false,
  consent_sms boolean not null default false,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists public.leads (
  id uuid primary key default gen_random_uuid(),
  organisation_id uuid not null,
  contact_id uuid references public.contacts(id) on delete set null,
  source text not null,
  status text not null check (status in ('new','qualified','nurture','won','lost')),
  project_typology text,
  project_location text,
  estimated_project_value numeric(18,2),
  currency text not null default 'INR',
  owner_user_id uuid,
  next_action_at timestamptz,
  metadata jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists public.opportunities (
  id uuid primary key default gen_random_uuid(),
  organisation_id uuid not null,
  lead_id uuid references public.leads(id) on delete set null,
  contact_id uuid references public.contacts(id) on delete set null,
  project_name text not null,
  stage text not null check (stage in ('discovery','briefing','proposal','negotiation','contracting','won','lost')),
  probability numeric(5,2) not null default 0 check (probability between 0 and 100),
  expected_fee numeric(18,2),
  currency text not null default 'INR',
  scope_modules jsonb not null default '[]'::jsonb,
  decision_due_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists public.proposals (
  id uuid primary key default gen_random_uuid(),
  organisation_id uuid not null,
  opportunity_id uuid not null references public.opportunities(id) on delete cascade,
  version integer not null default 1,
  status text not null check (status in ('draft','internal_review','sent','countered','accepted','rejected','expired')),
  currency text not null default 'INR',
  subtotal numeric(18,2) not null default 0,
  tax numeric(18,2) not null default 0,
  total numeric(18,2) not null default 0,
  valid_until date,
  commercial_notes jsonb not null default '[]'::jsonb,
  client_counter_offer numeric(18,2),
  approved_by uuid,
  approved_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique(opportunity_id, version)
);

create table if not exists public.proposal_lines (
  id uuid primary key default gen_random_uuid(),
  proposal_id uuid not null references public.proposals(id) on delete cascade,
  title text not null,
  scope_code text not null,
  pricing_model text not null check (pricing_model in ('fixed','percent','sqft','per_key','hourly','retainer','milestone','subscription','hybrid')),
  quantity numeric(18,4) not null default 1,
  rate numeric(18,2) not null default 0,
  tax_code text,
  amount numeric(18,2) not null default 0,
  optional boolean not null default false,
  sort_order integer not null default 0
);

create table if not exists public.contracts (
  id uuid primary key default gen_random_uuid(),
  organisation_id uuid not null,
  proposal_id uuid references public.proposals(id) on delete set null,
  project_id uuid,
  version integer not null default 1,
  status text not null check (status in ('draft','negotiation','signature_pending','active','suspended','completed','terminated')),
  effective_at timestamptz,
  expires_at timestamptz,
  signature_provider text,
  signature_envelope_id text,
  contract_snapshot jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists public.contract_obligations (
  id uuid primary key default gen_random_uuid(),
  contract_id uuid not null references public.contracts(id) on delete cascade,
  party text not null check (party in ('client','concept_spaces','consultant','contractor')),
  obligation text not null,
  due_at timestamptz,
  evidence_required text,
  status text not null default 'open' check (status in ('open','met','waived','breached')),
  completed_at timestamptz
);

create table if not exists public.invoices (
  id uuid primary key default gen_random_uuid(),
  organisation_id uuid not null,
  project_id uuid,
  contract_id uuid references public.contracts(id) on delete set null,
  invoice_number text not null,
  status text not null check (status in ('draft','issued','part_paid','paid','overdue','void')),
  currency text not null default 'INR',
  issue_date date not null,
  due_date date not null,
  subtotal numeric(18,2) not null default 0,
  tax numeric(18,2) not null default 0,
  total numeric(18,2) not null default 0,
  amount_paid numeric(18,2) not null default 0,
  tds_receivable numeric(18,2) not null default 0,
  metadata jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique(organisation_id, invoice_number)
);

create table if not exists public.invoice_lines (
  id uuid primary key default gen_random_uuid(),
  invoice_id uuid not null references public.invoices(id) on delete cascade,
  description text not null,
  quantity numeric(18,4) not null default 1,
  rate numeric(18,2) not null default 0,
  taxable_amount numeric(18,2) not null default 0,
  gst_rate numeric(7,4),
  tax_amount numeric(18,2) not null default 0,
  total numeric(18,2) not null default 0,
  sort_order integer not null default 0
);

create table if not exists public.payment_transactions (
  id uuid primary key default gen_random_uuid(),
  organisation_id uuid not null,
  invoice_id uuid references public.invoices(id) on delete set null,
  provider text not null,
  provider_order_id text,
  provider_payment_id text,
  provider_event_id text,
  amount numeric(18,2) not null,
  currency text not null default 'INR',
  status text not null check (status in ('created','authorized','captured','failed','refunded','part_refunded')),
  idempotency_key text not null,
  metadata jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique(provider, idempotency_key)
);

create table if not exists public.communication_intents (
  id uuid primary key default gen_random_uuid(),
  organisation_id uuid not null,
  channel text not null check (channel in ('email','whatsapp','sms','in_app')),
  recipient text not null,
  template_code text not null,
  locale text default 'en-IN',
  project_id uuid,
  commercial_object_type text,
  commercial_object_id uuid,
  payload jsonb not null default '{}'::jsonb,
  consent_basis text,
  send_after timestamptz,
  status text not null default 'queued' check (status in ('queued','processing','sent','failed','cancelled')),
  provider text,
  provider_message_id text,
  attempt_count integer not null default 0,
  last_error text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create index if not exists leads_org_status_idx on public.leads(organisation_id, status);
create index if not exists opportunities_org_stage_idx on public.opportunities(organisation_id, stage);
create index if not exists proposals_opportunity_idx on public.proposals(opportunity_id, version desc);
create index if not exists invoices_org_due_idx on public.invoices(organisation_id, due_date);
create index if not exists communication_queue_idx on public.communication_intents(status, send_after);

alter table public.contacts enable row level security;
alter table public.leads enable row level security;
alter table public.opportunities enable row level security;
alter table public.proposals enable row level security;
alter table public.proposal_lines enable row level security;
alter table public.contracts enable row level security;
alter table public.contract_obligations enable row level security;
alter table public.invoices enable row level security;
alter table public.invoice_lines enable row level security;
alter table public.payment_transactions enable row level security;
alter table public.communication_intents enable row level security;

commit;
