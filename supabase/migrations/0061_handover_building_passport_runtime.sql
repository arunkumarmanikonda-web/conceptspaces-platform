begin;

-- F22 Handover, Building Passport and Digital Twin execution runtime.
-- All authoritative mutations remain SECURITY INVOKER and are protected by RLS transaction phases.

-- Material passports are part of the governed handover record and need a controlled mutation path.
drop policy if exists material_passports_handover_write on public.material_passports;
create policy material_passports_handover_write
on public.material_passports
for all to authenticated
using (project.can_manage_project(project_id))
with check (
  project.can_manage_project(project_id)
  and current_setting('conceptspaces.handover_phase', true) = 'material'
);
grant insert, update on public.material_passports to authenticated;

-- Building Passport rows become immutable once issued. Operational history is appended elsewhere.
create or replace function public.guard_issued_building_passport_immutable()
returns trigger
language plpgsql
set search_path = public, pg_temp
as $$
begin
  if old.status = 'issued' then
    raise exception 'issued_building_passport_immutable';
  end if;
  return new;
end;
$$;
revoke all on function public.guard_issued_building_passport_immutable() from public, anon, authenticated;

drop trigger if exists building_passport_immutable_after_issue on public.building_passports;
create trigger building_passport_immutable_after_issue
before update on public.building_passports
for each row execute function public.guard_issued_building_passport_immutable();

-- Canonical project handover snapshot used both for compile and issue freshness checks.
create or replace function public.handover_snapshot(target_project_id uuid)
returns jsonb
language sql
stable
security invoker
set search_path = public, cde, project, procurement, extensions, pg_temp
as $$
  select jsonb_build_object(
    'project_id', target_project_id,
    'handover_items', coalesce((
      select jsonb_agg(
        jsonb_build_object(
          'id', h.id,
          'item_code', h.item_code,
          'category', h.category,
          'title', h.title,
          'mandatory', h.mandatory,
          'status', h.status,
          'evidence_refs', h.evidence_refs,
          'accepted_by', h.accepted_by,
          'accepted_at', h.accepted_at,
          'updated_at', h.updated_at
        ) order by h.item_code, h.id
      )
      from public.handover_items h
      where h.project_id = target_project_id
    ), '[]'::jsonb),
    'approved_exceptions', coalesce((
      select jsonb_agg(
        jsonb_build_object(
          'id', e.id,
          'handover_item_id', e.handover_item_id,
          'reason', e.reason,
          'evidence_refs', e.evidence_refs,
          'decided_by', e.decided_by,
          'decided_at', e.decided_at
        ) order by e.handover_item_id, e.id
      )
      from public.handover_exceptions e
      where e.project_id = target_project_id and e.status = 'approved'
    ), '[]'::jsonb),
    'final_documents', coalesce((
      select jsonb_agg(
        jsonb_build_object(
          'id', d.id,
          'document_number', d.document_number::text,
          'title', d.title,
          'revision', d.revision,
          'status', d.status,
          'cde_state', d.cde_state,
          'current_version_id', d.current_version_id,
          'checksum', v.checksum
        ) order by d.document_number, d.id
      )
      from cde.documents d
      left join cde.file_versions v on v.id = d.current_version_id
      where d.project_id = target_project_id
        and d.status in ('approved','issued')
        and d.cde_state in ('shared','published','archived')
    ), '[]'::jsonb),
    'final_models', coalesce((
      select jsonb_agg(
        jsonb_build_object(
          'id', m.id,
          'model_name', m.model_name,
          'discipline', m.discipline,
          'revision', m.revision,
          'status', m.status,
          'format', m.format,
          'schema_version', m.schema_version,
          'checksum', m.checksum,
          'coordinate_system', m.coordinate_system
        ) order by m.discipline, m.model_name, m.id
      )
      from cde.models m
      where m.project_id = target_project_id
        and m.status in ('approved','issued')
    ), '[]'::jsonb),
    'assets', coalesce((
      select jsonb_agg(
        jsonb_build_object(
          'id', a.id,
          'asset_code', a.asset_code,
          'asset_type', a.asset_type,
          'system_code', a.system_code,
          'install_location', a.install_location,
          'model_object_ref', a.model_object_ref,
          'manufacturer', a.manufacturer,
          'model', a.model,
          'serial_number', a.serial_number,
          'warranty_from', a.warranty_from,
          'warranty_until', a.warranty_until,
          'maintenance_plan', a.maintenance_plan,
          'document_refs', a.document_refs,
          'commissioning_refs', a.commissioning_refs,
          'operational_status', a.operational_status,
          'verified_by', a.verified_by,
          'verified_at', a.verified_at
        ) order by a.asset_code, a.id
      )
      from public.asset_passports a
      where a.project_id = target_project_id
    ), '[]'::jsonb),
    'materials', coalesce((
      select jsonb_agg(
        jsonb_build_object(
          'id', m.id,
          'material_code', m.material_code,
          'name', m.name,
          'manufacturer', m.manufacturer,
          'product_code', m.product_code,
          'batch_ref', m.batch_ref,
          'install_locations', m.install_locations,
          'quantity', m.quantity,
          'unit', m.unit,
          'embodied_carbon', m.embodied_carbon,
          'recycled_content_percent', m.recycled_content_percent,
          'warranty_until', m.warranty_until,
          'maintenance_requirements', m.maintenance_requirements,
          'end_of_life_route', m.end_of_life_route,
          'evidence_refs', m.evidence_refs
        ) order by m.material_code, m.id
      )
      from public.material_passports m
      where m.project_id = target_project_id
    ), '[]'::jsonb),
    'commissioning', coalesce((
      select jsonb_agg(
        jsonb_build_object(
          'id', c.id,
          'system_code', c.system_code,
          'asset_code', c.asset_code,
          'test_type', c.test_type,
          'procedure_ref', c.procedure_ref,
          'test_date', c.test_date,
          'result', c.result,
          'readings', c.readings,
          'witness_user_ids', c.witness_user_ids,
          'evidence_refs', c.evidence_refs,
          'defects', c.defects,
          'accepted_by', c.accepted_by,
          'accepted_at', c.accepted_at
        ) order by c.test_date, c.system_code, c.id
      )
      from public.commissioning_records c
      where c.project_id = target_project_id
    ), '[]'::jsonb),
    'vendors', coalesce((
      select jsonb_agg(distinct jsonb_build_object(
        'id', v.id,
        'legal_name', v.legal_name,
        'kyc_status', v.kyc_status,
        'status', v.status
      ))
      from procurement.vendors v
      join procurement.purchase_orders po on po.vendor_id = v.id
      where po.project_id = target_project_id
    ), '[]'::jsonb)
  );
