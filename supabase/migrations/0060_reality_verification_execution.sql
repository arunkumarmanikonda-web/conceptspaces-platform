begin;

alter table public.reality_captures add column if not exists review_note text;
alter table public.reality_deviations add column if not exists review_note text;
alter table public.reality_deviations add column if not exists source_model_checksum text;
alter table public.reality_deviations add column if not exists decision_hash text;
alter table public.reality_deviations add column if not exists linked_ncr_id uuid references public.non_conformances(id) on delete set null;

alter table coordination.issue_links drop constraint if exists issue_links_resource_type_check;
alter table coordination.issue_links add constraint issue_links_resource_type_check check(resource_type in ('document','model','truth_record','requirement','design_option','release','site_photo','reality_deviation','asset'));

create or replace function public.register_reality_capture(target_project_id uuid,input_payload jsonb)
returns uuid language plpgsql security invoker
set search_path=public,cde,project,audit,extensions,auth,pg_temp
as $$
declare r public.reality_captures%rowtype; m cde.models%rowtype; model_id_value uuid:=nullif(input_payload->>'model_id','')::uuid; type_value text:=lower(btrim(input_payload->>'capture_type')); provenance jsonb:=coalesce(input_payload->'capture_provenance','{}'::jsonb); tolerance_value jsonb:=coalesce(input_payload->'tolerance','{}'::jsonb); registration_hash_value text; org_id uuid;
begin
  if auth.uid() is null or not project.can_access_project(target_project_id) then raise exception 'project_access_required'; end if;
  if type_value not in ('photo','360','drone','point_cloud','lidar') then raise exception 'reality_capture_type_invalid'; end if;
  if nullif(btrim(input_payload->>'capture_ref'),'') is null then raise exception 'reality_capture_ref_required'; end if;
  select * into m from cde.models where id=model_id_value and project_id=target_project_id and status in ('approved','issued');
  if not found then raise exception 'approved_model_revision_required'; end if;
  if jsonb_typeof(provenance)<>'object' or nullif(btrim(provenance->>'source'),'') is null then raise exception 'capture_provenance_required'; end if;
  if jsonb_typeof(tolerance_value)<>'object' or tolerance_value='{}'::jsonb then raise exception 'reality_tolerance_required'; end if;
  registration_hash_value:=encode(extensions.digest(jsonb_build_object('project_id',target_project_id,'capture_type',type_value,'capture_ref',input_payload->>'capture_ref','model_id',m.id,'model_checksum',m.checksum,'coordinate_system',coalesce(nullif(btrim(input_payload->>'coordinate_system'),''),m.coordinate_system),'tolerance',tolerance_value,'capture_provenance',provenance)::text,'sha256'),'hex');
  perform set_config('conceptspaces.reality_phase','capture',true);
  insert into public.reality_captures(project_id,capture_type,capture_ref,model_ref,coordinate_system,comparison_status,captured_at,captured_by,model_id,model_checksum,tolerance,capture_provenance,registration_hash)
  values(target_project_id,type_value,btrim(input_payload->>'capture_ref'),m.id::text,coalesce(nullif(btrim(input_payload->>'coordinate_system'),''),m.coordinate_system),'queued',coalesce(nullif(input_payload->>'captured_at','')::timestamptz,now()),auth.uid(),m.id,m.checksum,tolerance_value,provenance,registration_hash_value) returning * into r;
  select organisation_id into org_id from project.projects where id=target_project_id;
  perform audit.append_event(org_id,target_project_id,'reality.capture.registered','reality_capture',r.id,null,to_jsonb(r),registration_hash_value,gen_random_uuid());
  return r.id;
end;$$;
revoke all on function public.register_reality_capture(uuid,jsonb) from public,anon;
grant execute on function public.register_reality_capture(uuid,jsonb) to authenticated;

