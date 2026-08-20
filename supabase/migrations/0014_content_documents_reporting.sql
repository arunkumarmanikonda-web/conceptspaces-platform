begin;

create table if not exists public.content_entries (
  id uuid primary key default gen_random_uuid(),
  organisation_id uuid not null,
  content_key text not null,
  content_type text not null check (content_type in ('public_page','product_page','help_article','knowledge_article','seo_landing','legal_notice','email_template')),
  locale text not null default 'en-IN',
  title text not null,
  slug text,
  status text not null default 'draft' check (status in ('draft','review','approved','published','archived')),
  current_version integer not null default 1,
  seo jsonb not null default '{}'::jsonb,
  owner_user_id uuid,
  published_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique(organisation_id, content_key, locale)
);

create table if not exists public.content_versions (
  id uuid primary key default gen_random_uuid(),
  content_entry_id uuid not null references public.content_entries(id) on delete cascade,
  version integer not null,
  body jsonb not null default '{}'::jsonb,
  source_refs jsonb not null default '[]'::jsonb,
  change_reason text,
  created_by uuid not null,
  approved_by uuid,
  created_at timestamptz not null default now(),
  approved_at timestamptz,
  unique(content_entry_id, version)
);

create table if not exists public.brand_profiles (
  id uuid primary key default gen_random_uuid(),
  organisation_id uuid not null,
  name text not null,
  logo_asset_ref text not null,
  palette jsonb not null default '{}'::jsonb,
  typography jsonb not null default '{}'::jsonb,
  footer_text text,
  legal_entity_name text,
  website text,
  active boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists public.document_templates (
  id uuid primary key default gen_random_uuid(),
  organisation_id uuid not null,
  code text not null,
  name text not null,
  template_kind text not null check (template_kind in ('proposal','contract','client_presentation','design_report','feasibility_report','drawing_cover','drawing_register','transmittal','meeting_minutes','invoice','progress_report','handover_pack')),
  output_formats jsonb not null default '[]'::jsonb,
  required_data_paths jsonb not null default '[]'::jsonb,
  current_version integer not null default 1,
  active boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique(organisation_id, code)
);

create table if not exists public.template_versions (
  id uuid primary key default gen_random_uuid(),
  template_id uuid not null references public.document_templates(id) on delete cascade,
  version integer not null,
  schema_version text not null,
  template_ref text not null,
  checksum text not null,
  required_data_paths jsonb not null default '[]'::jsonb,
  locked boolean not null default false,
  created_by uuid not null,
  approved_by uuid,
  created_at timestamptz not null default now(),
  approved_at timestamptz,
  unique(template_id, version)
);

create table if not exists public.project_report_snapshots (
  id uuid primary key default gen_random_uuid(),
  project_id uuid not null,
  report_type text not null,
  as_of timestamptz not null default now(),
  project_truth_hash text not null,
  requirement_snapshot_hash text,
  regulatory_snapshot_hash text,
  commercial_snapshot_hash text,
  document_snapshot_hash text,
  source_refs jsonb not null default '[]'::jsonb,
  created_by uuid not null,
  created_at timestamptz not null default now()
);

create table if not exists public.generation_jobs (
  id uuid primary key default gen_random_uuid(),
  organisation_id uuid not null,
  project_id uuid,
  template_version_id uuid not null references public.template_versions(id),
  output_format text not null check (output_format in ('pdf','docx','xlsx','pptx','html','json','csv','zip')),
  status text not null default 'queued' check (status in ('queued','running','completed','failed','cancelled')),
  snapshot_id uuid references public.project_report_snapshots(id) on delete set null,
  input_hash text not null,
  output_hash text,
  requested_by uuid not null,
  error_code text,
  created_at timestamptz not null default now(),
  started_at timestamptz,
  completed_at timestamptz
);

create table if not exists public.generated_artifacts (
  id uuid primary key default gen_random_uuid(),
  generation_job_id uuid not null references public.generation_jobs(id) on delete cascade,
  project_id uuid,
  title text not null,
  output_format text not null check (output_format in ('pdf','docx','xlsx','pptx','html','json','csv','zip')),
  object_ref text not null,
  checksum text not null,
  status text not null default 'draft' check (status in ('draft','for_review','approved','issued','superseded','withdrawn')),
  revision text not null default 'P01',
  source_snapshot_id uuid references public.project_report_snapshots(id) on delete set null,
  template_version_id uuid not null references public.template_versions(id),
  issued_by uuid,
  issued_at timestamptz,
  created_at timestamptz not null default now()
);

create table if not exists public.publication_sets (
  id uuid primary key default gen_random_uuid(),
  project_id uuid not null,
  publication_number text not null,
  title text not null,
  revision text not null default 'P01',
  status text not null default 'draft' check (status in ('draft','for_review','approved','issued','superseded')),
  approved_by uuid,
  issued_by uuid,
  issued_at timestamptz,
  created_at timestamptz not null default now(),
  unique(project_id, publication_number, revision)
);

create table if not exists public.publication_set_items (
  id uuid primary key default gen_random_uuid(),
  publication_set_id uuid not null references public.publication_sets(id) on delete cascade,
  artifact_id uuid not null references public.generated_artifacts(id),
  purpose text not null check (purpose in ('information','review','approval','tender','construction','record','handover')),
  sequence integer not null default 0,
  unique(publication_set_id, artifact_id)
);

create index if not exists content_entries_org_status_idx on public.content_entries(organisation_id, status);
create index if not exists generation_jobs_project_status_idx on public.generation_jobs(project_id, status);
create index if not exists generated_artifacts_project_status_idx on public.generated_artifacts(project_id, status);
create index if not exists publication_sets_project_idx on public.publication_sets(project_id, created_at desc);

alter table public.content_entries enable row level security;
alter table public.content_versions enable row level security;
alter table public.brand_profiles enable row level security;
alter table public.document_templates enable row level security;
alter table public.template_versions enable row level security;
alter table public.project_report_snapshots enable row level security;
alter table public.generation_jobs enable row level security;
alter table public.generated_artifacts enable row level security;
alter table public.publication_sets enable row level security;
alter table public.publication_set_items enable row level security;

commit;
