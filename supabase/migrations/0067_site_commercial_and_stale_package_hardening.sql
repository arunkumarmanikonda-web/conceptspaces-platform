begin;

create or replace function public.create_site_observation(target_project_id uuid,input_payload jsonb)
returns uuid
language plpgsql security invoker
set search_path=public,site,cde,project,audit,extensions,auth,pg_temp
as $$
declare o site.observations%rowtype; m cde.models%rowtype; p site.offline_packages%rowtype; org_id uuid; model_id_value uuid:=nullif(input_payload->>'source_model_id','')::uuid; offline_id uuid:=nullif(input_payload->>'offline_package_id','')::uuid; number_value text; type_value text:=lower(coalesce(nullif(btrim(input_payload->>'observation_type'),''),'progress')); current_hash text;
begin
  if auth.uid() is null or not project.can_access_project(target_project_id) then raise exception 'project_access_required'; end if;
  if type_value not in ('progress','quality','safety','material','non_conformance','inspection') then raise exception 'observation_type_invalid'; end if;
  if nullif(btrim(input_payload->>'title'),'') is null then raise exception 'observation_title_required'; end if;
  if offline_id is not null then
    select * into p from site.offline_packages where id=offline_id and project_id=target_project_id and user_id=auth.uid();
    if not found then raise exception 'offline_package_access_denied'; end if;
    current_hash:=encode(extensions.digest(site.current_controlled_snapshot(target_project_id)::text,'sha256'),'hex');
    if p.source_hash<>current_hash or (p.expires_at is not null and p.expires_at<=now()) then raise exception 'STALE_SITE_PACKAGE'; end if;
  end if;
  if model_id_value is not null then select * into m from cde.models where id=model_id_value and project_id=target_project_id and status in ('approved','issued'); if not found then raise exception 'current_approved_model_required'; end if; end if;
  number_value:=coalesce(nullif(btrim(input_payload->>'observation_number'),''),'OBS-'||upper(substr(replace(gen_random_uuid()::text,'-',''),1,8)));
  if current_setting('conceptspaces.site_phase',true)<>'offline_sync' then perform set_config('conceptspaces.site_phase','observation',true); end if;
  insert into site.observations(project_id,observation_number,observation_type,title,description,location_ref,media_refs,related_model_refs,criticality,status,observed_by,observed_at,offline_package_id,source_model_id,source_revision_hash)
  values(target_project_id,number_value,type_value,btrim(input_payload->>'title'),coalesce(nullif(btrim(input_payload->>'description'),''),'No description provided.'),nullif(btrim(input_payload->>'location_ref'),''),coalesce(input_payload->'media_refs','[]'::jsonb),coalesce(input_payload->'related_model_refs','[]'::jsonb),upper(coalesce(nullif(btrim(input_payload->>'criticality'),''),'C1')),'open',auth.uid(),coalesce(nullif(input_payload->>'observed_at','')::timestamptz,now()),offline_id,model_id_value,m.checksum) returning * into o;
  select organisation_id into org_id from project.projects where id=target_project_id;
  perform audit.append_event(org_id,target_project_id,'site.observation.created','site_observation',o.id,null,to_jsonb(o),o.source_revision_hash,gen_random_uuid());
  return o.id;
end;$$;
revoke all on function public.create_site_observation(uuid,jsonb) from public,anon; grant execute on function public.create_site_observation(uuid,jsonb) to authenticated;