create or replace function public.record_reality_comparison(target_capture_id uuid,input_payload jsonb)
returns text language plpgsql security invoker
set search_path=public,cde,project,audit,extensions,auth,pg_temp
as $$
declare r public.reality_captures%rowtype; m cde.models%rowtype; d public.reality_deviations%rowtype; item jsonb; comparison_hash_value text:=lower(coalesce(input_payload->>'comparison_hash','')); org_id uuid; confidence_value numeric; severity_value text; type_value text; tolerance_num numeric;
begin
  select * into r from public.reality_captures where id=target_capture_id for update;
  if not found or auth.uid() is null or not project.can_manage_project(r.project_id) then raise exception 'reality_compare_authority_required'; end if;
  if r.comparison_status not in ('queued','processing','failed') then raise exception 'reality_capture_not_comparable'; end if;
  select * into m from cde.models where id=r.model_id;
  if not found or m.checksum is distinct from r.model_checksum or m.status not in ('approved','issued') then raise exception 'REALITY_REGISTRATION_FAILED'; end if;
  if comparison_hash_value !~ '^[0-9a-f]{64}$' then raise exception 'reality_comparison_hash_required'; end if;
  if jsonb_typeof(coalesce(input_payload->'deviations','[]'::jsonb))<>'array' then raise exception 'reality_deviations_array_required'; end if;
  perform set_config('conceptspaces.reality_phase','compare',true);
  delete from public.reality_deviations where comparison_id=r.id and status='detected';
  for item in select value from jsonb_array_elements(coalesce(input_payload->'deviations','[]'::jsonb)) loop
    type_value:=lower(btrim(item->>'deviation_type')); severity_value:=lower(btrim(item->>'severity')); confidence_value:=nullif(item->>'confidence','')::numeric; tolerance_num:=nullif(item->>'permitted_tolerance','')::numeric;
    if type_value not in ('position','dimension','missing','unexpected','finish','progress','quality') then raise exception 'reality_deviation_type_invalid'; end if;
    if severity_value not in ('informational','minor','major','critical') then raise exception 'reality_deviation_severity_invalid'; end if;
    if confidence_value is null or confidence_value<0 or confidence_value>1 then raise exception 'reality_confidence_required'; end if;
    if jsonb_typeof(coalesce(item->'evidence_refs','[]'::jsonb))<>'array' or jsonb_array_length(coalesce(item->'evidence_refs','[]'::jsonb))=0 then raise exception 'reality_deviation_evidence_required'; end if;
    insert into public.reality_deviations(comparison_id,project_id,model_object_ref,location_ref,deviation_type,measured_value,permitted_tolerance,unit,severity,status,evidence_refs,confidence,source_model_checksum)
    values(r.id,r.project_id,nullif(btrim(item->>'model_object_ref'),''),nullif(btrim(item->>'location_ref'),''),type_value,nullif(item->>'measured_value','')::numeric,tolerance_num,nullif(btrim(item->>'unit'),''),severity_value,'detected',item->'evidence_refs',confidence_value,r.model_checksum) returning * into d;
  end loop;
  update public.reality_captures set comparison_hash=comparison_hash_value,comparison_status=case when jsonb_array_length(coalesce(input_payload->'deviations','[]'::jsonb))>0 then 'review_required' else 'accepted' end,reviewed_by=case when jsonb_array_length(coalesce(input_payload->'deviations','[]'::jsonb))=0 then auth.uid() else null end,reviewed_at=case when jsonb_array_length(coalesce(input_payload->'deviations','[]'::jsonb))=0 then now() else null end,review_note=null where id=r.id returning * into r;
  select organisation_id into org_id from project.projects where id=r.project_id;
  perform audit.append_event(org_id,r.project_id,'reality.comparison.recorded','reality_capture',r.id,null,to_jsonb(r),comparison_hash_value,gen_random_uuid());
  return r.comparison_status;
end;$$;
revoke all on function public.record_reality_comparison(uuid,jsonb) from public,anon;
grant execute on function public.record_reality_comparison(uuid,jsonb) to authenticated;

