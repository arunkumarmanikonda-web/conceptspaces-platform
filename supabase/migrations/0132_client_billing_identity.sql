begin;

create table public.client_accounts (
  id uuid primary key default gen_random_uuid(),
  organisation_id uuid not null references core.organisations(id) on delete restrict,
  display_name text not null,
  legal_name text not null,
  email text,
  phone text,
  gst_registered boolean not null,
  gstin text,
  gst_state_code text generated always as (case when gstin is null then null else left(gstin,2) end) stored,
  billing_address text,
  billing_state text,
  gst_verification_status text not null check (gst_verification_status in ('not_applicable','client_declared','verified','rejected')),
  created_by uuid not null references auth.users(id) on delete restrict,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (organisation_id,id),
  constraint client_accounts_gst_identity_check check (
    (not gst_registered and gstin is null and gst_verification_status = 'not_applicable')
    or
    (gst_registered and gstin ~ '^[0-9]{2}[A-Z]{5}[0-9]{4}[A-Z][1-9A-Z]Z[0-9A-Z]$' and gst_verification_status in ('client_declared','verified','rejected'))
  )
);

comment on table public.client_accounts is
'Canonical client billing identities. GST details are client-declared until separately verified.';
comment on column public.client_accounts.gst_state_code is
'Two-character state or union-territory code derived from the GSTIN; billing_state remains the human-readable declaration.';

create unique index client_accounts_org_gstin_unique
  on public.client_accounts(organisation_id,gstin)
  where gstin is not null;
create index client_accounts_org_name_idx
  on public.client_accounts(organisation_id,legal_name);

alter table public.client_accounts enable row level security;
create policy client_accounts_read on public.client_accounts
for select to authenticated
using (core.is_internal_org_member(organisation_id));
create policy client_accounts_insert on public.client_accounts
for insert to authenticated
with check (
  created_by = (select auth.uid())
  and core.has_org_role(
    organisation_id,
    array['super_admin','org_admin','sales','lead_architect','project_manager']
  )
);

grant select, insert on public.client_accounts to authenticated;

alter table project.projects
  add column client_account_id uuid;
alter table project.projects
  add constraint projects_client_account_organisation_fk
  foreign key (organisation_id,client_account_id)
  references public.client_accounts(organisation_id,id)
  on delete restrict;
create index projects_client_account_idx
  on project.projects(client_account_id)
  where client_account_id is not null;

