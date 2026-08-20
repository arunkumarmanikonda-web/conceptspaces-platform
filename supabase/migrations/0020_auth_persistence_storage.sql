begin;

-- Authentication creates identity only. Authority is assigned independently.
create or replace function core.handle_auth_user_authority()
returns trigger
language plpgsql
security definer
set search_path = core, public, auth, extensions
as $$
declare
  bootstrap_org uuid;
begin
  insert into core.profiles(user_id, display_name)
  values (new.id, coalesce(new.raw_user_meta_data->>'full_name', split_part(coalesce(new.email,''),'@',1)))
  on conflict (user_id) do update
    set display_name = coalesce(core.profiles.display_name, excluded.display_name),
        updated_at = now();

  if new.email_confirmed_at is not null then
    perform pg_advisory_xact_lock(hashtext('concept_spaces_bootstrap_administrator'));

    if not exists (select 1 from core.memberships) then
      insert into core.organisations(name, code, settings)
      values ('Concept Spaces', 'CS-HQ', jsonb_build_object('bootstrap','first_confirmed_identity'))
      on conflict (code) do update set updated_at = now()
      returning id into bootstrap_org;

      if bootstrap_org is null then
        select id into bootstrap_org from core.organisations where code = 'CS-HQ' limit 1;
      end if;

      insert into core.memberships(organisation_id,user_id,role_code,status)
      values (bootstrap_org,new.id,'super_admin','active')
      on conflict do nothing;
    end if;
  end if;

  return new;
end;
$$;

drop trigger if exists concept_spaces_auth_authority on auth.users;
create trigger concept_spaces_auth_authority
after insert or update of email_confirmed_at on auth.users
for each row execute function core.handle_auth_user_authority();

comment on function core.handle_auth_user_authority() is
'Creates a profile for every identity. Only the first confirmed identity may bootstrap the first super_admin; subsequent identities remain fail-closed until explicit membership assignment.';

-- Public RPC facade: internal schemas remain isolated from PostgREST exposure.
create or replace function public.get_workspace_context()
returns jsonb
language sql
stable
security definer
set search_path = core, public
as $$
  select jsonb_build_object(
    'user_id', auth.uid(),
    'memberships', coalesce((
      select jsonb_agg(jsonb_build_object(
        'organisation_id', m.organisation_id,
        'organisation_name', o.name,
        'role_code', m.role_code,
        'status', m.status
      ) order by case m.role_code when 'super_admin' then 1 when 'org_admin' then 2 else 9 end, m.created_at)
      from core.memberships m
      join core.organisations o on o.id = m.organisation_id
      where m.user_id = auth.uid() and m.status = 'active'
    ), '[]'::jsonb)
  );
$$;

revoke all on function public.get_workspace_context() from public;
grant execute on function public.get_workspace_context() to authenticated;

create or replace function public.list_accessible_projects()
returns table(
  id uuid,
  code text,
  name text,
  typology text,
  stage text,
  criticality text,
  status text,
  lead_architect_user_id uuid,
  created_at timestamptz
)
language sql
stable
security definer
set search_path = core, project, public
as $$
  select p.id, p.code::text, p.name, p.typology, p.stage, p.criticality, p.status,
         p.lead_architect_user_id, p.created_at
  from project.projects p
  where project.can_access_project(p.id)
  order by p.created_at desc;
$$;

revoke all on function public.list_accessible_projects() from public;
grant execute on function public.list_accessible_projects() to authenticated;