$$;
revoke all on function public.handover_snapshot(uuid) from public, anon;
grant execute on function public.handover_snapshot(uuid) to authenticated;

create or replace function public.ensure_standard_handover_checklist(target_project_id uuid)
returns integer
language plpgsql
security invoker
set search_path = public, project, audit, auth, pg_temp
as $$
declare
  org_id uuid;
  inserted_count integer := 0;
begin
  if auth.uid() is null or not project.can_manage_project(target_project_id) then
    raise exception 'project_manage_authority_required';
  end if;

  perform set_config('conceptspaces.handover_phase','item',true);
  insert into public.handover_items(project_id,item_code,category,title,mandatory,status)
  values
    (target_project_id,'ASBUILT-MODEL','as_built','Verified as-built model set',true,'open'),
    (target_project_id,'FINAL-DRAWINGS','document','Final approved / issued drawing set',true,'open'),
    (target_project_id,'ASSET-REGISTER','asset_data','Verified asset register',true,'open'),
    (target_project_id,'COMMISSIONING','commissioning','Accepted commissioning records',true,'open'),
    (target_project_id,'OM-MANUALS','document','Operation and maintenance manuals',true,'open'),
    (target_project_id,'WARRANTIES','warranty','Asset and system warranties',true,'open'),
    (target_project_id,'CERTIFICATES','certificate','Completion and statutory certificates',true,'open'),
    (target_project_id,'TRAINING','training','Owner / FM training evidence',true,'open'),
    (target_project_id,'MATERIAL-PASSPORTS','material_passport','Installed material passport register',true,'open')
  on conflict(project_id,item_code) do nothing;
  get diagnostics inserted_count = row_count;

  if inserted_count > 0 then
    select organisation_id into org_id from project.projects where id=target_project_id;
    perform audit.append_event(org_id,target_project_id,'handover.checklist.seeded','handover',target_project_id,null,jsonb_build_object('items_inserted',inserted_count),null,gen_random_uuid());
  end if;

  return inserted_count;
end;
$$;
revoke all on function public.ensure_standard_handover_checklist(uuid) from public, anon;
grant execute on function public.ensure_standard_handover_checklist(uuid) to authenticated;

create or replace function public.create_handover_item(target_project_id uuid,input_payload jsonb)
returns uuid
language plpgsql
security invoker
set search_path = public, project, audit, auth, pg_temp
as $$
declare
  item public.handover_items%rowtype;
  org_id uuid;
  category_value text := lower(btrim(input_payload->>'category'));
begin
  if auth.uid() is null or not project.can_manage_project(target_project_id) then raise exception 'project_manage_authority_required'; end if;
  if nullif(btrim(input_payload->>'item_code'),'') is null or nullif(btrim(input_payload->>'title'),'') is null then raise exception 'handover_item_identity_required'; end if;
  if category_value not in ('as_built','document','commissioning','warranty','training','certificate','asset_data','material_passport','other') then raise exception 'handover_item_category_invalid'; end if;

  perform set_config('conceptspaces.handover_phase','item',true);
  insert into public.handover_items(project_id,item_code,category,title,mandatory,evidence_refs,status)
  values(target_project_id,upper(btrim(input_payload->>'item_code')),category_value,btrim(input_payload->>'title'),coalesce((input_payload->>'mandatory')::boolean,true),coalesce(input_payload->'evidence_refs','[]'::jsonb),'open')
  returning * into item;

  select organisation_id into org_id from project.projects where id=target_project_id;
  perform audit.append_event(org_id,target_project_id,'handover.item.created','handover_item',item.id,null,to_jsonb(item),null,gen_random_uuid());
  return item.id;
end;
$$;
revoke all on function public.create_handover_item(uuid,jsonb) from public, anon;
grant execute on function public.create_handover_item(uuid,jsonb) to authenticated;

create or replace function public.submit_handover_item(target_item_id uuid,target_evidence_refs jsonb)
returns text
language plpgsql
security invoker
set search_path = public, project, audit, auth, pg_temp
as $$
declare
  item public.handover_items%rowtype;
  before_state jsonb;
  org_id uuid;
