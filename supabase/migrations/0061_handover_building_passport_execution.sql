begin;

alter table public.handover_items add column if not exists source_hash text;
alter table public.handover_exceptions add column if not exists decision_hash text;
alter table public.commissioning_records add column if not exists record_hash text;
alter table public.maintenance_work_orders add column if not exists source_building_passport_hash text;
alter table public.maintenance_work_orders add column if not exists completion_note text;
alter table public.twin_bindings add column if not exists binding_hash text;
alter table public.material_passports add column if not exists passport_hash text;

create index if not exists commissioning_asset_idx on public.commissioning_records(project_id,asset_code,test_date desc);
create index if not exists maintenance_asset_idx on public.maintenance_work_orders(project_id,asset_passport_id,status);

-- Material passports are part of the governed handover dataset.
drop policy if exists material_passports_write on public.material_passports;
create policy material_passports_write on public.material_passports for all to authenticated
using(project.can_manage_project(project_id))
with check(project.can_manage_project(project_id) and current_setting('conceptspaces.handover_phase',true)='material');
grant insert,update on public.material_passports to authenticated;

-- Once issued, a Building Passport's evidence snapshot is immutable. Status may move to superseded only.
create or replace function public.prevent_issued_building_passport_mutation()
returns trigger language plpgsql security definer
set search_path=public,pg_temp
as $$
begin
  if old.status='issued' and (
    new.handover_snapshot is distinct from old.handover_snapshot or
    new.snapshot_hash is distinct from old.snapshot_hash or
    new.mandatory_gap_refs is distinct from old.mandatory_gap_refs or
    new.exception_refs is distinct from old.exception_refs or
    new.project_id is distinct from old.project_id or
    new.version is distinct from old.version
  ) then raise exception 'issued_building_passport_snapshot_immutable'; end if;
  if old.status='issued' and new.status not in ('issued','superseded') then raise exception 'issued_building_passport_terminal'; end if;
  return new;
end;$$;
revoke all on function public.prevent_issued_building_passport_mutation() from public,anon,authenticated;
drop trigger if exists building_passport_immutable_trigger on public.building_passports;
create trigger building_passport_immutable_trigger before update on public.building_passports for each row execute function public.prevent_issued_building_passport_mutation();

create or replace function public.create_handover_item(target_project_id uuid,input_payload jsonb)
returns uuid language plpgsql security invoker
set search_path=public,project,audit,extensions,auth,pg_temp
as $$
declare h public.handover_items%rowtype; org_id uuid; category_value text:=lower(btrim(input_payload->>'category')); hash_value text;
begin
  if auth.uid() is null or not project.can_manage_project(target_project_id) then raise exception 'handover_manage_authority_required'; end if;
  if category_value not in ('as_built','document','commissioning','warranty','training','certificate','asset_data','material_passport','other') then raise exception 'handover_category_invalid'; end if;
  if nullif(btrim(input_payload->>'item_code'),'') is null or nullif(btrim(input_payload->>'title'),'') is null then raise exception 'handover_item_identity_required'; end if;
  hash_value:=encode(extensions.digest(jsonb_build_object('project_id',target_project_id,'item_code',input_payload->>'item_code','category',category_value,'title',input_payload->>'title','mandatory',coalesce((input_payload->>'mandatory')::boolean,true))::text,'sha256'),'hex');
  perform set_config('conceptspaces.handover_phase','item',true);
  insert into public.handover_items(project_id,item_code,category,title,mandatory,evidence_refs,status,source_hash)
  values(target_project_id,btrim(input_payload->>'item_code'),category_value,btrim(input_payload->>'title'),coalesce((input_payload->>'mandatory')::boolean,true),coalesce(input_payload->'evidence_refs','[]'::jsonb),'open',hash_value) returning * into h;
  select organisation_id into org_id from project.projects where id=target_project_id;
  perform audit.append_event(org_id,target_project_id,'handover.item.created','handover_item',h.id,null,to_jsonb(h),hash_value,gen_random_uuid());
  return h.id;
end;$$;
revoke all on function public.create_handover_item(uuid,jsonb) from public,anon;
grant execute on function public.create_handover_item(uuid,jsonb) to authenticated;