create or replace function public.submit_project_intake(input_payload jsonb, scope_modules text[] default '{}'::text[])
returns jsonb
language plpgsql
security definer
set search_path = core, project, engagement, public, extensions
as $$
declare
  actor uuid := auth.uid();
  actor_org uuid;
  actor_role text;
  new_project uuid;
  new_intake uuid;
  new_code text;
  project_name text := nullif(btrim(input_payload#>>'{project,name}'),'');
  typology_name text := nullif(btrim(input_payload#>>'{project,typology}'),'');
  geometry_has_evidence boolean := coalesce(nullif(btrim(input_payload#>>'{geometry,evidence}'),'') is not null,false);
  geometry_has_sides boolean :=
    nullif(btrim(input_payload#>>'{geometry,side1}'),'') is not null and
    nullif(btrim(input_payload#>>'{geometry,side2}'),'') is not null and
    nullif(btrim(input_payload#>>'{geometry,side3}'),'') is not null and
    nullif(btrim(input_payload#>>'{geometry,side4}'),'') is not null;
  module text;
begin
  if actor is null then raise exception 'authentication_required'; end if;
  if project_name is null or typology_name is null or nullif(btrim(input_payload#>>'{client,name}'),'') is null then
    raise exception 'client_project_and_typology_required';
  end if;

  select m.organisation_id, m.role_code
    into actor_org, actor_role
  from core.memberships m
  where m.user_id = actor and m.status = 'active'
  order by case m.role_code when 'super_admin' then 1 when 'org_admin' then 2 when 'lead_architect' then 3 when 'project_manager' then 4 when 'sales' then 5 else 9 end,
           m.created_at
  limit 1;

  if actor_org is null then raise exception 'workspace_membership_required'; end if;
  if actor_role not in ('super_admin','org_admin','sales','lead_architect','project_manager') then
    raise exception 'project_creation_not_authorised';
  end if;

  new_code := 'CS-' || upper(substr(replace(gen_random_uuid()::text,'-',''),1,10));

  insert into project.projects(organisation_id,code,name,typology,stage,criticality,status,created_by)
  values(actor_org,new_code,project_name,typology_name,'intake','C1','active',actor)
  returning id into new_project;

  insert into engagement.intake_sessions(
    organisation_id,project_id,current_step,status,client_payload,site_payload,geometry_payload,
    regulation_payload,programme_payload,interiors_payload,source_channel,created_by,submitted_at
  ) values (
    actor_org,new_project,'review','submitted',
    coalesce(input_payload->'client','{}'::jsonb),
    coalesce(input_payload->'site','{}'::jsonb),
    coalesce(input_payload->'geometry','{}'::jsonb),
    coalesce(input_payload->'regulation','{}'::jsonb),
    coalesce(input_payload->'programme','{}'::jsonb),
    coalesce(input_payload->'interiors','{}'::jsonb),
    'platform',actor,now()
  ) returning id into new_intake;

  foreach module in array coalesce(scope_modules,'{}'::text[]) loop
    module := upper(btrim(module));
    if module = any(array['FEAS','ARCH','INT','STR','MEPF','BIM','BOQ','PROC','PMC','TWIN']) then
      insert into engagement.scope_selections(intake_session_id,module_code,state)
      values(new_intake,module,'included')
      on conflict do nothing;
    end if;
  end loop;

  -- Declared information enters Project Truth as draft and never self-promotes to verified.
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

  if geometry_has_sides then
    insert into project.truth_records(project_id,kind,record_key,value,source_type,source_reference,confidence,status,criticality,created_by)
    values(new_project,'fact','plot.side_lengths',jsonb_build_object(
      'side1',input_payload#>>'{geometry,side1}','side2',input_payload#>>'{geometry,side2}',
      'side3',input_payload#>>'{geometry,side3}','side4',input_payload#>>'{geometry,side4}',
      'geometry_source',input_payload#>>'{geometry,source}','evidence',input_payload#>>'{geometry,evidence}'
    ),'client_declared',coalesce(nullif(input_payload#>>'{geometry,evidence}',''),'intake'),case when geometry_has_evidence then 'C' else 'D' end,'draft','C2',actor);
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

  return jsonb_build_object('project_id',new_project,'project_code',new_code,'intake_session_id',new_intake);
end;
$$;

revoke all on function public.submit_project_intake(jsonb,text[]) from public;
grant execute on function public.submit_project_intake(jsonb,text[]) to authenticated;

comment on function public.submit_project_intake(jsonb,text[]) is
'Governed server mutation for project intake. Declared values are stored as draft Project Truth with explicit source/confidence and cannot self-verify.';

-- Private Common Data Environment storage. Object path starts with governed project UUID.
insert into storage.buckets(id,name,public,file_size_limit)
values('project-cde','project-cde',false,524288000)
on conflict (id) do update set public=false, file_size_limit=excluded.file_size_limit;

create or replace function public.cde_path_project_id(object_name text)
returns uuid
language sql
immutable
set search_path = public
as $$
  select case
    when split_part(object_name,'/',1) ~* '^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$'
      then split_part(object_name,'/',1)::uuid
    else null::uuid
  end;
$$;

revoke all on function public.cde_path_project_id(text) from public;
grant execute on function public.cde_path_project_id(text) to authenticated;

drop policy if exists concept_spaces_cde_read on storage.objects;
create policy concept_spaces_cde_read on storage.objects
for select to authenticated
using (bucket_id='project-cde' and project.can_access_project(public.cde_path_project_id(name)));

drop policy if exists concept_spaces_cde_insert on storage.objects;
create policy concept_spaces_cde_insert on storage.objects
for insert to authenticated
with check (bucket_id='project-cde' and project.can_manage_project(public.cde_path_project_id(name)));

drop policy if exists concept_spaces_cde_update on storage.objects;
create policy concept_spaces_cde_update on storage.objects
for update to authenticated
using (bucket_id='project-cde' and project.can_manage_project(public.cde_path_project_id(name)))
with check (bucket_id='project-cde' and project.can_manage_project(public.cde_path_project_id(name)));

drop policy if exists concept_spaces_cde_delete on storage.objects;
create policy concept_spaces_cde_delete on storage.objects
for delete to authenticated
using (bucket_id='project-cde' and project.can_manage_project(public.cde_path_project_id(name)));

comment on function public.cde_path_project_id(text) is
'Extracts a project UUID from the first segment of the private CDE object path. Malformed paths resolve to NULL and fail closed.';

commit;
