begin;

-- Exposed RPCs run with the caller's database role. Their access is therefore
-- bounded by explicit grants plus Row Level Security rather than definer privilege.
grant usage on schema core, project, engagement to authenticated;
grant select on core.memberships to authenticated;
grant select on project.projects to authenticated;
grant select, insert on engagement.intake_sessions to authenticated;
grant insert on engagement.scope_selections to authenticated;
grant insert on project.projects, project.truth_records to authenticated;

create or replace function public.get_workspace_context()
returns jsonb
language sql
stable
security invoker
set search_path = core, public
as $$
  select jsonb_build_object(
    'user_id', auth.uid(),
    'memberships', coalesce((
      select jsonb_agg(jsonb_build_object(
        'organisation_id', m.organisation_id,
        'role_code', m.role_code,
        'status', m.status
      ) order by case m.role_code when 'super_admin' then 1 when 'org_admin' then 2 else 9 end, m.created_at)
      from core.memberships m
      where m.user_id = auth.uid() and m.status = 'active'
    ), '[]'::jsonb)
  );
$$;

revoke all on function public.get_workspace_context() from public, anon;
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
security invoker
set search_path = project, public
as $$
  select p.id, p.code::text, p.name, p.typology, p.stage, p.criticality, p.status,
         p.lead_architect_user_id, p.created_at
  from project.projects p
  order by p.created_at desc;
$$;

revoke all on function public.list_accessible_projects() from public, anon;
grant execute on function public.list_accessible_projects() to authenticated;

-- Creation policies are deliberately narrower than read policies. Browser code
-- cannot bypass them even though this RPC offers a convenient transactional API.
drop policy if exists intake_create on engagement.intake_sessions;
create policy intake_create on engagement.intake_sessions
for insert to authenticated
with check (
  created_by = (select auth.uid())
  and organisation_id is not null
  and core.has_org_role(organisation_id, array['super_admin','org_admin','sales','lead_architect','project_manager'])
  and (project_id is null or project.can_access_project(project_id))
);

drop policy if exists scope_selection_create on engagement.scope_selections;
create policy scope_selection_create on engagement.scope_selections
for insert to authenticated
with check (
  exists (
    select 1 from engagement.intake_sessions s
    where s.id = intake_session_id
      and s.created_by = (select auth.uid())
      and s.project_id is not null
      and project.can_access_project(s.project_id)
  )
);

drop policy if exists truth_record_create on project.truth_records;
create policy truth_record_create on project.truth_records
for insert to authenticated
with check (
  created_by = (select auth.uid())
  and project.can_access_project(project_id)
  and status = 'draft'
  and verified_by is null
  and verified_at is null
);

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

revoke all on function public.submit_project_intake(jsonb,text[]) from public, anon;
grant execute on function public.submit_project_intake(jsonb,text[]) to authenticated;

comment on function public.submit_project_intake(jsonb,text[]) is
'Invoker-bound governed project intake. Database grants and RLS remain authoritative; client declarations enter only as draft, sourced Project Truth.';

commit;