create or replace function public.transition_handover_item(target_item_id uuid,target_status text,input_payload jsonb default '{}'::jsonb)
returns text language plpgsql security invoker
set search_path=public,project,audit,extensions,auth,pg_temp
as $$
declare h public.handover_items%rowtype; before_state jsonb; s text:=lower(btrim(target_status)); org_id uuid; evidence jsonb:=coalesce(input_payload->'evidence_refs',h.evidence_refs); new_hash text;
begin
  select * into h from public.handover_items where id=target_item_id for update;
  if not found or auth.uid() is null or not project.can_manage_project(h.project_id) then raise exception 'handover_manage_authority_required'; end if;
  if s not in ('submitted','accepted','not_applicable','open') then raise exception 'handover_status_invalid'; end if;
  if h.status='accepted' then raise exception 'accepted_handover_item_immutable'; end if;
  if s='submitted' and h.status<>'open' then raise exception 'invalid_handover_transition'; end if;
  if s='accepted' and h.status<>'submitted' then raise exception 'invalid_handover_transition'; end if;
  if s='not_applicable' and h.mandatory and nullif(btrim(input_payload->>'reason'),'') is null then raise exception 'mandatory_handover_na_reason_required'; end if;
  if s in ('submitted','accepted') and (jsonb_typeof(evidence)<>'array' or jsonb_array_length(evidence)=0) then raise exception 'handover_evidence_required'; end if;
  new_hash:=encode(extensions.digest(jsonb_build_object('item_id',h.id,'source_hash',h.source_hash,'evidence_refs',evidence,'status',s,'reason',input_payload->>'reason')::text,'sha256'),'hex');
  before_state:=to_jsonb(h); perform set_config('conceptspaces.handover_phase','item',true);
  update public.handover_items set status=s,evidence_refs=evidence,submitted_by=case when s='submitted' then auth.uid() else submitted_by end,accepted_by=case when s='accepted' then auth.uid() else accepted_by end,accepted_at=case when s='accepted' then now() else accepted_at end,source_hash=new_hash,updated_at=now() where id=h.id returning * into h;
  select organisation_id into org_id from project.projects where id=h.project_id;
  perform audit.append_event(org_id,h.project_id,'handover.item.'||s,'handover_item',h.id,before_state,to_jsonb(h),new_hash,gen_random_uuid());
  return h.status;
end;$$;
revoke all on function public.transition_handover_item(uuid,text,jsonb) from public,anon;
grant execute on function public.transition_handover_item(uuid,text,jsonb) to authenticated;

create or replace function public.request_handover_exception(target_item_id uuid,input_payload jsonb)
returns uuid language plpgsql security invoker
set search_path=public,project,audit,auth,pg_temp
as $$
declare h public.handover_items%rowtype; e public.handover_exceptions%rowtype; org_id uuid;
begin
  select * into h from public.handover_items where id=target_item_id;
  if not found or auth.uid() is null or not project.can_access_project(h.project_id) then raise exception 'handover_item_access_required'; end if;
  if not h.mandatory or h.status='accepted' then raise exception 'handover_exception_not_required'; end if;
  if nullif(btrim(input_payload->>'reason'),'') is null or jsonb_array_length(coalesce(input_payload->'evidence_refs','[]'::jsonb))=0 then raise exception 'handover_exception_evidence_required'; end if;
  perform set_config('conceptspaces.handover_phase','exception',true);
  insert into public.handover_exceptions(project_id,handover_item_id,reason,evidence_refs,status,requested_by)
  values(h.project_id,h.id,btrim(input_payload->>'reason'),input_payload->'evidence_refs','requested',auth.uid()) returning * into e;
  select organisation_id into org_id from project.projects where id=h.project_id;
  perform audit.append_event(org_id,h.project_id,'handover.exception.requested','handover_exception',e.id,null,to_jsonb(e),null,gen_random_uuid());
  return e.id;
end;$$;
revoke all on function public.request_handover_exception(uuid,jsonb) from public,anon;
grant execute on function public.request_handover_exception(uuid,jsonb) to authenticated;

