begin;

-- These tables already have restrictive RLS policies. Their workspace RPCs are
-- security-invoker functions, so authenticated users also need the underlying
-- schema/table privileges for those policies to be evaluated.
grant usage on schema ai, finance, workflow to authenticated;
grant select on aec.design_options, coordination.issue_links,
  integration.webhook_events, finance.tax_rules, finance.tax_determinations,
  workflow.workflow_versions to authenticated;
grant select on ai.agent_definitions, ai.model_profiles, ai.prompt_versions,
  ai.evaluation_cases, ai.evaluation_results, ai.learning_candidates to authenticated;

create or replace function public.generate_preliminary_layout_set(target_project_id uuid)
returns uuid
language plpgsql
security definer
set search_path='public','project','aec','extensions','auth','pg_temp'
as $$
declare
  branch_row aec.design_branches%rowtype;
  intent_row aec.design_intents%rowtype;
  assembled jsonb;
  programme jsonb;
  project_code text;
  width_ft numeric;
  depth_ft numeric;
  parcel_width_ft numeric;
  option_hash text;
  artifact_ref text;
  existing_id uuid;
  option_id uuid;
begin
  if auth.uid() is null or not project.can_access_project(target_project_id) then
    raise exception 'project_access_required';
  end if;

  select p.code into project_code from project.projects p where p.id=target_project_id;
  if project_code is null then raise exception 'project_not_found'; end if;

  select * into branch_row from aec.design_branches
  where project_id=target_project_id and code='main' and status='active'
  order by created_at desc limit 1;
  if not found then raise exception 'active_main_design_branch_required'; end if;

  select * into intent_row from aec.design_intents
  where project_id=target_project_id order by version desc limit 1;
  if not found then raise exception 'design_intent_required'; end if;

  select value into assembled from project.truth_records
  where project_id=target_project_id and record_key='plot.assembled_geometry'
  order by created_at desc limit 1;
  select value into programme from project.truth_records
  where project_id=target_project_id and record_key='programme.client_brief'
  order by created_at desc limit 1;

  width_ft:=nullif(assembled#>>'{boundary,front}','')::numeric;
  depth_ft:=nullif(assembled#>>'{boundary,left}','')::numeric;
  if width_ft is null or depth_ft is null or width_ft<=0 or depth_ft<=0 then
    raise exception 'assembled_plot_dimensions_required';
  end if;
  parcel_width_ft:=width_ft/2;
  option_hash:=encode(extensions.digest(jsonb_build_object(
    'project',target_project_id,'branch',branch_row.id,'intent',intent_row.id,
    'width_ft',width_ft,'depth_ft',depth_ft,'programme',programme,
    'generator','concept-layout-diagram@1.0.0')::text,'sha256'),'hex');
  artifact_ref:='concept-layout://'||target_project_id::text||'/'||option_hash;

  select id into existing_id from aec.design_options
  where project_id=target_project_id and geometry_artifact_ref=artifact_ref limit 1;
  if existing_id is not null then return existing_id; end if;

  insert into aec.design_options(
    project_id,branch_id,intent_id,name,status,generated_by,
    geometry_artifact_ref,metrics,assumptions,validation_summary
  ) values (
    target_project_id,branch_row.id,intent_row.id,'Concept Layout A · Shared Core','generated','hybrid',
    artifact_ref,
    jsonb_build_object(
      'generator','concept-layout-diagram@1.0.0','option_hash',option_hash,
      'plot',jsonb_build_object('width_ft',width_ft,'depth_ft',depth_ft,'parcel_width_ft',parcel_width_ft,'parcel_count',2),
      'programme',jsonb_build_object(
        'target_floors',coalesce(programme->>'targetFloors','stilt plus three'),
        'unit_count',coalesce(programme->>'keyCount','06 sellable units'),
        'bedrooms',coalesce(programme->>'bedCount','2 beds per floor per plot'),
        'parking',coalesce(programme->>'parkingRequirement','Stilt parking'),
        'amenities',coalesce(programme->>'amenities','Common lift and stair, terrace')
      ),
      'sheets',jsonb_build_array(
        jsonb_build_object('code','A-001','title','Assembled site / parcel diagram'),
        jsonb_build_object('code','A-101','title','Stilt parking and common core'),
        jsonb_build_object('code','A-102','title','Typical residential floor zoning'),
        jsonb_build_object('code','A-103','title','Terrace zoning'),
        jsonb_build_object('code','A-201','title','Concept building section')
      )
    ),
    jsonb_build_array(
      'Client-declared dimensions; survey and title evidence not yet verified.',
      'Room blocks are diagrammatic zoning, not construction dimensions.',
      'Setbacks, FAR, coverage, parking and fire/life-safety remain subject to authority verification.',
      'Structural grid, services and wall thicknesses are not designed at this stage.'
    ),
    jsonb_build_object('state','not_verified','release_allowed',false,'professional_review_required',true)
  ) returning id into option_id;
  return option_id;
end;
$$;

revoke all on function public.generate_preliminary_layout_set(uuid) from public,anon;
grant execute on function public.generate_preliminary_layout_set(uuid) to authenticated;

commit;