begin
  select * into item from public.handover_items where id=target_item_id for update;
  if not found or auth.uid() is null or not project.can_access_project(item.project_id) then raise exception 'handover_item_access_required'; end if;
  if item.status not in ('open','submitted') then raise exception 'handover_item_not_submittable'; end if;
  if jsonb_typeof(coalesce(target_evidence_refs,'[]'::jsonb)) <> 'array' or jsonb_array_length(coalesce(target_evidence_refs,'[]'::jsonb)) = 0 then raise exception 'handover_evidence_required'; end if;

  before_state := to_jsonb(item);
  perform set_config('conceptspaces.handover_phase','item',true);
  update public.handover_items
  set evidence_refs=target_evidence_refs,status='submitted',submitted_by=auth.uid(),accepted_by=null,accepted_at=null,updated_at=now()
  where id=item.id returning * into item;

  select organisation_id into org_id from project.projects where id=item.project_id;
  perform audit.append_event(org_id,item.project_id,'handover.item.submitted','handover_item',item.id,before_state,to_jsonb(item),null,gen_random_uuid());
  return item.status;
end;
$$;
revoke all on function public.submit_handover_item(uuid,jsonb) from public, anon;
grant execute on function public.submit_handover_item(uuid,jsonb) to authenticated;

create or replace function public.decide_handover_item(target_item_id uuid,target_decision text,target_reason text default null)
returns text
language plpgsql
security invoker
set search_path = public, project, audit, auth, pg_temp
as $$
declare
  item public.handover_items%rowtype;
  before_state jsonb;
  decision_value text := lower(btrim(target_decision));
  org_id uuid;
begin
  select * into item from public.handover_items where id=target_item_id for update;
  if not found or auth.uid() is null or not project.can_manage_project(item.project_id) then raise exception 'handover_accept_authority_required'; end if;
  if decision_value not in ('accepted','open','not_applicable') then raise exception 'handover_decision_invalid'; end if;
  if decision_value='accepted' and (item.status<>'submitted' or jsonb_array_length(item.evidence_refs)=0) then raise exception 'submitted_handover_evidence_required'; end if;
  if decision_value='not_applicable' and item.mandatory and nullif(btrim(target_reason),'') is null then raise exception 'mandatory_item_na_reason_required'; end if;

  before_state := to_jsonb(item);
  perform set_config('conceptspaces.handover_phase','item',true);
  update public.handover_items
  set status=decision_value,
      accepted_by=case when decision_value in ('accepted','not_applicable') then auth.uid() else null end,
      accepted_at=case when decision_value in ('accepted','not_applicable') then now() else null end,
      updated_at=now()
  where id=item.id returning * into item;

  select organisation_id into org_id from project.projects where id=item.project_id;
  perform audit.append_event(org_id,item.project_id,'handover.item.'||decision_value,'handover_item',item.id,before_state,to_jsonb(item),target_reason,gen_random_uuid());
  return item.status;
end;
$$;
revoke all on function public.decide_handover_item(uuid,text,text) from public, anon;
grant execute on function public.decide_handover_item(uuid,text,text) to authenticated;

create or replace function public.request_handover_exception(target_item_id uuid,target_reason text,target_evidence_refs jsonb)
returns uuid
language plpgsql
security invoker
set search_path = public, project, audit, auth, pg_temp
as $$
declare
  item public.handover_items%rowtype;
  ex public.handover_exceptions%rowtype;
  org_id uuid;
begin
  select * into item from public.handover_items where id=target_item_id;
  if not found or auth.uid() is null or not project.can_access_project(item.project_id) then raise exception 'handover_item_access_required'; end if;
  if nullif(btrim(target_reason),'') is null or jsonb_typeof(coalesce(target_evidence_refs,'[]'::jsonb))<>'array' or jsonb_array_length(coalesce(target_evidence_refs,'[]'::jsonb))=0 then raise exception 'handover_exception_reason_evidence_required'; end if;

  perform set_config('conceptspaces.handover_phase','exception',true);
  insert into public.handover_exceptions(project_id,handover_item_id,reason,evidence_refs,status,requested_by)
  values(item.project_id,item.id,btrim(target_reason),target_evidence_refs,'requested',auth.uid()) returning * into ex;

  select organisation_id into org_id from project.projects where id=item.project_id;
  perform audit.append_event(org_id,item.project_id,'handover.exception.requested','handover_exception',ex.id,null,to_jsonb(ex),target_reason,gen_random_uuid());
  return ex.id;
end;
$$;
revoke all on function public.request_handover_exception(uuid,text,jsonb) from public, anon;
grant execute on function public.request_handover_exception(uuid,text,jsonb) to authenticated;

create or replace function public.decide_handover_exception(target_exception_id uuid,target_decision text,target_reason text default null)
returns text
language plpgsql
security invoker
set search_path = public, project, audit, auth, pg_temp
as $$
declare
  ex public.handover_exceptions%rowtype;
  before_state jsonb;
  decision_value text := lower(btrim(target_decision));
  org_id uuid;
begin
  select * into ex from public.handover_exceptions where id=target_exception_id for update;
  if not found or auth.uid() is null or not project.can_manage_project(ex.project_id) then raise exception 'handover_exception_authority_required'; end if;
  if ex.status<>'requested' or decision_value not in ('approved','rejected','withdrawn') then raise exception 'handover_exception_decision_invalid'; end if;
  if ex.requested_by=auth.uid() and decision_value='approved' then raise exception 'handover_exception_independent_approval_required'; end if;

  before_state:=to_jsonb(ex);
  perform set_config('conceptspaces.handover_phase','exception_decide',true);
  update public.handover_exceptions
  set status=decision_value,decided_by=auth.uid(),decided_at=now()
  where id=ex.id returning * into ex;

  select organisation_id into org_id from project.projects where id=ex.project_id;
  perform audit.append_event(org_id,ex.project_id,'handover.exception.'||decision_value,'handover_exception',ex.id,before_state,to_jsonb(ex),target_reason,gen_random_uuid());
  return ex.status;