create or replace function public.record_site_inspection(target_project_id uuid,input_payload jsonb)
returns uuid
language plpgsql security invoker
set search_path=public,site,cde,project,audit,extensions,auth,pg_temp
as $$
declare i public.inspection_records%rowtype; itp public.inspection_test_plans%rowtype; m cde.models%rowtype; p site.offline_packages%rowtype; n public.non_conformances%rowtype; itp_id_value uuid:=nullif(input_payload->>'itp_id','')::uuid; model_id_value uuid:=nullif(input_payload->>'source_model_id','')::uuid; offline_id uuid:=nullif(input_payload->>'offline_package_id','')::uuid; result_value text:=lower(btrim(input_payload->>'result')); org_id uuid; current_hash text;
begin
  if auth.uid() is null or not project.can_access_project(target_project_id) then raise exception 'project_access_required'; end if;
  select * into itp from public.inspection_test_plans where id=itp_id_value and project_id=target_project_id and status='approved'; if not found then raise exception 'approved_itp_required'; end if;
  if result_value not in ('pass','pass_with_comments','fail') then raise exception 'inspection_result_invalid'; end if;
  if jsonb_typeof(coalesce(input_payload->'evidence_refs','[]'::jsonb))<>'array' or jsonb_array_length(coalesce(input_payload->'evidence_refs','[]'::jsonb))=0 then raise exception 'inspection_evidence_required'; end if;
  if offline_id is not null then
    select * into p from site.offline_packages where id=offline_id and project_id=target_project_id and user_id=auth.uid(); if not found then raise exception 'offline_package_access_denied'; end if;
    current_hash:=encode(extensions.digest(site.current_controlled_snapshot(target_project_id)::text,'sha256'),'hex');
    if p.source_hash<>current_hash or (p.expires_at is not null and p.expires_at<=now()) then raise exception 'STALE_SITE_PACKAGE'; end if;
  end if;
  if model_id_value is not null then select * into m from cde.models where id=model_id_value and project_id=target_project_id and status in ('approved','issued'); if not found then raise exception 'current_approved_model_required'; end if; end if;
  if current_setting('conceptspaces.site_phase',true)<>'offline_sync' then perform set_config('conceptspaces.site_phase','inspection',true); end if;
  insert into public.inspection_records(project_id,itp_id,activity_ref,location_ref,inspected_at,inspector_user_id,result,measurements,media_refs,evidence_refs,offline_package_id,source_model_id,source_revision_hash)
  values(target_project_id,itp.id,nullif(btrim(input_payload->>'activity_ref'),''),nullif(btrim(input_payload->>'location_ref'),''),coalesce(nullif(input_payload->>'inspected_at','')::timestamptz,now()),auth.uid(),result_value,coalesce(input_payload->'measurements','{}'::jsonb),coalesce(input_payload->'media_refs','[]'::jsonb),input_payload->'evidence_refs',offline_id,model_id_value,m.checksum) returning * into i;
  if result_value='fail' then
    perform set_config('conceptspaces.site_phase','inspection',true);
    insert into public.non_conformances(project_id,number,title,description,criticality,location_ref,source_inspection_id,affected_object_refs,disposition,status)
    values(target_project_id,'NCR-'||upper(substr(replace(gen_random_uuid()::text,'-',''),1,8)),coalesce(nullif(btrim(input_payload->>'ncr_title'),''),'Inspection failure · '||itp.code),coalesce(nullif(btrim(input_payload->>'ncr_description'),''),'Inspection failed against approved ITP '||itp.code),upper(coalesce(nullif(btrim(input_payload->>'criticality'),''),'C2')),nullif(btrim(input_payload->>'location_ref'),''),i.id,coalesce(input_payload->'affected_object_refs','[]'::jsonb),'pending','open') returning * into n;
    perform set_config('conceptspaces.site_phase','inspection_link',true); update public.inspection_records set non_conformance_id=n.id where id=i.id;
  end if;
  select organisation_id into org_id from project.projects where id=target_project_id;
  perform audit.append_event(org_id,target_project_id,'site.inspection.recorded','inspection',i.id,null,to_jsonb(i),result_value,gen_random_uuid());
  if n.id is not null then perform audit.append_event(org_id,target_project_id,'site.ncr.opened','ncr',n.id,null,to_jsonb(n),null,gen_random_uuid()); end if;
  return i.id;
end;$$;
revoke all on function public.record_site_inspection(uuid,jsonb) from public,anon; grant execute on function public.record_site_inspection(uuid,jsonb) to authenticated;