create or replace function public.submit_project_intake(input_payload jsonb, scope_modules text[] default '{}'::text[])
returns jsonb
language plpgsql
security invoker
set search_path = core, project, engagement, public, extensions
as $$
declare
  actor uuid := auth.uid();
  actor_org uuid;
  actor_role text;
  new_project uuid;
  new_intake uuid;
  new_client_account uuid;
  new_code text;
  client_name text := nullif(btrim(input_payload#>>'{client,name}'),'');
  billing_legal_name text;
  billing_address text := nullif(btrim(input_payload#>>'{client,billing,address}'),'');
  billing_state text := nullif(btrim(input_payload#>>'{client,billing,state}'),'');
  billing_gstin text := upper(regexp_replace(coalesce(input_payload#>>'{client,billing,gstin}',''),'[[:space:]-]+','','g'));
  billing_gst_registered boolean;
  project_name text := nullif(btrim(input_payload#>>'{project,name}'),'');
  typology_name text := nullif(btrim(input_payload#>>'{project,typology}'),'');
  site_parcels jsonb := coalesce(input_payload#>'{site,parcels}','[]'::jsonb);
  parcel_geometry jsonb := coalesce(input_payload#>'{geometry,parcels}','[]'::jsonb);
  combined_boundary jsonb := coalesce(input_payload#>'{geometry,combinedBoundary}','{}'::jsonb);
  geometry_has_evidence boolean := coalesce(nullif(btrim(input_payload#>>'{geometry,evidence}'),'') is not null,false);
  legacy_geometry_has_sides boolean :=
    nullif(btrim(input_payload#>>'{geometry,side1}'),'') is not null and
    nullif(btrim(input_payload#>>'{geometry,side2}'),'') is not null and
    nullif(btrim(input_payload#>>'{geometry,side3}'),'') is not null and
    nullif(btrim(input_payload#>>'{geometry,side4}'),'') is not null;
  module text;
begin
  if actor is null then raise exception 'authentication_required'; end if;
  if project_name is null or typology_name is null or client_name is null then
    raise exception 'client_project_and_typology_required';
  end if;
  if jsonb_typeof(input_payload#>'{client,billing,gstRegistered}') is distinct from 'boolean' then
    raise exception 'gst_registration_status_required';
  end if;
  billing_gst_registered := (input_payload#>>'{client,billing,gstRegistered}')::boolean;
  billing_legal_name := coalesce(
    nullif(btrim(input_payload#>>'{client,billing,legalName}'),''),
    nullif(btrim(input_payload#>>'{client,organisation}'),''),
    client_name
  );
  if billing_gst_registered and (billing_address is null or billing_state is null or nullif(billing_gstin,'') is null) then
    raise exception 'registered_client_billing_identity_required';
  end if;
  if billing_gst_registered and billing_gstin !~ '^[0-9]{2}[A-Z]{5}[0-9]{4}[A-Z][1-9A-Z]Z[0-9A-Z]$' then
    raise exception 'valid_gstin_required';
  end if;
  if not billing_gst_registered then billing_gstin := null; end if;
  if jsonb_typeof(site_parcels) <> 'array' or jsonb_array_length(site_parcels) = 0 then
    raise exception 'site_parcels_required';
  end if;

  select m.organisation_id, m.role_code into actor_org, actor_role
  from core.memberships m
  where m.user_id = actor and m.status = 'active'
  order by case m.role_code when 'super_admin' then 1 when 'org_admin' then 2 when 'lead_architect' then 3 when 'project_manager' then 4 when 'sales' then 5 else 9 end,
           m.created_at
  limit 1;

  if actor_org is null then raise exception 'workspace_membership_required'; end if;
  if actor_role not in ('super_admin','org_admin','sales','lead_architect','project_manager') then raise exception 'project_creation_not_authorised'; end if;

  insert into public.client_accounts(
    organisation_id,display_name,legal_name,email,phone,gst_registered,gstin,billing_address,billing_state,gst_verification_status,created_by
  ) values (
    actor_org,client_name,billing_legal_name,nullif(lower(btrim(input_payload#>>'{client,email}')),''),nullif(btrim(input_payload#>>'{client,phone}'),''),
    billing_gst_registered,billing_gstin,billing_address,billing_state,
    case when billing_gst_registered then 'client_declared' else 'not_applicable' end,actor
  )
  on conflict (organisation_id,gstin) where gstin is not null do nothing
  returning id into new_client_account;

  if new_client_account is null and billing_gstin is not null then
    select id into new_client_account
    from public.client_accounts
    where organisation_id = actor_org and gstin = billing_gstin;
  end if;
  if new_client_account is null then raise exception 'client_billing_account_not_created'; end if;

  new_code := 'CS-' || upper(substr(replace(gen_random_uuid()::text,'-',''),1,10));
  insert into project.projects(organisation_id,client_account_id,code,name,typology,stage,criticality,status,created_by)
  values(actor_org,new_client_account,new_code,project_name,typology_name,'intake','C1','active',actor)
  returning id into new_project;

  insert into engagement.intake_sessions(
    organisation_id,project_id,current_step,status,client_payload,site_payload,geometry_payload,
    regulation_payload,programme_payload,interiors_payload,source_channel,created_by,submitted_at
  ) values (
    actor_org,new_project,'review','submitted',
    coalesce(input_payload->'client','{}'::jsonb),coalesce(input_payload->'site','{}'::jsonb),coalesce(input_payload->'geometry','{}'::jsonb),
    coalesce(input_payload->'regulation','{}'::jsonb),coalesce(input_payload->'programme','{}'::jsonb),coalesce(input_payload->'interiors','{}'::jsonb),
    'platform',actor,now()
  ) returning id into new_intake;

  foreach module in array coalesce(scope_modules,'{}'::text[]) loop
    module := upper(btrim(module));
    if module = any(array['FEAS','ARCH','INT','STR','MEPF','BIM','BOQ','PROC','PMC','TWIN']) then
      insert into engagement.scope_selections(intake_session_id,module_code,state) values(new_intake,module,'included') on conflict do nothing;
    end if;
  end loop;

  if nullif(btrim(input_payload#>>'{site,address}'),'') is not null then
    insert into project.truth_records(project_id,kind,record_key,value,source_type,source_reference,confidence,status,criticality,created_by)
    values(new_project,'fact','site.address',jsonb_build_object('value',input_payload#>>'{site,address}'),'client_declared','intake','C','draft','C1',actor);
  end if;
  if nullif(btrim(input_payload#>>'{site,latitude}'),'') is not null or nullif(btrim(input_payload#>>'{site,longitude}'),'') is not null then
    insert into project.truth_records(project_id,kind,record_key,value,source_type,source_reference,confidence,status,criticality,created_by)
    values(new_project,'fact','site.coordinates',jsonb_build_object('latitude',input_payload#>>'{site,latitude}','longitude',input_payload#>>'{site,longitude}'),'client_declared','intake','C','draft','C2',actor);
  end if;
  if nullif(btrim(input_payload#>>'{site,plotArea}'),'') is not null then
    insert into project.truth_records(project_id,kind,record_key,value,unit,source_type,source_reference,confidence,status,criticality,created_by)
    values(new_project,'fact','site.plot_area',jsonb_build_object('value',input_payload#>>'{site,plotArea}'),coalesce(input_payload#>>'{site,plotAreaUnit}','sqm'),'client_declared','intake','C','draft','C1',actor);
  end if;
  insert into project.truth_records(project_id,kind,record_key,value,source_type,source_reference,confidence,status,criticality,created_by)
  values(new_project,'fact','site.parcels',jsonb_build_object(
    'arrangement',input_payload#>>'{site,arrangement}',
    'parcels',site_parcels,
    'combined_area',coalesce(input_payload#>'{site,combinedArea}','{}'::jsonb)
  ),'client_declared','intake','C','draft','C1',actor);

  if jsonb_typeof(parcel_geometry) = 'array' and jsonb_array_length(parcel_geometry) > 0 then
    insert into project.truth_records(project_id,kind,record_key,value,source_type,source_reference,confidence,status,criticality,created_by)
    values(new_project,'fact','plot.parcel_geometry',jsonb_build_object('parcels',parcel_geometry,'geometry_source',input_payload#>>'{geometry,source}','evidence',input_payload#>>'{geometry,evidence}'),'client_declared',coalesce(nullif(input_payload#>>'{geometry,evidence}',''),'intake'),case when geometry_has_evidence then 'C' else 'D' end,'draft','C2',actor);
  elsif legacy_geometry_has_sides then
    insert into project.truth_records(project_id,kind,record_key,value,source_type,source_reference,confidence,status,criticality,created_by)
    values(new_project,'fact','plot.side_lengths',jsonb_build_object('side1',input_payload#>>'{geometry,side1}','side2',input_payload#>>'{geometry,side2}','side3',input_payload#>>'{geometry,side3}','side4',input_payload#>>'{geometry,side4}','geometry_source',input_payload#>>'{geometry,source}','evidence',input_payload#>>'{geometry,evidence}'),'client_declared',coalesce(nullif(input_payload#>>'{geometry,evidence}',''),'intake'),case when geometry_has_evidence then 'C' else 'D' end,'draft','C2',actor);
  end if;
  if combined_boundary <> '{}'::jsonb or nullif(btrim(input_payload#>>'{geometry,adjacencyNotes}'),'') is not null then
    insert into project.truth_records(project_id,kind,record_key,value,source_type,source_reference,confidence,status,criticality,created_by)
    values(new_project,'fact','plot.assembled_geometry',jsonb_build_object('boundary',combined_boundary,'adjacency_notes',input_payload#>>'{geometry,adjacencyNotes}','geometry_source',input_payload#>>'{geometry,source}','evidence',input_payload#>>'{geometry,evidence}'),'client_declared',coalesce(nullif(input_payload#>>'{geometry,evidence}',''),'intake'),case when geometry_has_evidence then 'C' else 'D' end,'draft','C2',actor);
  end if;

  if coalesce(input_payload->'regulation','{}'::jsonb) <> '{}'::jsonb then
    insert into project.truth_records(project_id,kind,record_key,value,source_type,source_reference,confidence,status,criticality,created_by)
    values(new_project,'constraint','regulation.client_declared',coalesce(input_payload->'regulation','{}'::jsonb),'client_declared',coalesce(nullif(input_payload#>>'{regulation,authorityReference}',''),'intake'),'C','draft','C2',actor);
  end if;
  if nullif(btrim(input_payload#>>'{programme,requirements}'),'') is not null then
    insert into project.truth_records(project_id,kind,record_key,value,source_type,source_reference,confidence,status,criticality,created_by)
    values(new_project,'requirement','programme.client_brief',coalesce(input_payload->'programme','{}'::jsonb),'client_brief','intake','C','draft','C1',actor);
  end if;
  if nullif(btrim(input_payload#>>'{interiors,designLanguage}'),'') is not null then
    insert into project.truth_records(project_id,kind,record_key,value,source_type,source_reference,confidence,status,criticality,created_by)
    values(new_project,'requirement','interiors.design_dna_brief',coalesce(input_payload->'interiors','{}'::jsonb),'client_brief','intake','C','draft','C1',actor);
  end if;

  return jsonb_build_object('project_id',new_project,'project_code',new_code,'intake_session_id',new_intake,'client_account_id',new_client_account);
end;
$$;

revoke all on function public.submit_project_intake(jsonb,text[]) from public, anon;
grant execute on function public.submit_project_intake(jsonb,text[]) to authenticated;
comment on function public.submit_project_intake(jsonb,text[]) is
'Invoker-bound project intake. Creates or links the governed client billing identity, then records legal parcels, assembled geometry and sourced requirements.';

commit;