end;
$$;
revoke all on function public.decide_handover_exception(uuid,text,text) from public, anon;
grant execute on function public.decide_handover_exception(uuid,text,text) to authenticated;

create or replace function public.upsert_asset_passport(target_project_id uuid,input_payload jsonb)
returns uuid
language plpgsql
security invoker
set search_path = public, project, audit, auth, pg_temp
as $$
declare
  asset public.asset_passports%rowtype;
  before_state jsonb;
  org_id uuid;
  asset_code_value text := upper(btrim(input_payload->>'asset_code'));
  asset_id_value uuid := nullif(input_payload->>'id','')::uuid;
  warranty_from_value date := nullif(input_payload->>'warranty_from','')::date;
  warranty_until_value date := nullif(input_payload->>'warranty_until','')::date;
begin
  if auth.uid() is null or not project.can_manage_project(target_project_id) then raise exception 'project_manage_authority_required'; end if;
  if nullif(asset_code_value,'') is null or nullif(btrim(input_payload->>'asset_type'),'') is null then raise exception 'asset_identity_required'; end if;
  if nullif(btrim(input_payload->>'system_code'),'') is null or nullif(btrim(input_payload->>'install_location'),'') is null then raise exception 'asset_system_location_required'; end if;
  if warranty_until_value is not null and warranty_from_value is not null and warranty_until_value < warranty_from_value then raise exception 'warranty_date_invalid'; end if;
  if jsonb_typeof(coalesce(input_payload->'document_refs','[]'::jsonb))<>'array' then raise exception 'asset_document_refs_invalid'; end if;

  perform set_config('conceptspaces.handover_phase','asset',true);
  if asset_id_value is null then
    insert into public.asset_passports(project_id,asset_code,asset_type,manufacturer,model,serial_number,install_location,model_object_ref,warranty_from,warranty_until,maintenance_plan,document_refs,commissioning_refs,operational_status,system_code)
    values(target_project_id,asset_code_value,btrim(input_payload->>'asset_type'),nullif(btrim(input_payload->>'manufacturer'),''),nullif(btrim(input_payload->>'model'),''),nullif(btrim(input_payload->>'serial_number'),''),btrim(input_payload->>'install_location'),nullif(btrim(input_payload->>'model_object_ref'),''),warranty_from_value,warranty_until_value,coalesce(input_payload->'maintenance_plan','{}'::jsonb),coalesce(input_payload->'document_refs','[]'::jsonb),coalesce(input_payload->'commissioning_refs','[]'::jsonb),coalesce(nullif(lower(btrim(input_payload->>'operational_status')),''),'installed'),upper(btrim(input_payload->>'system_code')))
    returning * into asset;
  else
    select to_jsonb(a) into before_state from public.asset_passports a where a.id=asset_id_value and a.project_id=target_project_id;
    if before_state is null then raise exception 'asset_not_found'; end if;
    update public.asset_passports
    set asset_code=asset_code_value,
        asset_type=btrim(input_payload->>'asset_type'),
        manufacturer=nullif(btrim(input_payload->>'manufacturer'),''),
        model=nullif(btrim(input_payload->>'model'),''),
        serial_number=nullif(btrim(input_payload->>'serial_number'),''),
        install_location=btrim(input_payload->>'install_location'),
        model_object_ref=nullif(btrim(input_payload->>'model_object_ref'),''),
        warranty_from=warranty_from_value,
        warranty_until=warranty_until_value,
        maintenance_plan=coalesce(input_payload->'maintenance_plan',maintenance_plan),
        document_refs=coalesce(input_payload->'document_refs',document_refs),
        commissioning_refs=coalesce(input_payload->'commissioning_refs',commissioning_refs),
        operational_status=coalesce(nullif(lower(btrim(input_payload->>'operational_status')),''),operational_status),
        system_code=upper(btrim(input_payload->>'system_code')),
        verified_by=null,
        verified_at=null,
        updated_at=now()
    where id=asset_id_value returning * into asset;
  end if;

  select organisation_id into org_id from project.projects where id=target_project_id;
  perform audit.append_event(org_id,target_project_id,case when before_state is null then 'handover.asset.created' else 'handover.asset.updated' end,'asset_passport',asset.id,before_state,to_jsonb(asset),null,gen_random_uuid());
  return asset.id;
end;
$$;
revoke all on function public.upsert_asset_passport(uuid,jsonb) from public, anon;
grant execute on function public.upsert_asset_passport(uuid,jsonb) to authenticated;

create or replace function public.verify_asset_passport(target_asset_id uuid,target_reason text default null)
returns text
language plpgsql
security invoker
set search_path = public, project, audit, auth, pg_temp
as $$
declare
  asset public.asset_passports%rowtype;
  before_state jsonb;
  org_id uuid;
begin
  select * into asset from public.asset_passports where id=target_asset_id for update;
  if not found or auth.uid() is null or not project.can_manage_project(asset.project_id) then raise exception 'asset_verification_authority_required'; end if;
  if nullif(asset.system_code,'') is null or nullif(asset.install_location,'') is null then raise exception 'asset_system_location_required'; end if;
  if jsonb_array_length(asset.document_refs)=0 then raise exception 'asset_documentation_required'; end if;
  if asset.warranty_until is not null and asset.warranty_from is not null and asset.warranty_until < asset.warranty_from then raise exception 'warranty_date_invalid'; end if;

  before_state:=to_jsonb(asset);
  perform set_config('conceptspaces.handover_phase','asset_verify',true);
  update public.asset_passports set verified_by=auth.uid(),verified_at=now(),updated_at=now() where id=asset.id returning * into asset;
  select organisation_id into org_id from project.projects where id=asset.project_id;
  perform audit.append_event(org_id,asset.project_id,'handover.asset.verified','asset_passport',asset.id,before_state,to_jsonb(asset),target_reason,gen_random_uuid());
  return 'verified';