create or replace function public.decide_handover_exception(target_exception_id uuid,target_decision text,target_reason text)
returns text language plpgsql security invoker
set search_path=public,project,audit,extensions,auth,pg_temp
as $$
declare e public.handover_exceptions%rowtype; s text:=lower(btrim(target_decision)); org_id uuid; hash_value text;
begin
  select * into e from public.handover_exceptions where id=target_exception_id for update;
  if not found or auth.uid() is null or not project.can_manage_project(e.project_id) then raise exception 'handover_exception_authority_required'; end if;
  if e.status<>'requested' or s not in ('approved','rejected','withdrawn') then raise exception 'handover_exception_not_decidable'; end if;
  if nullif(btrim(target_reason),'') is null then raise exception 'handover_exception_decision_reason_required'; end if;
  hash_value:=encode(extensions.digest(jsonb_build_object('exception_id',e.id,'item_id',e.handover_item_id,'reason',e.reason,'evidence_refs',e.evidence_refs,'decision',s,'decision_reason',target_reason)::text,'sha256'),'hex');
  perform set_config('conceptspaces.handover_phase','exception_decide',true);
  update public.handover_exceptions set status=s,decided_by=auth.uid(),decided_at=now(),decision_hash=hash_value where id=e.id returning * into e;
  select organisation_id into org_id from project.projects where id=e.project_id;
  perform audit.append_event(org_id,e.project_id,'handover.exception.'||s,'handover_exception',e.id,null,to_jsonb(e),hash_value,gen_random_uuid());
  return e.status;
end;$$;
revoke all on function public.decide_handover_exception(uuid,text,text) from public,anon;
grant execute on function public.decide_handover_exception(uuid,text,text) to authenticated;

create or replace function public.register_asset_passport(target_project_id uuid,input_payload jsonb)
returns uuid language plpgsql security invoker
set search_path=public,project,audit,auth,pg_temp
as $$
declare a public.asset_passports%rowtype; org_id uuid;
begin
  if auth.uid() is null or not project.can_manage_project(target_project_id) then raise exception 'asset_manage_authority_required'; end if;
  if nullif(btrim(input_payload->>'asset_code'),'') is null or nullif(btrim(input_payload->>'asset_type'),'') is null then raise exception 'asset_identity_required'; end if;
  if nullif(input_payload->>'warranty_from','') is not null and nullif(input_payload->>'warranty_until','') is not null and (input_payload->>'warranty_until')::date<(input_payload->>'warranty_from')::date then raise exception 'asset_warranty_dates_invalid'; end if;
  perform set_config('conceptspaces.handover_phase','asset',true);
  insert into public.asset_passports(project_id,asset_code,asset_type,manufacturer,model,serial_number,install_location,model_object_ref,warranty_from,warranty_until,maintenance_plan,document_refs,commissioning_refs,operational_status,system_code)
  values(target_project_id,btrim(input_payload->>'asset_code'),btrim(input_payload->>'asset_type'),nullif(btrim(input_payload->>'manufacturer'),''),nullif(btrim(input_payload->>'model'),''),nullif(btrim(input_payload->>'serial_number'),''),nullif(btrim(input_payload->>'install_location'),''),nullif(btrim(input_payload->>'model_object_ref'),''),nullif(input_payload->>'warranty_from','')::date,nullif(input_payload->>'warranty_until','')::date,coalesce(input_payload->'maintenance_plan','{}'::jsonb),coalesce(input_payload->'document_refs','[]'::jsonb),coalesce(input_payload->'commissioning_refs','[]'::jsonb),'planned',nullif(btrim(input_payload->>'system_code'),'')) returning * into a;
  select organisation_id into org_id from project.projects where id=target_project_id;
  perform audit.append_event(org_id,target_project_id,'asset.passport.registered','asset_passport',a.id,null,to_jsonb(a),null,gen_random_uuid());
  return a.id;
end;$$;
revoke all on function public.register_asset_passport(uuid,jsonb) from public,anon;
grant execute on function public.register_asset_passport(uuid,jsonb) to authenticated;

