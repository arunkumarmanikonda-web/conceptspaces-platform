-- Concept Spaces client intake, scope, professional assignment and engagement activation

create schema if not exists engagement;

create table if not exists engagement.intake_sessions (
  id uuid primary key default gen_random_uuid(),
  organisation_id uuid,
  contact_id uuid references public.contacts(id) on delete set null,
  opportunity_id uuid references public.opportunities(id) on delete set null,
  project_id uuid,
  current_step text not null default 'client' check (current_step in ('client','site','geometry','regulation','use','programme','interiors','scope','review')),
  status text not null default 'draft' check (status in ('draft','client_review','submitted','qualified','converted','cancelled')),
  client_payload jsonb not null default '{}'::jsonb,
  site_payload jsonb not null default '{}'::jsonb,
  geometry_payload jsonb not null default '{}'::jsonb,
  regulation_payload jsonb not null default '{}'::jsonb,
  programme_payload jsonb not null default '{}'::jsonb,
  interiors_payload jsonb not null default '{}'::jsonb,
  source_channel text,
  created_by uuid,
  submitted_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists engagement.scope_catalogue (
  id uuid primary key default gen_random_uuid(),
  code citext not null unique,
  name text not null,
  category text not null,
  description text not null,
  dependencies jsonb not null default '[]'::jsonb,
  pricing_models jsonb not null default '[]'::jsonb,
  default_state text not null default 'optional' check (default_state in ('included','optional','excluded')),
  active boolean not null default true,
  version integer not null default 1,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists engagement.scope_selections (
  id uuid primary key default gen_random_uuid(),
  intake_session_id uuid not null references engagement.intake_sessions(id) on delete cascade,
  module_code citext not null references engagement.scope_catalogue(code) on delete restrict,
  state text not null check (state in ('included','optional','excluded')),
  pricing_model text,
  quoted_amount numeric(18,2),
  currency char(3) not null default 'INR',
  notes text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique(intake_session_id,module_code)
);

create table if not exists engagement.client_portal_access (
  id uuid primary key default gen_random_uuid(),
  contact_id uuid not null references public.contacts(id) on delete cascade,
  project_id uuid,
  opportunity_id uuid references public.opportunities(id) on delete cascade,
  role text not null check (role in ('client_owner','client_representative','client_finance','client_viewer')),
  status text not null default 'invited' check (status in ('invited','active','suspended','revoked')),
  invited_by uuid,
  invited_at timestamptz,
  activated_at timestamptz,
  revoked_at timestamptz,
  created_at timestamptz not null default now()
);

create table if not exists engagement.professional_role_requirements (
  id uuid primary key default gen_random_uuid(),
  project_id uuid not null,
  role_code citext not null,
  discipline text not null,
  stage text not null,
  required boolean not null default true,
  credential_types jsonb not null default '[]'::jsonb,
  capacity_hours numeric(12,2),
  location_preference text,
  created_at timestamptz not null default now(),
  unique(project_id,role_code,stage)
);

create table if not exists engagement.project_professional_assignments (
  id uuid primary key default gen_random_uuid(),
  project_id uuid not null,
  role_code citext not null,
  discipline text not null,
  user_id uuid,
  professional_profile_id uuid,
  state text not null default 'proposed' check (state in ('proposed','invited','accepted','active','completed','declined','removed')),
  starts_at timestamptz,
  ends_at timestamptz,
  allocation_percent numeric(7,3),
  appointment_ref text,
  assigned_by uuid,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists engagement.proposal_negotiation_events (
  id uuid primary key default gen_random_uuid(),
  proposal_id uuid not null references public.proposals(id) on delete cascade,
  version integer not null,
  party text not null check (party in ('client','concept_spaces')),
  event_type text not null check (event_type in ('sent','counter_offer','scope_change','commercial_note','accepted','rejected','expired')),
  amount numeric(18,2),
  currency char(3) default 'INR',
  scope_delta jsonb,
  note text,
  actor_user_id uuid,
  created_at timestamptz not null default now()
);

create table if not exists engagement.activations (
  id uuid primary key default gen_random_uuid(),
  opportunity_id uuid not null references public.opportunities(id) on delete restrict,
  proposal_id uuid not null references public.proposals(id) on delete restrict,
  contract_id uuid references public.contracts(id) on delete restrict,
  project_id uuid,
  proposal_accepted boolean not null default false,
  contract_executed boolean not null default false,
  initial_payment_satisfied boolean not null default false,
  required_kyc_satisfied boolean not null default false,
  state text not null default 'pending' check (state in ('pending','ready','activated','blocked')),
  blocked_reason text,
  activated_by uuid,
  activated_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique(opportunity_id)
);

create index if not exists ix_intake_status on engagement.intake_sessions(status,created_at desc);
create index if not exists ix_scope_intake on engagement.scope_selections(intake_session_id,state);
create index if not exists ix_client_portal_project on engagement.client_portal_access(project_id,status);
create index if not exists ix_professional_assignment_project on engagement.project_professional_assignments(project_id,discipline,state);
create index if not exists ix_negotiation_proposal on engagement.proposal_negotiation_events(proposal_id,created_at);

alter table engagement.intake_sessions enable row level security;
alter table engagement.scope_catalogue enable row level security;
alter table engagement.scope_selections enable row level security;
alter table engagement.client_portal_access enable row level security;
alter table engagement.professional_role_requirements enable row level security;
alter table engagement.project_professional_assignments enable row level security;
alter table engagement.proposal_negotiation_events enable row level security;
alter table engagement.activations enable row level security;