end;
$$;
revoke all on function public.verify_asset_passport(uuid,text) from public, anon;
grant execute on function public.verify_asset_passport(uuid,text) to authenticated;

create or replace function public.upsert_material_passport(target_project_id uuid,input_payload jsonb)
returns uuid
language plpgsql
security invoker
set search_path = public, project, audit, auth, pg_temp
as $$
declare
  material public.material_passports%rowtype;
  material_id_value uuid := nullif(input_payload->>'id','')::uuid;
  before_state jsonb;
  org_id uuid;
begin
  if auth.uid() is null or not project.can_manage_project(target_project_id) then raise exception 'project_manage_authority_required'; end if;
  if nullif(btrim(input_payload->>'material_code'),'') is null or nullif(btrim(input_payload->>'name'),'') is null then raise exception 'material_identity_required'; end if;
  if jsonb_typeof(coalesce(input_payload->'evidence_refs','[]'::jsonb))<>'array' or jsonb_array_length(coalesce(input_payload->'evidence_refs','[]'::jsonb))=0 then raise exception 'material_evidence_required'; end if;

  perform set_config('conceptspaces.handover_phase','material',true);
  if material_id_value is null then
    insert into public.material_passports(project_id,material_code,name,manufacturer,product_code,batch_ref,install_locations,quantity,unit,embodied_carbon,recycled_content_percent,warranty_until,maintenance_requirements,end_of_life_route,evidence_refs)
    values(target_project_id,upper(btrim(input_payload->>'material_code')),btrim(input_payload->>'name'),nullif(btrim(input_payload->>'manufacturer'),''),nullif(btrim(input_payload->>'product_code'),''),nullif(btrim(input_payload->>'batch_ref'),''),coalesce(input_payload->'install_locations','[]'::jsonb),nullif(input_payload->>'quantity','')::numeric,nullif(btrim(input_payload->>'unit'),''),nullif(input_payload->>'embodied_carbon','')::numeric,nullif(input_payload->>'recycled_content_percent','')::numeric,nullif(input_payload->>'warranty_until','')::date,coalesce(input_payload->'maintenance_requirements','[]'::jsonb),nullif(btrim(input_payload->>'end_of_life_route'),''),input_payload->'evidence_refs') returning * into material;
  else
    select to_jsonb(m) into before_state from public.material_passports m where m.id=material_id_value and m.project_id=target_project_id;
    if before_state is null then raise exception 'material_not_found'; end if;
    update public.material_passports
    set material_code=upper(btrim(input_payload->>'material_code')),
        name=btrim(input_payload->>'name'),manufacturer=nullif(btrim(input_payload->>'manufacturer'),''),product_code=nullif(btrim(input_payload->>'product_code'),''),batch_ref=nullif(btrim(input_payload->>'batch_ref'),''),install_locations=coalesce(input_payload->'install_locations',install_locations),quantity=nullif(input_payload->>'quantity','')::numeric,unit=nullif(btrim(input_payload->>'unit'),''),embodied_carbon=nullif(input_payload->>'embodied_carbon','')::numeric,recycled_content_percent=nullif(input_payload->>'recycled_content_percent','')::numeric,warranty_until=nullif(input_payload->>'warranty_until','')::date,maintenance_requirements=coalesce(input_payload->'maintenance_requirements',maintenance_requirements),end_of_life_route=nullif(btrim(input_payload->>'end_of_life_route'),''),evidence_refs=input_payload->'evidence_refs'
    where id=material_id_value returning * into material;
  end if;

  select organisation_id into org_id from project.projects where id=target_project_id;
  perform audit.append_event(org_id,target_project_id,case when before_state is null then 'handover.material.created' else 'handover.material.updated' end,'material_passport',material.id,before_state,to_jsonb(material),null,gen_random_uuid());
  return material.id;
end;
$$;
revoke all on function public.upsert_material_passport(uuid,jsonb) from public, anon;
grant execute on function public.upsert_material_passport(uuid,jsonb) to authenticated;

create or replace function public.record_commissioning(target_project_id uuid,input_payload jsonb)
returns uuid
language plpgsql
security invoker
set search_path = public, project, audit, auth, pg_temp
as $$
declare
  rec public.commissioning_records%rowtype;
  org_id uuid;
  result_value text := lower(btrim(input_payload->>'result'));
begin
  if auth.uid() is null or not project.can_manage_project(target_project_id) then raise exception 'project_manage_authority_required'; end if;
  if result_value not in ('pass','conditional','fail') then raise exception 'commissioning_result_invalid'; end if;
  if nullif(btrim(input_payload->>'system_code'),'') is null or nullif(btrim(input_payload->>'test_type'),'') is null or nullif(btrim(input_payload->>'procedure_ref'),'') is null then raise exception 'commissioning_definition_required'; end if;
  if jsonb_typeof(coalesce(input_payload->'evidence_refs','[]'::jsonb))<>'array' or jsonb_array_length(coalesce(input_payload->'evidence_refs','[]'::jsonb))=0 then raise exception 'commissioning_evidence_required'; end if;

  perform set_config('conceptspaces.handover_phase','commissioning',true);
  insert into public.commissioning_records(project_id,system_code,asset_code,test_type,procedure_ref,test_date,result,readings,witness_user_ids,evidence_refs,defects)
  values(target_project_id,upper(btrim(input_payload->>'system_code')),nullif(upper(btrim(input_payload->>'asset_code')),''),btrim(input_payload->>'test_type'),btrim(input_payload->>'procedure_ref'),coalesce(nullif(input_payload->>'test_date','')::date,current_date),result_value,coalesce(input_payload->'readings','{}'::jsonb),coalesce(input_payload->'witness_user_ids','[]'::jsonb),input_payload->'evidence_refs',coalesce(input_payload->'defects','[]'::jsonb)) returning * into rec;

  select organisation_id into org_id from project.projects where id=target_project_id;
  perform audit.append_event(org_id,target_project_id,'handover.commissioning.recorded','commissioning_record',rec.id,null,to_jsonb(rec),result_value,gen_random_uuid());
  return rec.id;