create or replace function public.record_commissioning_record(target_project_id uuid,input_payload jsonb)
returns uuid language plpgsql security invoker
set search_path=public,project,audit,extensions,auth,pg_temp
as $$
declare c public.commissioning_records%rowtype; a public.asset_passports%rowtype; result_value text:=lower(btrim(input_payload->>'result')); org_id uuid; hash_value text;
begin
  if auth.uid() is null or not project.can_manage_project(target_project_id) then raise exception 'commissioning_authority_required'; end if;
  if result_value not in ('pass','conditional','fail') then raise exception 'commissioning_result_invalid'; end if;
  if nullif(btrim(input_payload->>'system_code'),'') is null or nullif(btrim(input_payload->>'test_type'),'') is null or nullif(btrim(input_payload->>'procedure_ref'),'') is null then raise exception 'commissioning_identity_required'; end if;
  if jsonb_array_length(coalesce(input_payload->'evidence_refs','[]'::jsonb))=0 then raise exception 'commissioning_evidence_required'; end if;
  if nullif(btrim(input_payload->>'asset_code'),'') is not null then select * into a from public.asset_passports where project_id=target_project_id and asset_code=btrim(input_payload->>'asset_code'); if not found then raise exception 'commissioning_asset_not_found'; end if; end if;
  hash_value:=encode(extensions.digest(jsonb_build_object('project_id',target_project_id,'system_code',input_payload->>'system_code','asset_code',input_payload->>'asset_code','test_type',input_payload->>'test_type','procedure_ref',input_payload->>'procedure_ref','test_date',input_payload->>'test_date','result',result_value,'readings',coalesce(input_payload->'readings','{}'::jsonb),'evidence_refs',input_payload->'evidence_refs')::text,'sha256'),'hex');
  perform set_config('conceptspaces.handover_phase','commissioning',true);
  insert into public.commissioning_records(project_id,system_code,asset_code,test_type,procedure_ref,test_date,result,readings,witness_user_ids,evidence_refs,defects,record_hash)
  values(target_project_id,btrim(input_payload->>'system_code'),nullif(btrim(input_payload->>'asset_code'),''),btrim(input_payload->>'test_type'),btrim(input_payload->>'procedure_ref'),coalesce(nullif(input_payload->>'test_date','')::date,current_date),result_value,coalesce(input_payload->'readings','{}'::jsonb),coalesce(input_payload->'witness_user_ids','[]'::jsonb),input_payload->'evidence_refs',coalesce(input_payload->'defects','[]'::jsonb),hash_value) returning * into c;
  select organisation_id into org_id from project.projects where id=target_project_id;
  perform audit.append_event(org_id,target_project_id,'asset.commissioning.recorded','commissioning_record',c.id,null,to_jsonb(c),hash_value,gen_random_uuid());
  return c.id;
end;$$;
revoke all on function public.record_commissioning_record(uuid,jsonb) from public,anon;
grant execute on function public.record_commissioning_record(uuid,jsonb) to authenticated;

create or replace function public.accept_commissioning_record(target_record_id uuid,target_reason text default null)
returns text language plpgsql security invoker
set search_path=public,project,audit,auth,pg_temp
as $$
declare c public.commissioning_records%rowtype; org_id uuid;
begin
  select * into c from public.commissioning_records where id=target_record_id;
  if not found or auth.uid() is null or not project.can_manage_project(c.project_id) then raise exception 'commissioning_acceptance_authority_required'; end if;
  if c.result='fail' then raise exception 'failed_commissioning_cannot_be_accepted'; end if;
  if c.accepted_at is not null then raise exception 'commissioning_already_accepted'; end if;
  perform set_config('conceptspaces.handover_phase','commissioning',true);
  update public.commissioning_records set accepted_by=auth.uid(),accepted_at=now() where id=c.id returning * into c;
  if c.asset_code is not null then update public.asset_passports set commissioning_refs=commissioning_refs||jsonb_build_array(c.id),updated_at=now() where project_id=c.project_id and asset_code=c.asset_code; end if;
  select organisation_id into org_id from project.projects where id=c.project_id;
  perform audit.append_event(org_id,c.project_id,'asset.commissioning.accepted','commissioning_record',c.id,null,to_jsonb(c),target_reason,gen_random_uuid());
  return 'accepted';
end;$$;
revoke all on function public.accept_commissioning_record(uuid,text) from public,anon;
grant execute on function public.accept_commissioning_record(uuid,text) to authenticated;

