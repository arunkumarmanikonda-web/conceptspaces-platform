begin;

create schema if not exists finance;

create table if not exists finance.fiscal_periods (
  id uuid primary key default gen_random_uuid(),
  organisation_id uuid not null references core.organisations(id) on delete cascade,
  fiscal_year text not null,
  period_code text not null,
  start_date date not null,
  end_date date not null,
  status text not null default 'open' check (status in ('open','soft_closed','closed')),
  unique(organisation_id, period_code)
);

create table if not exists finance.ledger_accounts (
  id uuid primary key default gen_random_uuid(),
  organisation_id uuid not null references core.organisations(id) on delete cascade,
  code citext not null,
  name text not null,
  account_type text not null check (account_type in ('asset','liability','equity','income','expense')),
  parent_id uuid references finance.ledger_accounts(id),
  currency text,
  active boolean not null default true,
  metadata jsonb not null default '{}'::jsonb,
  unique(organisation_id, code)
);

create table if not exists finance.journals (
  id uuid primary key default gen_random_uuid(),
  organisation_id uuid not null references core.organisations(id) on delete cascade,
  journal_number citext not null,
  posting_date date not null,
  status text not null default 'draft' check (status in ('draft','posted','reversed')),
  source_type text not null,
  source_id uuid,
  reversal_of_id uuid references finance.journals(id),
  created_by uuid references auth.users(id),
  posted_by uuid references auth.users(id),
  posted_at timestamptz,
  created_at timestamptz not null default now(),
  unique(organisation_id, journal_number)
);

create table if not exists finance.journal_lines (
  id uuid primary key default gen_random_uuid(),
  journal_id uuid not null references finance.journals(id) on delete cascade,
  account_id uuid not null references finance.ledger_accounts(id) on delete restrict,
  project_id uuid references project.projects(id) on delete set null,
  cost_code text,
  counterparty_id uuid,
  debit numeric(18,2) not null default 0 check (debit >= 0),
  credit numeric(18,2) not null default 0 check (credit >= 0),
  currency text not null default 'INR',
  tax_determination_id uuid,
  memo text,
  check (not (debit > 0 and credit > 0))
);

create table if not exists finance.tax_rules (
  id uuid primary key default gen_random_uuid(),
  rule_set text not null,
  code citext not null,
  jurisdiction text not null default 'IN',
  effective_from date not null,
  effective_until date,
  priority integer not null default 100,
  conditions jsonb not null default '{}'::jsonb,
  outcome jsonb not null default '{}'::jsonb,
  source_reference text not null,
  publication_status text not null default 'draft' check (publication_status in ('draft','review','published','retired')),
  approved_by uuid references auth.users(id),
  approved_at timestamptz,
  created_at timestamptz not null default now(),
  unique(rule_set, code, effective_from)
);

create table if not exists finance.tax_determinations (
  id uuid primary key default gen_random_uuid(),
  organisation_id uuid not null references core.organisations(id) on delete cascade,
  transaction_date date not null,
  source_type text not null,
  source_id uuid,
  context jsonb not null,
  rule_ids jsonb not null default '[]'::jsonb,
  components jsonb not null default '[]'::jsonb,
  status text not null check (status in ('determined','needs_review','not_verified')),
  explanation jsonb not null default '[]'::jsonb,
  determined_at timestamptz not null default now()
);

alter table finance.journal_lines
  add constraint journal_lines_tax_determination_fk
  foreign key (tax_determination_id) references finance.tax_determinations(id) deferrable initially deferred;

create table if not exists finance.bank_accounts (
  id uuid primary key default gen_random_uuid(),
  organisation_id uuid not null references core.organisations(id) on delete cascade,
  bank_name text not null,
  account_name text not null,
  masked_account_number text not null,
  ifsc text,
  currency text not null default 'INR',
  active boolean not null default true,
  unique(organisation_id, bank_name, masked_account_number)
);

create table if not exists finance.bank_transactions (
  id uuid primary key default gen_random_uuid(),
  bank_account_id uuid not null references finance.bank_accounts(id) on delete cascade,
  booked_at timestamptz not null,
  value_date date,
  amount numeric(18,2) not null,
  currency text not null default 'INR',
  direction text not null check (direction in ('credit','debit')),
  reference text,
  counterparty text,
  matched_journal_line_id uuid references finance.journal_lines(id) on delete set null,
  reconciliation_status text not null default 'unmatched' check (reconciliation_status in ('unmatched','suggested','matched','excluded')),
  raw_payload jsonb not null default '{}'::jsonb
);

create table if not exists finance.budgets (
  id uuid primary key default gen_random_uuid(),
  organisation_id uuid not null references core.organisations(id) on delete cascade,
  project_id uuid references project.projects(id) on delete cascade,
  fiscal_year text not null,
  version integer not null default 1,
  status text not null default 'draft' check (status in ('draft','approved','superseded')),
  currency text not null default 'INR',
  approved_by uuid references auth.users(id),
  approved_at timestamptz,
  unique(organisation_id, project_id, fiscal_year, version)
);

create table if not exists finance.budget_lines (
  id uuid primary key default gen_random_uuid(),
  budget_id uuid not null references finance.budgets(id) on delete cascade,
  account_id uuid not null references finance.ledger_accounts(id) on delete restrict,
  cost_code text,
  period_code text,
  amount numeric(18,2) not null default 0
);

create table if not exists finance.fixed_assets (
  id uuid primary key default gen_random_uuid(),
  organisation_id uuid not null references core.organisations(id) on delete cascade,
  asset_code citext not null,
  description text not null,
  acquisition_date date,
  acquisition_cost numeric(18,2) not null default 0,
  useful_life_months integer,
  residual_value numeric(18,2) not null default 0,
  depreciation_method text,
  status text not null default 'active' check (status in ('active','disposed','written_off')),
  unique(organisation_id, asset_code)
);

create index if not exists finance_journal_lines_project_idx on finance.journal_lines(project_id, account_id);
create index if not exists finance_tax_rules_effective_idx on finance.tax_rules(rule_set, jurisdiction, effective_from, effective_until);
create index if not exists finance_bank_transactions_match_idx on finance.bank_transactions(bank_account_id, reconciliation_status, booked_at desc);
create index if not exists finance_budgets_project_idx on finance.budgets(project_id, fiscal_year, version desc);

alter table finance.fiscal_periods enable row level security;
alter table finance.ledger_accounts enable row level security;
alter table finance.journals enable row level security;
alter table finance.journal_lines enable row level security;
alter table finance.tax_rules enable row level security;
alter table finance.tax_determinations enable row level security;
alter table finance.bank_accounts enable row level security;
alter table finance.bank_transactions enable row level security;
alter table finance.budgets enable row level security;
alter table finance.budget_lines enable row level security;
alter table finance.fixed_assets enable row level security;

commit;