end;
$$;
revoke all on function public.record_commissioning(uuid,jsonb) from public, anon;
grant execute on function public.record_commissioning(uuid,jsonb) to authenticated;

create or replace function public.accept_commissioning(target_record_id uuid,target_reason text default null)
returns text
language plpgsql
security invoker
set search_path = public, project, audit, auth, pg_temp
as $$
declare
  rec public.commissioning_records%rowtype;
  before_state jsonb;
  org_id uuid;
begin
  select * into rec from public.commissioning_records where id=target_record_id for update;
  if not found or auth.uid() is null or not project.can_manage_project(rec.project_id) then raise exception 'commissioning_accept_authority_required'; end if;
  if rec.result='fail' then raise exception 'failed_commissioning_cannot_be_accepted'; end if;
  if jsonb_array_length(rec.evidence_refs)=0 then raise exception 'commissioning_evidence_required'; end if;

  before_state:=to_jsonb(rec);
  perform set_config('conceptspaces.handover_phase','commissioning',true);
  update public.commissioning_records set accepted_by=auth.uid(),accepted_at=now() where id=rec.id returning * into rec;
  select organisation_id into org_id from project.projects where id=rec.project_id;
  perform audit.append_event(org_id,rec.project_id,'handover.commissioning.accepted','commissioning_record',rec.id,before_state,to_jsonb(rec),target_reason,gen_random_uuid());
  return 'accepted';
end;
$$;
revoke all on function public.accept_commissioning(uuid,text) from public, anon;
grant execute on function public.accept_commissioning(uuid,text) to authenticated;

create or replace function public.compile_building_passport(target_project_id uuid)
returns uuid
language plpgsql
security invoker
set search_path = public, project, audit, extensions, auth, pg_temp
as $$
declare
  snapshot jsonb;
  snapshot_hash_value text;
  gap_refs jsonb;
  exception_refs jsonb;
  passport public.building_passports%rowtype;
  version_value integer;
  org_id uuid;
begin
  if auth.uid() is null or not project.can_manage_project(target_project_id) then raise exception 'project_manage_authority_required'; end if;
  perform public.ensure_standard_handover_checklist(target_project_id);

  snapshot:=public.handover_snapshot(target_project_id);
  snapshot_hash_value:=encode(extensions.digest(snapshot::text,'sha256'),'hex');

  select coalesce(jsonb_agg(jsonb_build_object('item_id',h.id,'item_code',h.item_code,'title',h.title,'status',h.status) order by h.item_code),'[]'::jsonb)
  into gap_refs
  from public.handover_items h
  where h.project_id=target_project_id
    and h.mandatory
    and h.status not in ('accepted','not_applicable')
    and not exists (
      select 1 from public.handover_exceptions e
      where e.handover_item_id=h.id and e.project_id=target_project_id and e.status='approved'
    );

  select coalesce(jsonb_agg(jsonb_build_object('id',e.id,'handover_item_id',e.handover_item_id,'reason',e.reason) order by e.created_at,e.id),'[]'::jsonb)
  into exception_refs
  from public.handover_exceptions e
  where e.project_id=target_project_id and e.status='approved';

  select coalesce(max(version),0)+1 into version_value from public.building_passports where project_id=target_project_id;
  perform set_config('conceptspaces.handover_phase','compile',true);
  insert into public.building_passports(project_id,version,handover_snapshot,snapshot_hash,mandatory_gap_refs,exception_refs,status,compiled_by)
  values(target_project_id,version_value,snapshot,snapshot_hash_value,gap_refs,exception_refs,'compiled',auth.uid()) returning * into passport;

  select organisation_id into org_id from project.projects where id=target_project_id;
  perform audit.append_event(org_id,target_project_id,'building_passport.compiled','building_passport',passport.id,null,to_jsonb(passport),snapshot_hash_value,gen_random_uuid());
  return passport.id;
end;
$$;
revoke all on function public.compile_building_passport(uuid) from public, anon;
grant execute on function public.compile_building_passport(uuid) to authenticated;

create or replace function public.issue_building_passport(target_passport_id uuid,target_reason text default null)
returns text
language plpgsql
security invoker
set search_path = public, project, audit, extensions, auth, pg_temp
as $$
declare
  passport public.building_passports%rowtype;
  current_snapshot jsonb;
  current_hash text;
  unresolved_gap_count integer;
  unverified_asset_count integer;
  unaccepted_commissioning_count integer;
  before_state jsonb;
  org_id uuid;