create or replace function public.verify_asset_passport(target_asset_id uuid,target_status text default 'commissioned')
returns text language plpgsql security invoker
set search_path=public,project,audit,auth,pg_temp
as $$
declare a public.asset_passports%rowtype; s text:=lower(btrim(target_status)); org_id uuid;
begin
  select * into a from public.asset_passports where id=target_asset_id for update;
  if not found or auth.uid() is null or not project.can_manage_project(a.project_id) then raise exception 'asset_verify_authority_required'; end if;
  if s not in ('installed','commissioned','active') then raise exception 'asset_status_invalid'; end if;
  if nullif(a.install_location,'') is null or nullif(a.system_code,'') is null or nullif(a.model_object_ref,'') is null or jsonb_array_length(a.document_refs)=0 then raise exception 'asset_traceability_incomplete'; end if;
  if s in ('commissioned','active') and not exists(select 1 from public.commissioning_records c where c.project_id=a.project_id and c.asset_code=a.asset_code and c.result in ('pass','conditional') and c.accepted_at is not null) then raise exception 'accepted_commissioning_required'; end if;
  perform set_config('conceptspaces.handover_phase','asset_verify',true);
  update public.asset_passports set operational_status=s,verified_by=auth.uid(),verified_at=now(),updated_at=now() where id=a.id returning * into a;
  select organisation_id into org_id from project.projects where id=a.project_id;
  perform audit.append_event(org_id,a.project_id,'asset.passport.verified','asset_passport',a.id,null,to_jsonb(a),s,gen_random_uuid());
  return a.operational_status;
end;$$;
revoke all on function public.verify_asset_passport(uuid,text) from public,anon;
grant execute on function public.verify_asset_passport(uuid,text) to authenticated;

create or replace function public.register_material_passport(target_project_id uuid,input_payload jsonb)
returns uuid language plpgsql security invoker
set search_path=public,project,audit,extensions,auth,pg_temp
as $$
declare m public.material_passports%rowtype; org_id uuid; hash_value text;
begin
  if auth.uid() is null or not project.can_manage_project(target_project_id) then raise exception 'material_passport_authority_required'; end if;
  if nullif(btrim(input_payload->>'material_code'),'') is null or nullif(btrim(input_payload->>'name'),'') is null or jsonb_array_length(coalesce(input_payload->'install_locations','[]'::jsonb))=0 then raise exception 'material_passport_identity_required'; end if;
  hash_value:=encode(extensions.digest(jsonb_build_object('project_id',target_project_id,'material_code',input_payload->>'material_code','name',input_payload->>'name','manufacturer',input_payload->>'manufacturer','product_code',input_payload->>'product_code','batch_ref',input_payload->>'batch_ref','install_locations',input_payload->'install_locations','evidence_refs',coalesce(input_payload->'evidence_refs','[]'::jsonb))::text,'sha256'),'hex');
  perform set_config('conceptspaces.handover_phase','material',true);
  insert into public.material_passports(project_id,material_code,name,manufacturer,product_code,batch_ref,install_locations,quantity,unit,embodied_carbon,recycled_content_percent,warranty_until,maintenance_requirements,end_of_life_route,evidence_refs,passport_hash)
  values(target_project_id,btrim(input_payload->>'material_code'),btrim(input_payload->>'name'),nullif(btrim(input_payload->>'manufacturer'),''),nullif(btrim(input_payload->>'product_code'),''),nullif(btrim(input_payload->>'batch_ref'),''),input_payload->'install_locations',nullif(input_payload->>'quantity','')::numeric,nullif(btrim(input_payload->>'unit'),''),nullif(input_payload->>'embodied_carbon','')::numeric,nullif(input_payload->>'recycled_content_percent','')::numeric,nullif(input_payload->>'warranty_until','')::date,coalesce(input_payload->'maintenance_requirements','[]'::jsonb),nullif(btrim(input_payload->>'end_of_life_route'),''),coalesce(input_payload->'evidence_refs','[]'::jsonb),hash_value) returning * into m;
  select organisation_id into org_id from project.projects where id=target_project_id;
  perform audit.append_event(org_id,target_project_id,'asset.material_passport.registered','material_passport',m.id,null,to_jsonb(m),hash_value,gen_random_uuid());
  return m.id;
end;$$;
revoke all on function public.register_material_passport(uuid,jsonb) from public,anon;
grant execute on function public.register_material_passport(uuid,jsonb) to authenticated;