create or replace function public.record_progress_measurement(target_project_id uuid,input_payload jsonb)
returns uuid
language plpgsql security invoker
set search_path=public,site,cost,cde,procurement,project,audit,auth,pg_temp
as $$
declare pm site.progress_measurements%rowtype; b cost.boq_lines%rowtype; model cde.models%rowtype; activity site.activities%rowtype; po procurement.purchase_orders%rowtype; boq_id uuid:=nullif(input_payload->>'boq_line_id','')::uuid; model_id_value uuid:=nullif(input_payload->>'source_model_id','')::uuid; activity_id_value uuid:=nullif(input_payload->>'activity_id','')::uuid; po_id_value uuid:=nullif(input_payload->>'purchase_order_id','')::uuid; org_id uuid; measured_value numeric:=nullif(input_payload->>'measured_quantity','')::numeric;
begin
  if auth.uid() is null or not project.can_access_project(target_project_id) then raise exception 'project_access_required'; end if;
  if measured_value is null or measured_value<0 then raise exception 'progress_quantity_invalid'; end if;
  if jsonb_typeof(coalesce(input_payload->'evidence_refs','[]'::jsonb))<>'array' or jsonb_array_length(coalesce(input_payload->'evidence_refs','[]'::jsonb))=0 then raise exception 'PROGRESS_EVIDENCE_MISSING'; end if;
  if boq_id is not null then select bl.* into b from cost.boq_lines bl join cost.cost_plans cp on cp.id=bl.cost_plan_id where bl.id=boq_id and cp.project_id=target_project_id and cp.status='approved'; if not found then raise exception 'approved_boq_line_required'; end if; end if;
  if activity_id_value is not null then select * into activity from site.activities where id=activity_id_value and project_id=target_project_id; if not found then raise exception 'project_activity_required'; end if; end if;
  if po_id_value is not null then select * into po from procurement.purchase_orders where id=po_id_value and project_id=target_project_id and status in ('approved','issued','delivering','closed'); if not found then raise exception 'project_purchase_order_required'; end if; end if;
  if po_id_value is not null and boq_id is not null and not exists(select 1 from procurement.tender_boq_lines tbl where tbl.tender_package_id=po.tender_package_id and tbl.boq_line_id=boq_id) then raise exception 'boq_line_not_in_purchase_order_scope'; end if;
  if model_id_value is not null then select * into model from cde.models where id=model_id_value and project_id=target_project_id and status in ('approved','issued'); if not found then raise exception 'current_approved_model_required'; end if; end if;
  perform set_config('conceptspaces.site_phase','progress',true);
  insert into site.progress_measurements(project_id,activity_id,purchase_order_id,boq_line_id,location_ref,measured_quantity,unit,evidence_refs,source_revision_hash,status,measured_by)
  values(target_project_id,activity_id_value,po_id_value,boq_id,nullif(btrim(input_payload->>'location_ref'),''),measured_value,coalesce(nullif(btrim(input_payload->>'unit'),''),b.unit),input_payload->'evidence_refs',model.checksum,'draft',auth.uid()) returning * into pm;
  select organisation_id into org_id from project.projects where id=target_project_id;
  perform audit.append_event(org_id,target_project_id,'site.progress.measured','progress_measurement',pm.id,null,to_jsonb(pm),pm.source_revision_hash,gen_random_uuid());
  return pm.id;
end;$$;
revoke all on function public.record_progress_measurement(uuid,jsonb) from public,anon; grant execute on function public.record_progress_measurement(uuid,jsonb) to authenticated;

