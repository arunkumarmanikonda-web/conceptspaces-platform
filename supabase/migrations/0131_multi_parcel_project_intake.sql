begin;

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
  new_code text;
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
  if project_name is null or typology_name is null or nullif(btrim(input_payload#>>'{client,name}'),'') is null then
    raise exception 'client_project_and_typology_required';
  end if;
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

  new_code := 'CS-' || upper(substr(replace(gen_random_uuid()::text,'-',''),1,10));
  insert into project.projects(organisation_id,code,name,typology,stage,criticality,status,created_by)
  values(actor_org,new_code,project_name,typology_name,'intake','C1','active',actor)
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

  return jsonb_build_object('project_id',new_project,'project_code',new_code,'intake_session_id',new_intake);
end;
$$;

revoke all on function public.submit_project_intake(jsonb,text[]) from public, anon;
grant execute on function public.submit_project_intake(jsonb,text[]) to authenticated;
comment on function public.submit_project_intake(jsonb,text[]) is
'Invoker-bound multi-parcel project intake. Legal parcels, assembled geometry and structured client requirements enter as sourced draft Project Truth.';

commit;
