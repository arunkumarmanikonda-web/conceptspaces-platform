begin;

create table if not exists core.roles (
  code text primary key,
  name text not null,
  description text,
  system_role boolean not null default false,
  created_at timestamptz not null default now()
);

create table if not exists core.permissions (
  code text primary key,
  resource text not null,
  action text not null,
  description text,
  criticality text not null default 'C1' check (criticality in ('C0','C1','C2','C3','C4')),
  unique(resource, action)
);

create table if not exists core.role_permissions (
  role_code text not null references core.roles(code) on delete cascade,
  permission_code text not null references core.permissions(code) on delete cascade,
  conditions jsonb not null default '{}'::jsonb,
  primary key(role_code, permission_code)
);

create table if not exists core.invitations (
  id uuid primary key default gen_random_uuid(),
  organisation_id uuid not null references core.organisations(id) on delete cascade,
  email citext not null,
  role_codes text[] not null default '{}',
  project_ids uuid[] not null default '{}',
  token_hash text not null,
  status text not null default 'pending' check (status in ('pending','accepted','revoked','expired')),
  invited_by uuid references auth.users(id),
  expires_at timestamptz not null,
  accepted_by uuid references auth.users(id),
  accepted_at timestamptz,
  created_at timestamptz not null default now()
);

create table if not exists core.access_reviews (
  id uuid primary key default gen_random_uuid(),
  organisation_id uuid not null references core.organisations(id) on delete cascade,
  review_type text not null,
  status text not null default 'open' check (status in ('open','in_progress','completed','cancelled')),
  due_at timestamptz,
  initiated_by uuid references auth.users(id),
  completed_by uuid references auth.users(id),
  completed_at timestamptz,
  created_at timestamptz not null default now()
);

create table if not exists core.access_review_items (
  id uuid primary key default gen_random_uuid(),
  review_id uuid not null references core.access_reviews(id) on delete cascade,
  user_id uuid not null references auth.users(id) on delete cascade,
  membership_id uuid references core.memberships(id) on delete cascade,
  decision text check (decision in ('retain','modify','revoke')),
  rationale text,
  reviewed_by uuid references auth.users(id),
  reviewed_at timestamptz
);

insert into core.roles(code,name,description,system_role) values
  ('super_admin','Super Admin','Platform-wide configuration and governance',true),
  ('org_admin','Organisation Admin','Organisation administration',true),
  ('lead_architect','Lead Architect','Project design authority and SPOC',true),
  ('architect','Architect','Architecture discipline contributor',true),
  ('structural_engineer','Structural Engineer','Structural discipline contributor',true),
  ('mep_engineer','MEP Engineer','MEP discipline contributor',true),
  ('interior_designer','Interior Designer','Interior discipline contributor',true),
  ('quantity_surveyor','Quantity Surveyor','Cost and quantity discipline contributor',true),
  ('project_manager','Project Manager','Programme and delivery management',true),
  ('finance','Finance','Commercial and finance operations',true),
  ('sales','Sales','CRM and opportunity management',true),
  ('client','Client','Client portal access',true)
on conflict(code) do nothing;

insert into core.permissions(code,resource,action,description,criticality) values
  ('project.read','project','read','Read project information','C1'),
  ('project.create','project','create','Create project','C1'),
  ('truth.verify','truth_record','verify','Verify a Project Truth record','C3'),
  ('release.review','release','review','Review a release package','C3'),
  ('release.approve','release','approve','Approve a critical release package','C4'),
  ('proposal.approve','proposal','approve','Approve commercial proposal','C2'),
  ('invoice.issue','invoice','issue','Issue client invoice','C2'),
  ('payment.reconcile','payment','reconcile','Reconcile verified payment event','C2'),
  ('integration.configure','integration','configure','Configure provider integration','C3'),
  ('admin.access','admin','access','Access Super Admin','C3')
on conflict(code) do nothing;

alter table core.roles enable row level security;
alter table core.permissions enable row level security;
alter table core.role_permissions enable row level security;
alter table core.invitations enable row level security;
alter table core.access_reviews enable row level security;
alter table core.access_review_items enable row level security;

commit;