create or replace function public.compile_building_passport(target_project_id uuid)
returns uuid language plpgsql security invoker
set search_path=public,cde,project,audit,extensions,auth,pg_temp
as $$
declare version_value int; snapshot jsonb; gaps jsonb; exceptions jsonb; hash_value text; bp public.building_passports%rowtype; org_id uuid;
begin
  if auth.uid() is null or not project.can_manage_project(target_project_id) then raise exception 'building_passport_authority_required'; end if;
  if not exists(select 1 from public.handover_items h where h.project_id=target_project_id) then raise exception 'handover_checklist_required'; end if;
  select coalesce(max(version),0)+1 into version_value from public.building_passports where project_id=target_project_id;
  gaps:=coalesce((select jsonb_agg(jsonb_build_object('id',h.id,'item_code',h.item_code,'title',h.title,'status',h.status) order by h.item_code) from public.handover_items h where h.project_id=target_project_id and h.mandatory and h.status not in ('accepted','not_applicable')),'[]'::jsonb);
  exceptions:=coalesce((select jsonb_agg(jsonb_build_object('id',e.id,'handover_item_id',e.handover_item_id,'status',e.status,'decision_hash',e.decision_hash) order by e.created_at) from public.handover_exceptions e where e.project_id=target_project_id and e.status='approved'),'[]'::jsonb);
  snapshot:=jsonb_build_object(
    'handover_items',coalesce((select jsonb_agg(to_jsonb(h) order by h.item_code) from public.handover_items h where h.project_id=target_project_id),'[]'::jsonb),
    'approved_exceptions',exceptions,
    'documents',coalesce((select jsonb_agg(jsonb_build_object('id',d.id,'number',d.document_number::text,'revision',d.revision,'status',d.status,'version_id',d.current_version_id,'checksum',v.checksum) order by d.document_number) from cde.documents d left join cde.file_versions v on v.id=d.current_version_id where d.project_id=target_project_id and d.status='issued'),'[]'::jsonb),
    'models',coalesce((select jsonb_agg(jsonb_build_object('id',m.id,'name',m.model_name,'revision',m.revision,'checksum',m.checksum,'status',m.status) order by m.discipline,m.model_name) from cde.models m where m.project_id=target_project_id and m.status='issued'),'[]'::jsonb),
    'assets',coalesce((select jsonb_agg(to_jsonb(a) order by a.asset_code) from public.asset_passports a where a.project_id=target_project_id),'[]'::jsonb),
    'commissioning',coalesce((select jsonb_agg(to_jsonb(c) order by c.test_date,c.id) from public.commissioning_records c where c.project_id=target_project_id),'[]'::jsonb),
    'materials',coalesce((select jsonb_agg(to_jsonb(m) order by m.material_code) from public.material_passports m where m.project_id=target_project_id),'[]'::jsonb)
  );
  hash_value:=encode(extensions.digest(jsonb_build_object('project_id',target_project_id,'version',version_value,'snapshot',snapshot,'mandatory_gaps',gaps,'approved_exceptions',exceptions)::text,'sha256'),'hex');
  perform set_config('conceptspaces.handover_phase','compile',true);
  insert into public.building_passports(project_id,version,handover_snapshot,snapshot_hash,mandatory_gap_refs,exception_refs,status,compiled_by)
  values(target_project_id,version_value,snapshot,hash_value,gaps,exceptions,'compiled',auth.uid()) returning * into bp;
  select organisation_id into org_id from project.projects where id=target_project_id;
  perform audit.append_event(org_id,target_project_id,'handover.building_passport.compiled','building_passport',bp.id,null,to_jsonb(bp),hash_value,gen_random_uuid());
  return bp.id;
end;$$;
revoke all on function public.compile_building_passport(uuid) from public,anon;
grant execute on function public.compile_building_passport(uuid) to authenticated;

create or replace function public.issue_building_passport(target_passport_id uuid,target_reason text)
returns text language plpgsql security invoker
set search_path=public,project,audit,auth,pg_temp
as $$
declare bp public.building_passports%rowtype; gap jsonb; org_id uuid;
begin
  select * into bp from public.building_passports where id=target_passport_id for update;
  if not found or auth.uid() is null or not project.can_manage_project(bp.project_id) then raise exception 'building_passport_authority_required'; end if;
  if bp.status<>'compiled' then raise exception 'building_passport_not_issuable'; end if;
  if nullif(btrim(target_reason),'') is null then raise exception 'building_passport_issue_reason_required'; end if;
  for gap in select value from jsonb_array_elements(bp.mandatory_gap_refs) loop
    if not exists(select 1 from public.handover_exceptions e where e.project_id=bp.project_id and e.handover_item_id=(gap->>'id')::uuid and e.status='approved') then raise exception 'HANDOVER_INCOMPLETE:%',gap->>'item_code'; end if;
  end loop;
  perform set_config('conceptspaces.handover_phase','issue',true);
  update public.building_passports set status='superseded' where project_id=bp.project_id and status='issued' and id<>bp.id;
  update public.building_passports set status='issued',issued_by=auth.uid(),issued_at=now() where id=bp.id returning * into bp;
  perform set_config('conceptspaces.handover_phase','asset_verify',true);
  update public.asset_passports set source_building_passport_hash=bp.snapshot_hash where project_id=bp.project_id and verified_at is not null;
  select organisation_id into org_id from project.projects where id=bp.project_id;
  perform audit.append_event(org_id,bp.project_id,'handover.building_passport.issued','building_passport',bp.id,null,to_jsonb(bp),bp.snapshot_hash,gen_random_uuid());
  return bp.status;