create or replace function public.create_progress_claim(target_project_id uuid,input_payload jsonb)
returns uuid
language plpgsql security invoker
set search_path=public,procurement,project,audit,auth,pg_temp
as $$
declare c public.progress_claims%rowtype; org_id uuid; project_org uuid; contractor_id_value uuid:=nullif(input_payload->>'contractor_id','')::uuid;
begin
  if auth.uid() is null or not project.can_access_project(target_project_id) then raise exception 'project_access_required'; end if;
  if jsonb_typeof(coalesce(input_payload->'evidence_refs','[]'::jsonb))<>'array' or jsonb_array_length(coalesce(input_payload->'evidence_refs','[]'::jsonb))=0 then raise exception 'PROGRESS_EVIDENCE_MISSING'; end if;
  if contractor_id_value is null or nullif(input_payload->>'period_from','') is null or nullif(input_payload->>'period_to','') is null then raise exception 'progress_claim_identity_required'; end if;
  select organisation_id into project_org from project.projects where id=target_project_id;
  if not exists(select 1 from procurement.vendors v where v.id=contractor_id_value and v.organisation_id=project_org and v.status='active') then raise exception 'project_contractor_vendor_required'; end if;
  if not exists(select 1 from procurement.purchase_orders po where po.project_id=target_project_id and po.vendor_id=contractor_id_value and po.status in ('approved','issued','delivering','closed')) then raise exception 'contractor_purchase_order_required'; end if;
  perform set_config('conceptspaces.site_phase','claim',true);
  insert into public.progress_claims(project_id,contractor_id,period_from,period_to,currency,gross_claim,certified_work,material_on_site,retention,deductions,tax,certified_payable,evidence_refs,status)
  values(target_project_id,contractor_id_value,(input_payload->>'period_from')::date,(input_payload->>'period_to')::date,upper(coalesce(nullif(btrim(input_payload->>'currency'),''),'INR')),coalesce(nullif(input_payload->>'gross_claim','')::numeric,0),0,coalesce(nullif(input_payload->>'material_on_site','')::numeric,0),coalesce(nullif(input_payload->>'retention','')::numeric,0),coalesce(nullif(input_payload->>'deductions','')::numeric,0),coalesce(nullif(input_payload->>'tax','')::numeric,0),0,input_payload->'evidence_refs','submitted') returning * into c;
  select organisation_id into org_id from project.projects where id=target_project_id;
  perform audit.append_event(org_id,target_project_id,'site.progress_claim.submitted','progress_claim',c.id,null,to_jsonb(c),null,gen_random_uuid());
  return c.id;
end;$$;
revoke all on function public.create_progress_claim(uuid,jsonb) from public,anon; grant execute on function public.create_progress_claim(uuid,jsonb) to authenticated;

create or replace function public.certify_progress_claim(target_claim_id uuid,input_payload jsonb)
returns text
language plpgsql security invoker
set search_path=public,procurement,project,audit,auth,pg_temp
as $$
declare c public.progress_claims%rowtype; po_limit numeric; prior_certified numeric; certified_value numeric:=coalesce(nullif(input_payload->>'certified_payable','')::numeric,0); certified_work_value numeric:=coalesce(nullif(input_payload->>'certified_work','')::numeric,0); org_id uuid;
begin
  select * into c from public.progress_claims where id=target_claim_id for update;
  if not found or auth.uid() is null or not project.can_manage_project(c.project_id) then raise exception 'progress_claim_certification_authority_required'; end if;
  if c.status not in ('submitted','review') then raise exception 'progress_claim_not_certifiable'; end if;
  with latest_po as (
    select distinct on (po_number) po_number,total,approved_variation_total,status
    from procurement.purchase_orders
    where project_id=c.project_id and vendor_id=c.contractor_id and status in ('approved','issued','delivering','closed')
    order by po_number,version desc
  ) select coalesce(sum(total+approved_variation_total),0) into po_limit from latest_po;
  select coalesce(sum(certified_payable),0) into prior_certified from public.progress_claims where project_id=c.project_id and contractor_id=c.contractor_id and status in ('certified','paid') and id<>c.id;
  if certified_value<0 or prior_certified+certified_value>po_limit then raise exception 'progress_claim_exceeds_po_and_variation_authority'; end if;
  perform set_config('conceptspaces.site_phase','claim_certify',true);
  update public.progress_claims set certified_work=certified_work_value,certified_payable=certified_value,status='certified',certified_by=auth.uid(),updated_at=now() where id=c.id returning * into c;
  select organisation_id into org_id from project.projects where id=c.project_id;
  perform audit.append_event(org_id,c.project_id,'site.progress.certified','progress_claim',c.id,null,to_jsonb(c),input_payload->>'reason',gen_random_uuid());
  return c.status;
end;$$;
revoke all on function public.certify_progress_claim(uuid,jsonb) from public,anon; grant execute on function public.certify_progress_claim(uuid,jsonb) to authenticated;

commit;