create or replace function public.review_reality_deviation(target_deviation_id uuid,target_decision text,input_payload jsonb default '{}'::jsonb)
returns text language plpgsql security invoker
set search_path=public,coordination,project,audit,extensions,auth,pg_temp
as $$
declare d public.reality_deviations%rowtype; r public.reality_captures%rowtype; decision_value text:=lower(btrim(target_decision)); org_id uuid; hash_value text; issue_id uuid; ncr public.non_conformances%rowtype; note_value text:=btrim(input_payload->>'review_note');
begin
  select * into d from public.reality_deviations where id=target_deviation_id for update;
  if not found or auth.uid() is null or not project.can_manage_project(d.project_id) then raise exception 'reality_review_authority_required'; end if;
  select * into r from public.reality_captures where id=d.comparison_id;
  if r.model_checksum is distinct from d.source_model_checksum then raise exception 'reality_source_model_stale'; end if;
  if d.status not in ('detected','review') then raise exception 'reality_deviation_not_reviewable'; end if;
  if decision_value not in ('review','accepted','ncr_raised') then raise exception 'reality_review_decision_invalid'; end if;
  if decision_value in ('accepted','ncr_raised') and nullif(note_value,'') is null then raise exception 'reality_review_note_required'; end if;
  if decision_value='accepted' and d.severity in ('major','critical') and nullif(btrim(input_payload->>'accepted_deviation_ref'),'') is null then raise exception 'major_reality_deviation_approval_ref_required'; end if;
  hash_value:=encode(extensions.digest(jsonb_build_object('deviation_id',d.id,'comparison_hash',r.comparison_hash,'model_checksum',d.source_model_checksum,'decision',decision_value,'review_note',note_value,'accepted_deviation_ref',input_payload->>'accepted_deviation_ref')::text,'sha256'),'hex');
  if decision_value='ncr_raised' then
    issue_id:=public.create_coordination_issue(jsonb_build_object('project_id',d.project_id,'issue_type','coordination','title','Reality deviation · '||upper(d.deviation_type),'description',coalesce(note_value,'Reality comparison deviation requires corrective action.'),'priority',case when d.severity in ('major','critical') then 'critical' else 'high' end,'criticality',case when d.severity='critical' then 'C4' when d.severity='major' then 'C3' else 'C2' end));
    perform set_config('conceptspaces.coordination_phase','raise',true);
    insert into coordination.issue_links(issue_id,resource_type,resource_id,relationship) values(issue_id,'reality_deviation',d.id,'reality_verification') on conflict do nothing;
    perform set_config('conceptspaces.site_phase','reality',true);
    insert into public.non_conformances(project_id,number,title,description,criticality,location_ref,affected_object_refs,disposition,status)
    values(d.project_id,'NCR-'||upper(substr(replace(gen_random_uuid()::text,'-',''),1,8)),'Reality deviation · '||upper(d.deviation_type),note_value,case when d.severity='critical' then 'C4' when d.severity='major' then 'C3' else 'C2' end,d.location_ref,case when d.model_object_ref is null then '[]'::jsonb else jsonb_build_array(d.model_object_ref) end,'pending','open') returning * into ncr;
  end if;
  perform set_config('conceptspaces.reality_phase','review',true);
  update public.reality_deviations set status=decision_value,reviewed_by=auth.uid(),reviewed_at=now(),disposition_by=auth.uid(),review_note=note_value,linked_issue_id=coalesce(issue_id,linked_issue_id),linked_ncr_id=coalesce(ncr.id,linked_ncr_id),decision_hash=hash_value,updated_at=now() where id=d.id returning * into d;
  if not exists(select 1 from public.reality_deviations x where x.comparison_id=d.comparison_id and x.status in ('detected','review')) then
    perform set_config('conceptspaces.reality_phase','compare',true);
    update public.reality_captures set comparison_status='accepted',reviewed_by=auth.uid(),reviewed_at=now(),review_note='All deviations dispositioned by accountable reviewer.' where id=d.comparison_id;
  end if;
  select organisation_id into org_id from project.projects where id=d.project_id;
  perform audit.append_event(org_id,d.project_id,'reality.deviation.'||decision_value,'reality_deviation',d.id,null,to_jsonb(d),hash_value,gen_random_uuid());
  return d.status;
end;$$;
revoke all on function public.review_reality_deviation(uuid,text,jsonb) from public,anon;
grant execute on function public.review_reality_deviation(uuid,text,jsonb) to authenticated;

create or replace function public.list_reality_workspace(target_project_id uuid)
returns jsonb language plpgsql stable security invoker
set search_path=public,cde,project,pg_temp
as $$
begin
  if auth.uid() is null or not project.can_access_project(target_project_id) then raise exception 'project_access_required'; end if;
  return jsonb_build_object(
    'approved_models',coalesce((select jsonb_agg(to_jsonb(m) order by m.updated_at desc) from cde.models m where m.project_id=target_project_id and m.status in ('approved','issued')),'[]'::jsonb),
    'captures',coalesce((select jsonb_agg(to_jsonb(r) order by r.captured_at desc) from public.reality_captures r where r.project_id=target_project_id),'[]'::jsonb),
    'deviations',coalesce((select jsonb_agg(to_jsonb(d) order by d.created_at desc) from public.reality_deviations d where d.project_id=target_project_id),'[]'::jsonb),
    'open_ncrs',coalesce((select jsonb_agg(to_jsonb(n) order by n.created_at desc) from public.non_conformances n where n.project_id=target_project_id and n.status<>'closed'),'[]'::jsonb)
  );
end;$$;
revoke all on function public.list_reality_workspace(uuid) from public,anon;
grant execute on function public.list_reality_workspace(uuid) to authenticated;

commit;