end;$$;
revoke all on function public.issue_building_passport(uuid,text) from public,anon;
grant execute on function public.issue_building_passport(uuid,text) to authenticated;

create or replace function public.create_maintenance_work_order(target_asset_id uuid,input_payload jsonb)
returns uuid language plpgsql security invoker
set search_path=public,project,audit,auth,pg_temp
as $$
declare a public.asset_passports%rowtype; w public.maintenance_work_orders%rowtype; latest_passport public.building_passports%rowtype; org_id uuid; type_value text:=lower(btrim(input_payload->>'type')); priority_value text:=lower(coalesce(nullif(btrim(input_payload->>'priority'),''),'medium'));
begin
  select * into a from public.asset_passports where id=target_asset_id;
  if not found or auth.uid() is null or not project.can_access_project(a.project_id) then raise exception 'asset_access_required'; end if;
  if type_value not in ('preventive','predictive','corrective','statutory') or priority_value not in ('low','medium','high','critical') then raise exception 'maintenance_classification_invalid'; end if;
  select * into latest_passport from public.building_passports where project_id=a.project_id and status='issued' order by version desc limit 1;
  if not found then raise exception 'issued_building_passport_required'; end if;
  perform set_config('conceptspaces.handover_phase','maintenance',true);
  insert into public.maintenance_work_orders(project_id,asset_passport_id,title,type,priority,due_at,assignee_ref,status,evidence_refs,source_building_passport_hash)
  values(a.project_id,a.id,btrim(input_payload->>'title'),type_value,priority_value,nullif(input_payload->>'due_at','')::timestamptz,nullif(btrim(input_payload->>'assignee_ref'),''),'open',coalesce(input_payload->'evidence_refs','[]'::jsonb),latest_passport.snapshot_hash) returning * into w;
  select organisation_id into org_id from project.projects where id=a.project_id;
  perform audit.append_event(org_id,a.project_id,'asset.maintenance.created','maintenance_work_order',w.id,null,to_jsonb(w),latest_passport.snapshot_hash,gen_random_uuid());
  return w.id;
end;$$;
revoke all on function public.create_maintenance_work_order(uuid,jsonb) from public,anon;
grant execute on function public.create_maintenance_work_order(uuid,jsonb) to authenticated;

create or replace function public.transition_maintenance_work_order(target_work_order_id uuid,target_status text,input_payload jsonb default '{}'::jsonb)
returns text language plpgsql security invoker
set search_path=public,project,audit,auth,pg_temp
as $$
declare w public.maintenance_work_orders%rowtype; s text:=lower(btrim(target_status)); org_id uuid;
begin
  select * into w from public.maintenance_work_orders where id=target_work_order_id for update;
  if not found or auth.uid() is null or not project.can_access_project(w.project_id) then raise exception 'maintenance_access_required'; end if;
  if s not in ('scheduled','in_progress','verification','closed') then raise exception 'maintenance_status_invalid'; end if;
  if w.status='closed' then raise exception 'terminal_maintenance_work_order'; end if;
  if s='closed' and (w.status<>'verification' or nullif(btrim(input_payload->>'completion_note'),'') is null or jsonb_array_length(coalesce(input_payload->'evidence_refs',w.evidence_refs))=0) then raise exception 'maintenance_close_evidence_required'; end if;
  perform set_config('conceptspaces.handover_phase','maintenance',true);
  update public.maintenance_work_orders set status=s,evidence_refs=coalesce(input_payload->'evidence_refs',evidence_refs),completion_note=coalesce(nullif(btrim(input_payload->>'completion_note'),''),completion_note),closed_at=case when s='closed' then now() else closed_at end,updated_at=now() where id=w.id returning * into w;
  select organisation_id into org_id from project.projects where id=w.project_id;
  perform audit.append_event(org_id,w.project_id,'asset.maintenance.'||s,'maintenance_work_order',w.id,null,to_jsonb(w),w.source_building_passport_hash,gen_random_uuid());
  return w.status;
