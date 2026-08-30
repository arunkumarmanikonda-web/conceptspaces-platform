begin;

-- The scope/engagement facade reads this ledger through an invoker-bound RPC.
-- RLS still limits rows to proposals in the caller's organisation.
grant select on engagement.proposal_negotiation_events to authenticated;
grant usage on schema feasibility to authenticated;
grant select on feasibility.typology_packs,
                feasibility.programme_briefs,
                aec.design_intents
to authenticated;

create or replace function public.initialise_project_intake_baseline(target_project_id uuid)
returns jsonb
language plpgsql
security invoker
set search_path = public, core, project, engagement, feasibility, aec, audit, extensions, auth, pg_temp
as $$
declare
  actor uuid := auth.uid();
  p project.projects%rowtype;
  intake engagement.intake_sessions%rowtype;
  programme jsonb;
  interiors jsonb;
  regulation jsonb;
  geometry_payload jsonb;
  combined_boundary jsonb;
  typology_pack_id uuid;
  source_truth_id uuid;
  brief_id uuid;
  intent_id uuid;
  front_value numeric;
  rear_value numeric;
  left_value numeric;
  right_value numeric;
  dimension_unit text;
  geometry_parcel jsonb;
begin
  if actor is null then raise exception 'authentication_required'; end if;
  select * into p from project.projects where id = target_project_id;
  if not found or not project.can_manage_project(p.id) then raise exception 'project_manage_authority_required'; end if;

  select * into intake
  from engagement.intake_sessions
  where project_id = p.id and status = 'submitted'
  order by submitted_at desc nulls last, created_at desc
  limit 1;
  if not found then raise exception 'submitted_project_intake_required'; end if;

  programme := coalesce(intake.programme_payload, '{}'::jsonb);
  interiors := coalesce(intake.interiors_payload, '{}'::jsonb);
  regulation := coalesce(intake.regulation_payload, '{}'::jsonb);
  geometry_payload := coalesce(intake.geometry_payload, '{}'::jsonb);
  combined_boundary := coalesce(geometry_payload->'combinedBoundary', '{}'::jsonb);

  select t.id into source_truth_id
  from project.truth_records t
  where t.project_id = p.id and t.record_key = 'programme.client_brief' and t.valid_until is null
  order by t.created_at desc
  limit 1;

  if not exists(select 1 from feasibility.brief_interpretations b where b.project_id = p.id) then
    select tp.id into typology_pack_id
    from feasibility.typology_packs tp
    where tp.state = 'published' and lower(tp.typology) = lower(p.typology)
    order by tp.version desc
    limit 1;
    if typology_pack_id is not null then
      brief_id := public.interpret_project_brief(
        p.id,
        jsonb_build_object(
          'source_type','text',
          'raw_input',coalesce(nullif(btrim(programme->>'requirements'),''),programme::text),
          'typology_pack_id',typology_pack_id,
          'structured_draft',programme || jsonb_build_object(
            'interiors',interiors,
            'site_assembly',coalesce(intake.site_payload,'{}'::jsonb),
            'client_declared_regulation',regulation
          )
        )
      );
    end if;
  else
    select b.id into brief_id from feasibility.brief_interpretations b where b.project_id = p.id order by b.version desc limit 1;
  end if;

  if not exists(select 1 from project.requirements r where r.project_id = p.id and r.code::text = 'INTAKE-CORE')
     and nullif(btrim(programme->>'requirements'),'') is not null then
    perform public.create_project_requirement(p.id,jsonb_build_object(
      'code','INTAKE-CORE','statement',programme->>'requirements','category','client_brief',
      'acceptance_criteria',jsonb_build_array('Confirm against the approved project brief'),
      'criticality','C1','source_truth_record_id',source_truth_id
    ));
  end if;
  if not exists(select 1 from project.requirements r where r.project_id = p.id and r.code::text = 'INTAKE-FLOORS')
     and nullif(btrim(programme->>'floorRequirements'),'') is not null then
    perform public.create_project_requirement(p.id,jsonb_build_object(
      'code','INTAKE-FLOORS','statement',programme->>'floorRequirements','category','programme',
      'acceptance_criteria',jsonb_build_array('Confirm the floor-by-floor accommodation schedule'),
      'criticality','C1','source_truth_record_id',source_truth_id
    ));
  end if;
  if not exists(select 1 from project.requirements r where r.project_id = p.id and r.code::text = 'INTAKE-SPACES')
     and nullif(btrim(programme->>'spaceRequirements'),'') is not null then
    perform public.create_project_requirement(p.id,jsonb_build_object(
      'code','INTAKE-SPACES','statement',programme->>'spaceRequirements','category','space_programme',
      'acceptance_criteria',jsonb_build_array('Reconcile the room and unit mix with the approved programme'),
      'criticality','C1','source_truth_record_id',source_truth_id
    ));
  end if;
  if not exists(select 1 from project.requirements r where r.project_id = p.id and r.code::text = 'INTAKE-PARKING')
     and nullif(btrim(programme->>'parkingRequirement'),'') is not null then
    perform public.create_project_requirement(p.id,jsonb_build_object(
      'code','INTAKE-PARKING','statement',programme->>'parkingRequirement','category','access_parking',
      'acceptance_criteria',jsonb_build_array('Validate parking and access against applicable regulations'),
      'criticality','C2','source_truth_record_id',source_truth_id
    ));
  end if;
  if not exists(select 1 from project.requirements r where r.project_id = p.id and r.code::text = 'INTAKE-AMENITIES')
     and nullif(btrim(programme->>'amenities'),'') is not null then
    perform public.create_project_requirement(p.id,jsonb_build_object(
      'code','INTAKE-AMENITIES','statement',programme->>'amenities','category','amenities',
      'acceptance_criteria',jsonb_build_array('Confirm amenity capacity, location and service dependencies'),
      'criticality','C1','source_truth_record_id',source_truth_id
    ));
  end if;
  if not exists(select 1 from project.requirements r where r.project_id = p.id and r.code::text = 'INTAKE-SPECIAL')
     and nullif(btrim(programme->>'specialRequirements'),'') is not null then
    perform public.create_project_requirement(p.id,jsonb_build_object(
      'code','INTAKE-SPECIAL','statement',programme->>'specialRequirements','category','special_requirements',
      'acceptance_criteria',jsonb_build_array('Translate each special requirement into measurable design checks'),
      'criticality','C2','source_truth_record_id',source_truth_id
    ));
  end if;

  if nullif(btrim(regulation->>'far'),'') is not null and not exists(
    select 1 from project.truth_records t where t.project_id=p.id and t.record_key='planning.far' and t.valid_until is null
  ) then
    insert into project.truth_records(project_id,kind,record_key,value,unit,source_type,source_reference,confidence,status,criticality,created_by)
    values(p.id,'constraint','planning.far',jsonb_build_object('value',regulation->>'far'),'ratio','client_declared',coalesce(nullif(regulation->>'authorityReference',''),'intake'),'C','draft','C2',actor);
  end if;
  if nullif(btrim(regulation->>'groundCoverage'),'') is not null and not exists(
    select 1 from project.truth_records t where t.project_id=p.id and t.record_key='planning.ground_coverage' and t.valid_until is null
  ) then
    insert into project.truth_records(project_id,kind,record_key,value,unit,source_type,source_reference,confidence,status,criticality,created_by)
    values(p.id,'constraint','planning.ground_coverage',jsonb_build_object('value',regulation->>'groundCoverage'),'percent','client_declared',coalesce(nullif(regulation->>'authorityReference',''),'intake'),'C','draft','C2',actor);
  end if;
  if nullif(btrim(regulation->>'heightLimit'),'') is not null and not exists(
    select 1 from project.truth_records t where t.project_id=p.id and t.record_key='planning.height_limit' and t.valid_until is null
  ) then
    insert into project.truth_records(project_id,kind,record_key,value,source_type,source_reference,confidence,status,criticality,created_by)
    values(p.id,'constraint','planning.height_limit',jsonb_build_object('value',regulation->>'heightLimit'),'client_declared',coalesce(nullif(regulation->>'authorityReference',''),'intake'),'C','draft','C2',actor);
  end if;
  if nullif(btrim(regulation->>'frontSetback'),'') is not null and not exists(
    select 1 from project.truth_records t where t.project_id=p.id and t.record_key='planning.front_setback' and t.valid_until is null
  ) then
    insert into project.truth_records(project_id,kind,record_key,value,source_type,source_reference,confidence,status,criticality,created_by)
    values(p.id,'constraint','planning.front_setback',jsonb_build_object('value',regulation->>'frontSetback'),'client_declared',coalesce(nullif(regulation->>'authorityReference',''),'intake'),'C','draft','C2',actor);
  end if;
  if nullif(btrim(regulation->>'rearSetback'),'') is not null and not exists(
    select 1 from project.truth_records t where t.project_id=p.id and t.record_key='planning.rear_setback' and t.valid_until is null
  ) then
    insert into project.truth_records(project_id,kind,record_key,value,source_type,source_reference,confidence,status,criticality,created_by)
    values(p.id,'constraint','planning.rear_setback',jsonb_build_object('value',regulation->>'rearSetback'),'client_declared',coalesce(nullif(regulation->>'authorityReference',''),'intake'),'C','draft','C2',actor);
  end if;

  if not exists(select 1 from aec.design_intents d where d.project_id = p.id) then
    intent_id := public.create_design_intent(p.id,jsonb_build_object(
      'typology',p.typology,
      'optimisation_mode','balanced',
      'seed','intake-baseline-v1',
      'metric_set_version','feasibility-envelope-metrics@1.0.0',
      'programme',programme,
      'mandatory_requirements','[]'::jsonb,
      'preferences',jsonb_build_object('programme',programme,'interiors',interiors,'site_assembly',coalesce(intake.site_payload,'{}'::jsonb)),
      'exclusions',case when nullif(btrim(programme->>'exclusions'),'') is null then '[]'::jsonb else jsonb_build_array(programme->>'exclusions') end
    ));
  else
    select d.id into intent_id from aec.design_intents d where d.project_id = p.id order by d.version desc limit 1;
  end if;

  if not exists(select 1 from aec.site_geometries g where g.project_id = p.id) then
    begin
      front_value := nullif(regexp_replace(coalesce(combined_boundary->>'front',''),'[^0-9.+-]','','g'),'')::numeric;
      rear_value := nullif(regexp_replace(coalesce(combined_boundary->>'rear',''),'[^0-9.+-]','','g'),'')::numeric;
      left_value := nullif(regexp_replace(coalesce(combined_boundary->>'left',''),'[^0-9.+-]','','g'),'')::numeric;
      right_value := nullif(regexp_replace(coalesce(combined_boundary->>'right',''),'[^0-9.+-]','','g'),'')::numeric;
    exception when others then
      front_value := null; rear_value := null; left_value := null; right_value := null;
    end;
    dimension_unit := lower(coalesce(nullif(combined_boundary->>'dimensionUnit',''),'m'));
    if dimension_unit not in ('m','ft') then dimension_unit := 'm'; end if;
    if front_value > 0 and rear_value > 0 and left_value > 0 and right_value > 0
       and abs(front_value-rear_value) <= greatest(front_value,rear_value)*0.01
       and abs(left_value-right_value) <= greatest(left_value,right_value)*0.01 then
      geometry_parcel := jsonb_build_object(
        'vertices',jsonb_build_array(
          jsonb_build_object('x',0,'y',0),
          jsonb_build_object('x',front_value,'y',0),
          jsonb_build_object('x',front_value,'y',right_value),
          jsonb_build_object('x',0,'y',right_value)
        ),
        'unit',dimension_unit,
        'coordinate_system','INTAKE_LOCAL_RECTANGLE',
        'source_type','manual',
        'source_reference',coalesce(nullif(geometry_payload->>'evidence',''),'client-declared assembled boundary from intake')
      );
    end if;
  end if;

  return jsonb_build_object(
    'project_id',p.id,
    'brief_id',brief_id,
    'design_intent_id',intent_id,
    'geometry_parcel',geometry_parcel,
    'counts',jsonb_build_object(
      'truth_records',(select count(*) from project.truth_records t where t.project_id=p.id and t.valid_until is null),
      'requirements',(select count(*) from project.requirements r where r.project_id=p.id),
      'brief_interpretations',(select count(*) from feasibility.brief_interpretations b where b.project_id=p.id),
      'design_intents',(select count(*) from aec.design_intents d where d.project_id=p.id),
      'site_geometries',(select count(*) from aec.site_geometries g where g.project_id=p.id)
    )
  );
end;
$$;

revoke all on function public.initialise_project_intake_baseline(uuid) from public, anon;
grant execute on function public.initialise_project_intake_baseline(uuid) to authenticated;
comment on function public.initialise_project_intake_baseline(uuid) is
'Idempotently converts a submitted project intake into draft brief, requirement, planning, design-intent and geometry inputs. It never verifies client declarations or approves professional outputs.';

commit;