begin
  select * into passport from public.building_passports where id=target_passport_id for update;
  if not found or auth.uid() is null or not project.can_manage_project(passport.project_id) then raise exception 'building_passport_issue_authority_required'; end if;
  if passport.status<>'compiled' then raise exception 'building_passport_not_issuable'; end if;

  current_snapshot:=public.handover_snapshot(passport.project_id);
  current_hash:=encode(extensions.digest(current_snapshot::text,'sha256'),'hex');
  if current_hash<>passport.snapshot_hash then raise exception 'building_passport_snapshot_stale_recompile_required'; end if;

  select count(*) into unresolved_gap_count
  from public.handover_items h
  where h.project_id=passport.project_id and h.mandatory and h.status not in ('accepted','not_applicable')
    and not exists(select 1 from public.handover_exceptions e where e.project_id=h.project_id and e.handover_item_id=h.id and e.status='approved');
  if unresolved_gap_count>0 then raise exception 'mandatory_handover_gaps_open'; end if;

  select count(*) into unverified_asset_count from public.asset_passports a where a.project_id=passport.project_id and a.verified_at is null;
  if unverified_asset_count>0 then raise exception 'unverified_assets_block_handover'; end if;

  select count(*) into unaccepted_commissioning_count from public.commissioning_records c where c.project_id=passport.project_id and (c.result='fail' or c.accepted_at is null);
  if unaccepted_commissioning_count>0 then raise exception 'commissioning_incomplete_blocks_handover'; end if;

  before_state:=to_jsonb(passport);
  perform set_config('conceptspaces.handover_phase','issue',true);
  update public.building_passports set status='issued',issued_by=auth.uid(),issued_at=now() where id=passport.id returning * into passport;

  -- Freeze the exact handover source hash onto verified asset records without changing their evidence payload.
  perform set_config('conceptspaces.handover_phase','asset_verify',true);
  update public.asset_passports set source_building_passport_hash=passport.snapshot_hash,updated_at=now() where project_id=passport.project_id and verified_at is not null;

  select organisation_id into org_id from project.projects where id=passport.project_id;
  perform audit.append_event(org_id,passport.project_id,'building_passport.issued','building_passport',passport.id,before_state,to_jsonb(passport),target_reason,gen_random_uuid());
  return passport.status;
end;
$$;
revoke all on function public.issue_building_passport(uuid,text) from public, anon;
grant execute on function public.issue_building_passport(uuid,text) to authenticated;

create or replace function public.create_maintenance_work_order(target_project_id uuid,input_payload jsonb)
returns uuid
language plpgsql
security invoker
set search_path = public, project, audit, auth, pg_temp
as $$
declare
  work_order public.maintenance_work_orders%rowtype;
  asset public.asset_passports%rowtype;
  asset_id_value uuid:=nullif(input_payload->>'asset_passport_id','')::uuid;
  type_value text:=lower(btrim(input_payload->>'type'));
  priority_value text:=lower(coalesce(nullif(btrim(input_payload->>'priority'),''),'medium'));
  org_id uuid;
begin
  if auth.uid() is null or not project.can_access_project(target_project_id) then raise exception 'project_access_required'; end if;
  if type_value not in ('preventive','predictive','corrective','statutory') then raise exception 'maintenance_type_invalid'; end if;
  if priority_value not in ('low','medium','high','critical') then raise exception 'maintenance_priority_invalid'; end if;
  if nullif(btrim(input_payload->>'title'),'') is null then raise exception 'maintenance_title_required'; end if;
  if asset_id_value is not null then
    select * into asset from public.asset_passports where id=asset_id_value and project_id=target_project_id;
    if not found then raise exception 'maintenance_asset_not_found'; end if;
  end if;

  perform set_config('conceptspaces.handover_phase','maintenance',true);
  insert into public.maintenance_work_orders(project_id,asset_passport_id,title,type,priority,due_at,assignee_ref,status,evidence_refs)
  values(target_project_id,asset_id_value,btrim(input_payload->>'title'),type_value,priority_value,nullif(input_payload->>'due_at','')::timestamptz,nullif(btrim(input_payload->>'assignee_ref'),''),'open',coalesce(input_payload->'evidence_refs','[]'::jsonb)) returning * into work_order;
  select organisation_id into org_id from project.projects where id=target_project_id;
  perform audit.append_event(org_id,target_project_id,'maintenance.work_order.created','maintenance_work_order',work_order.id,null,to_jsonb(work_order),null,gen_random_uuid());
  return work_order.id;
end;
$$;
revoke all on function public.create_maintenance_work_order(uuid,jsonb) from public, anon;
grant execute on function public.create_maintenance_work_order(uuid,jsonb) to authenticated;

create or replace function public.transition_maintenance_work_order(target_work_order_id uuid,target_status text,target_evidence_refs jsonb default null)
returns text
language plpgsql
security invoker
set search_path = public, project, audit, auth, pg_temp
as $$
declare
  work_order public.maintenance_work_orders%rowtype;
  before_state jsonb;
  status_value text:=lower(btrim(target_status));
  org_id uuid;
begin
  select * into work_order from public.maintenance_work_orders where id=target_work_order_id for update;
  if not found or auth.uid() is null or not project.can_access_project(work_order.project_id) then raise exception 'maintenance_access_required'; end if;
  if status_value not in ('scheduled','in_progress','verification','closed') then raise exception 'maintenance_status_invalid'; end if;
  if work_order.status='closed' then raise exception 'maintenance_work_order_closed'; end if;
  if status_value='closed' and (jsonb_typeof(coalesce(target_evidence_refs,work_order.evidence_refs))<>'array' or jsonb_array_length(coalesce(target_evidence_refs,work_order.evidence_refs))=0) then raise exception 'maintenance_closure_evidence_required'; end if;

  before_state:=to_jsonb(work_order);
  perform set_config('conceptspaces.handover_phase','maintenance',true);
  update public.maintenance_work_orders
  set status=status_value,evidence_refs=coalesce(target_evidence_refs,evidence_refs),closed_at=case when status_value='closed' then now() else null end,updated_at=now()
  where id=work_order.id returning * into work_order;
  select organisation_id into org_id from project.projects where id=work_order.project_id;
  perform audit.append_event(org_id,work_order.project_id,'maintenance.work_order.'||status_value,'maintenance_work_order',work_order.id,before_state,to_jsonb(work_order),null,gen_random_uuid());
  return work_order.status;