end;$$;
revoke all on function public.transition_maintenance_work_order(uuid,text,jsonb) from public,anon;
grant execute on function public.transition_maintenance_work_order(uuid,text,jsonb) to authenticated;

create or replace function public.configure_twin_binding(target_asset_id uuid,input_payload jsonb)
returns uuid language plpgsql security invoker
set search_path=public,project,audit,extensions,auth,pg_temp
as $$
declare a public.asset_passports%rowtype; t public.twin_bindings%rowtype; org_id uuid; hash_value text;
begin
  select * into a from public.asset_passports where id=target_asset_id;
  if not found or auth.uid() is null or not project.can_manage_project(a.project_id) then raise exception 'twin_config_authority_required'; end if;
  if a.verified_at is null then raise exception 'verified_asset_required'; end if;
  if nullif(btrim(input_payload->>'provider_key'),'') is null or nullif(btrim(input_payload->>'external_asset_ref'),'') is null or jsonb_typeof(coalesce(input_payload->'telemetry_schema','{}'::jsonb))<>'object' then raise exception 'twin_binding_definition_required'; end if;
  hash_value:=encode(extensions.digest(jsonb_build_object('asset_id',a.id,'provider_key',input_payload->>'provider_key','external_asset_ref',input_payload->>'external_asset_ref','telemetry_schema',input_payload->'telemetry_schema')::text,'sha256'),'hex');
  perform set_config('conceptspaces.handover_phase','twin',true);
  insert into public.twin_bindings(project_id,asset_passport_id,provider_key,external_asset_ref,telemetry_schema,status,binding_hash)
  values(a.project_id,a.id,btrim(input_payload->>'provider_key'),btrim(input_payload->>'external_asset_ref'),coalesce(input_payload->'telemetry_schema','{}'::jsonb),'configured',hash_value) returning * into t;
  select organisation_id into org_id from project.projects where id=a.project_id;
  perform audit.append_event(org_id,a.project_id,'asset.twin.configured','twin_binding',t.id,null,to_jsonb(t),hash_value,gen_random_uuid());
  return t.id;
end;$$;
revoke all on function public.configure_twin_binding(uuid,jsonb) from public,anon;
grant execute on function public.configure_twin_binding(uuid,jsonb) to authenticated;

create or replace function public.list_asset_operations_workspace(target_project_id uuid)
returns jsonb language plpgsql stable security invoker
set search_path=public,project,pg_temp
as $$
begin
  if auth.uid() is null or not project.can_access_project(target_project_id) then raise exception 'project_access_required'; end if;
  return jsonb_build_object(
    'handover_items',coalesce((select jsonb_agg(to_jsonb(h) order by h.item_code) from public.handover_items h where h.project_id=target_project_id),'[]'::jsonb),
    'exceptions',coalesce((select jsonb_agg(to_jsonb(e) order by e.created_at desc) from public.handover_exceptions e where e.project_id=target_project_id),'[]'::jsonb),
    'building_passports',coalesce((select jsonb_agg(to_jsonb(b) order by b.version desc) from public.building_passports b where b.project_id=target_project_id),'[]'::jsonb),
    'assets',coalesce((select jsonb_agg(to_jsonb(a) order by a.asset_code) from public.asset_passports a where a.project_id=target_project_id),'[]'::jsonb),
    'commissioning',coalesce((select jsonb_agg(to_jsonb(c) order by c.test_date desc,c.id) from public.commissioning_records c where c.project_id=target_project_id),'[]'::jsonb),
    'materials',coalesce((select jsonb_agg(to_jsonb(m) order by m.material_code) from public.material_passports m where m.project_id=target_project_id),'[]'::jsonb),
    'maintenance',coalesce((select jsonb_agg(to_jsonb(w) order by w.created_at desc) from public.maintenance_work_orders w where w.project_id=target_project_id),'[]'::jsonb),
    'twin_bindings',coalesce((select jsonb_agg(to_jsonb(t) order by t.created_at desc) from public.twin_bindings t where t.project_id=target_project_id),'[]'::jsonb)
  );
end;$$;
revoke all on function public.list_asset_operations_workspace(uuid) from public,anon;
grant execute on function public.list_asset_operations_workspace(uuid) to authenticated;

commit;