begin;

create schema if not exists cde;
create schema if not exists coordination;

create table if not exists cde.documents (
  id uuid primary key default gen_random_uuid(),
  project_id uuid not null references project.projects(id) on delete cascade,
  document_number citext not null,
  title text not null,
  discipline text not null,
  document_type text not null,
  cde_state text not null default 'work_in_progress' check (cde_state in ('work_in_progress','shared','published','archived')),
  status text not null default 'draft' check (status in ('draft','for_review','for_approval','approved','issued','superseded','withdrawn')),
  revision text not null default 'P01',
  scale text,
  current_version_id uuid,
  authored_by uuid references auth.users(id),
  checked_by uuid references auth.users(id),
  approved_by uuid references auth.users(id),
  metadata jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique(project_id, document_number, revision)
);

create table if not exists cde.file_versions (
  id uuid primary key default gen_random_uuid(),
  document_id uuid not null references cde.documents(id) on delete cascade,
  version integer not null,
  object_key text not null,
  mime_type text not null,
  size_bytes bigint not null check (size_bytes >= 0),
  checksum text not null,
  created_by uuid references auth.users(id),
  created_at timestamptz not null default now(),
  unique(document_id, version),
  unique(object_key)
);

alter table cde.documents
  add constraint documents_current_version_fk
  foreign key (current_version_id) references cde.file_versions(id) deferrable initially deferred;

create table if not exists cde.models (
  id uuid primary key default gen_random_uuid(),
  project_id uuid not null references project.projects(id) on delete cascade,
  discipline text not null,
  model_name text not null,
  format text not null,
  schema_version text,
  object_key text not null unique,
  checksum text not null,
  coordinate_system text,
  status text not null default 'draft' check (status in ('draft','for_review','for_approval','approved','issued','superseded','withdrawn')),
  created_by uuid references auth.users(id),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists coordination.issues (
  id uuid primary key default gen_random_uuid(),
  project_id uuid not null references project.projects(id) on delete cascade,
  issue_number citext not null,
  issue_type text not null check (issue_type in ('coordination','design','rfi','quality','regulatory','commercial','site')),
  title text not null,
  description text not null,
  status text not null default 'open' check (status in ('open','in_progress','answered','resolved','closed')),
  priority text not null default 'medium' check (priority in ('low','medium','high','critical')),
  criticality text not null default 'C1' check (criticality in ('C0','C1','C2','C3','C4')),
  assignee_id uuid references auth.users(id),
  due_at timestamptz,
  bcf_topic_ref text,
  location_ref text,
  created_by uuid references auth.users(id),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  closed_at timestamptz,
  unique(project_id, issue_number)
);

create table if not exists coordination.issue_links (
  issue_id uuid not null references coordination.issues(id) on delete cascade,
  resource_type text not null check (resource_type in ('document','model','truth_record','requirement','design_option','release','site_photo')),
  resource_id uuid not null,
  relationship text not null default 'related',
  primary key(issue_id, resource_type, resource_id)
);

create table if not exists coordination.issue_comments (
  id uuid primary key default gen_random_uuid(),
  issue_id uuid not null references coordination.issues(id) on delete cascade,
  body text not null,
  author_id uuid references auth.users(id),
  evidence_refs jsonb not null default '[]'::jsonb,
  created_at timestamptz not null default now()
);

create table if not exists coordination.approval_requests (
  id uuid primary key default gen_random_uuid(),
  project_id uuid not null references project.projects(id) on delete cascade,
  resource_type text not null check (resource_type in ('document','model','design_option','release','commercial','change')),
  resource_id uuid not null,
  requested_from uuid references auth.users(id),
  role_required text,
  criticality text not null default 'C1' check (criticality in ('C0','C1','C2','C3','C4')),
  decision text not null default 'pending' check (decision in ('pending','approved','approved_with_comments','rejected')),
  comments text,
  requested_by uuid references auth.users(id),
  requested_at timestamptz not null default now(),
  decided_at timestamptz,
  decision_evidence_hash text
);

create table if not exists cde.transmittals (
  id uuid primary key default gen_random_uuid(),
  project_id uuid not null references project.projects(id) on delete cascade,
  transmittal_number citext not null,
  sender_id uuid references auth.users(id),
  recipient_refs jsonb not null default '[]'::jsonb,
  message text,
  acknowledgement_required boolean not null default false,
  issued_at timestamptz,
  created_at timestamptz not null default now(),
  unique(project_id, transmittal_number)
);

create table if not exists cde.transmittal_items (
  id uuid primary key default gen_random_uuid(),
  transmittal_id uuid not null references cde.transmittals(id) on delete cascade,
  document_id uuid references cde.documents(id) on delete restrict,
  model_id uuid references cde.models(id) on delete restrict,
  purpose text not null check (purpose in ('information','review','approval','construction','record')),
  check ((document_id is not null and model_id is null) or (document_id is null and model_id is not null))
);

create index if not exists cde_documents_project_idx on cde.documents(project_id, cde_state, status);
create index if not exists cde_models_project_idx on cde.models(project_id, discipline, status);
create index if not exists coordination_issues_project_idx on coordination.issues(project_id, status, criticality);
create index if not exists approvals_project_idx on coordination.approval_requests(project_id, decision, criticality);
create index if not exists transmittals_project_idx on cde.transmittals(project_id, issued_at desc);

alter table cde.documents enable row level security;
alter table cde.file_versions enable row level security;
alter table cde.models enable row level security;
alter table coordination.issues enable row level security;
alter table coordination.issue_links enable row level security;
alter table coordination.issue_comments enable row level security;
alter table coordination.approval_requests enable row level security;
alter table cde.transmittals enable row level security;
alter table cde.transmittal_items enable row level security;

commit;