end;
$$;
revoke all on function public.transition_maintenance_work_order(uuid,text,jsonb) from public, anon;
grant execute on function public.transition_maintenance_work_order(uuid,text,jsonb) to authenticated;

create or replace function public.configure_twin_binding(target_project_id uuid,input_payload jsonb)
returns uuid
language plpgsql
security invoker
set search_path = public, project, audit, auth, pg_temp
as $$
declare
  asset public.asset_passports%rowtype;
  binding public.twin_bindings%rowtype;
  asset_id_value uuid:=nullif(input_payload->>'asset_passport_id','')::uuid;
  provider_value text:=lower(btrim(input_payload->>'provider_key'));
  org_id uuid;
begin
  if auth.uid() is null or not project.can_manage_project(target_project_id) then raise exception 'project_manage_authority_required'; end if;
  select * into asset from public.asset_passports where id=asset_id_value and project_id=target_project_id;
  if not found or asset.verified_at is null then raise exception 'verified_asset_required_for_twin'; end if;
  if nullif(provider_value,'') is null or nullif(btrim(input_payload->>'external_asset_ref'),'') is null then raise exception 'twin_binding_identity_required'; end if;

  perform set_config('conceptspaces.handover_phase','twin',true);
  insert into public.twin_bindings(project_id,asset_passport_id,provider_key,external_asset_ref,telemetry_schema,status,last_seen_at)
  values(target_project_id,asset.id,provider_value,btrim(input_payload->>'external_asset_ref'),coalesce(input_payload->'telemetry_schema','{}'::jsonb),coalesce(nullif(lower(btrim(input_payload->>'status')),''),'configured'),nullif(input_payload->>'last_seen_at','')::timestamptz)
  on conflict(asset_passport_id,provider_key) do update
    set external_asset_ref=excluded.external_asset_ref,telemetry_schema=excluded.telemetry_schema,status=excluded.status,last_seen_at=excluded.last_seen_at,updated_at=now()
  returning * into binding;

  select organisation_id into org_id from project.projects where id=target_project_id;
  perform audit.append_event(org_id,target_project_id,'twin.binding.configured','twin_binding',binding.id,null,to_jsonb(binding),null,gen_random_uuid());
  return binding.id;
end;
$$;
revoke all on function public.configure_twin_binding(uuid,jsonb) from public, anon;
grant execute on function public.configure_twin_binding(uuid,jsonb) to authenticated;

create or replace function public.list_handover_workspace(target_project_id uuid)
returns jsonb
language plpgsql
stable
security invoker
set search_path = public, project, cde, procurement, auth, pg_temp
as $$
begin
  if auth.uid() is null or not project.can_access_project(target_project_id) then raise exception 'project_access_required'; end if;
  return jsonb_build_object(
    'items',coalesce((select jsonb_agg(to_jsonb(h) order by h.mandatory desc,h.item_code) from public.handover_items h where h.project_id=target_project_id),'[]'::jsonb),
    'exceptions',coalesce((select jsonb_agg(to_jsonb(e) order by e.created_at desc) from public.handover_exceptions e where e.project_id=target_project_id),'[]'::jsonb),
    'assets',coalesce((select jsonb_agg(to_jsonb(a) order by a.asset_code) from public.asset_passports a where a.project_id=target_project_id),'[]'::jsonb),
    'materials',coalesce((select jsonb_agg(to_jsonb(m) order by m.material_code) from public.material_passports m where m.project_id=target_project_id),'[]'::jsonb),
    'commissioning',coalesce((select jsonb_agg(to_jsonb(c) order by c.test_date desc,c.system_code) from public.commissioning_records c where c.project_id=target_project_id),'[]'::jsonb),
    'passports',coalesce((select jsonb_agg(to_jsonb(b) order by b.version desc) from public.building_passports b where b.project_id=target_project_id),'[]'::jsonb),
    'work_orders',coalesce((select jsonb_agg(to_jsonb(w) order by w.created_at desc) from public.maintenance_work_orders w where w.project_id=target_project_id),'[]'::jsonb),
    'twin_bindings',coalesce((select jsonb_agg(to_jsonb(t) order by t.created_at desc) from public.twin_bindings t where t.project_id=target_project_id),'[]'::jsonb),
    'models',coalesce((select jsonb_agg(jsonb_build_object('id',m.id,'model_name',m.model_name,'discipline',m.discipline,'revision',m.revision,'status',m.status,'checksum',m.checksum) order by m.discipline,m.model_name) from cde.models m where m.project_id=target_project_id and m.status in ('approved','issued')),'[]'::jsonb),
    'documents',coalesce((select jsonb_agg(jsonb_build_object('id',d.id,'document_number',d.document_number::text,'title',d.title,'revision',d.revision,'status',d.status,'cde_state',d.cde_state) order by d.document_number) from cde.documents d where d.project_id=target_project_id and d.status in ('approved','issued')),'[]'::jsonb)
  );
end;
$$;
revoke all on function public.list_handover_workspace(uuid) from public, anon;
grant execute on function public.list_handover_workspace(uuid) to authenticated;

commit;
