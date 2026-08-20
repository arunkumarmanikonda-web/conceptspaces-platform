begin;

create or replace function site.current_controlled_snapshot(target_project_id uuid)
returns jsonb
language sql stable security invoker
set search_path=site,cde,project,extensions,pg_temp
as $$
  select jsonb_build_object(
    'documents',coalesce((select jsonb_agg(jsonb_build_object('id',d.id,'number',d.document_number::text,'revision',d.revision,'status',d.status,'cde_state',d.cde_state,'version_id',d.current_version_id,'checksum',v.checksum) order by d.document_number,d.id) from cde.documents d left join cde.file_versions v on v.id=d.current_version_id where d.project_id=target_project_id and d.status in ('approved','issued') and d.cde_state in ('shared','published')),'[]'::jsonb),
    'models',coalesce((select jsonb_agg(jsonb_build_object('id',m.id,'name',m.model_name,'revision',m.revision,'discipline',m.discipline,'status',m.status,'checksum',m.checksum) order by m.discipline,m.model_name,m.id) from cde.models m where m.project_id=target_project_id and m.status in ('approved','issued')),'[]'::jsonb)
  );
$$;
revoke all on function site.current_controlled_snapshot(uuid) from public,anon;
grant execute on function site.current_controlled_snapshot(uuid) to authenticated;

create or replace function public.create_site_offline_package(target_project_id uuid,target_expires_at timestamptz default null)
returns uuid
language plpgsql security invoker
set search_path=public,site,project,audit,extensions,auth,pg_temp
as $$
declare snapshot jsonb; hash_value text; p site.offline_packages%rowtype; org_id uuid;
begin
  if auth.uid() is null or not project.can_access_project(target_project_id) then raise exception 'project_access_required'; end if;
  snapshot:=site.current_controlled_snapshot(target_project_id);
  hash_value:=encode(extensions.digest(snapshot::text,'sha256'),'hex');
  perform set_config('conceptspaces.site_phase','offline_package',true);
  insert into site.offline_packages(project_id,user_id,source_snapshot,source_hash,expires_at,status) values(target_project_id,auth.uid(),snapshot,hash_value,target_expires_at,'active') returning * into p;
  select organisation_id into org_id from project.projects where id=target_project_id;
  perform audit.append_event(org_id,target_project_id,'site.offline_package.created','offline_package',p.id,null,to_jsonb(p),hash_value,gen_random_uuid());
  return p.id;
end;$$;
revoke all on function public.create_site_offline_package(uuid,timestamptz) from public,anon;
grant execute on function public.create_site_offline_package(uuid,timestamptz) to authenticated;

create or replace function public.site_offline_package_status(target_package_id uuid)
returns jsonb
language plpgsql stable security invoker
set search_path=public,site,project,extensions,auth,pg_temp
as $$
declare p site.offline_packages%rowtype; current_snapshot jsonb; current_hash text;
begin
  select * into p from site.offline_packages where id=target_package_id;
  if not found or auth.uid() is null or not (p.user_id=auth.uid() or project.can_manage_project(p.project_id)) then raise exception 'offline_package_access_denied'; end if;
  current_snapshot:=site.current_controlled_snapshot(p.project_id); current_hash:=encode(extensions.digest(current_snapshot::text,'sha256'),'hex');
  return jsonb_build_object('package_id',p.id,'downloaded_hash',p.source_hash,'current_hash',current_hash,'fresh',p.source_hash=current_hash and (p.expires_at is null or p.expires_at>now()),'downloaded_at',p.downloaded_at,'expires_at',p.expires_at);
end;$$;
revoke all on function public.site_offline_package_status(uuid) from public,anon;
grant execute on function public.site_offline_package_status(uuid) to authenticated;

create or replace function public.record_site_diary(target_project_id uuid,input_payload jsonb)
returns uuid
language plpgsql security invoker
set search_path=public,site,project,audit,auth,pg_temp
as $$
declare d site.site_diaries%rowtype; org_id uuid;
begin
  if auth.uid() is null or not project.can_access_project(target_project_id) then raise exception 'project_access_required'; end if;
  perform set_config('conceptspaces.site_phase','diary',true);
  insert into site.site_diaries(project_id,diary_date,weather,manpower,equipment,progress,photos,notes,status,captured_by)
  values(target_project_id,coalesce(nullif(input_payload->>'diary_date','')::date,current_date),coalesce(input_payload->'weather','{}'::jsonb),coalesce(input_payload->'manpower','[]'::jsonb),coalesce(input_payload->'equipment','[]'::jsonb),coalesce(input_payload->'progress','[]'::jsonb),coalesce(input_payload->'photos','[]'::jsonb),nullif(btrim(input_payload->>'notes'),''),'draft',auth.uid()) returning * into d;
  select organisation_id into org_id from project.projects where id=target_project_id;
  perform audit.append_event(org_id,target_project_id,'site.diary.created','site_diary',d.id,null,to_jsonb(d),null,gen_random_uuid());
  return d.id;
end;$$;
revoke all on function public.record_site_diary(uuid,jsonb) from public,anon;
grant execute on function public.record_site_diary(uuid,jsonb) to authenticated;

create or replace function public.create_site_observation(target_project_id uuid,input_payload jsonb)
returns uuid
language plpgsql security invoker
set search_path=public,site,cde,project,audit,auth,pg_temp
as $$
declare o site.observations%rowtype; m cde.models%rowtype; org_id uuid; model_id_value uuid:=nullif(input_payload->>'source_model_id','')::uuid; number_value text;
begin
  if auth.uid() is null or not project.can_access_project(target_project_id) then raise exception 'project_access_required'; end if;
  if model_id_value is not null then
    select * into m from cde.models where id=model_id_value and project_id=target_project_id;
    if not found or m.status not in ('approved','issued') then raise exception 'current_approved_model_required'; end if;
  end if;
  number_value:=coalesce(nullif(btrim(input_payload->>'observation_number'),''),'OBS-'||upper(substr(replace(gen_random_uuid()::text,'-',''),1,8)));
  perform set_config('conceptspaces.site_phase','observation',true);
  insert into site.observations(project_id,observation_number,observation_type,title,description,location_ref,media_refs,related_model_refs,criticality,status,observed_by,observed_at,source_model_id,source_revision_hash)
  values(target_project_id,number_value,coalesce(nullif(lower(btrim(input_payload->>'observation_type')),''),'progress'),btrim(input_payload->>'title'),coalesce(nullif(btrim(input_payload->>'description'),''),'No description provided.'),nullif(btrim(input_payload->>'location_ref'),''),coalesce(input_payload->'media_refs','[]'::jsonb),coalesce(input_payload->'related_model_refs','[]'::jsonb),upper(coalesce(nullif(btrim(input_payload->>'criticality'),''),'C1')),'open',auth.uid(),now(),model_id_value,m.checksum) returning * into o;
  select organisation_id into org_id from project.projects where id=target_project_id;
  perform audit.append_event(org_id,target_project_id,'site.observation.created','site_observation',o.id,null,to_jsonb(o),o.source_revision_hash,gen_random_uuid());
  return o.id;
end;$$;
revoke all on function public.create_site_observation(uuid,jsonb) from public,anon;
grant execute on function public.create_site_observation(uuid,jsonb) to authenticated;

create or replace function public.create_inspection_test_plan(target_project_id uuid,input_payload jsonb)
returns uuid
language plpgsql security invoker
set search_path=public,project,audit,auth,pg_temp
as $$
declare i public.inspection_test_plans%rowtype; org_id uuid;
begin
  if auth.uid() is null or not project.can_manage_project(target_project_id) then raise exception 'project_manage_authority_required'; end if;
  if nullif(btrim(input_payload->>'code'),'') is null or jsonb_typeof(coalesce(input_payload->'acceptance_criteria','[]'::jsonb))<>'array' or jsonb_array_length(coalesce(input_payload->'acceptance_criteria','[]'::jsonb))=0 then raise exception 'itp_definition_required'; end if;
  perform set_config('conceptspaces.site_phase','itp',true);
  insert into public.inspection_test_plans(project_id,code,work_package,activity,acceptance_criteria,reference_documents,hold_points,witness_points,responsible_party,status)
  values(target_project_id,btrim(input_payload->>'code'),btrim(input_payload->>'work_package'),btrim(input_payload->>'activity'),input_payload->'acceptance_criteria',coalesce(input_payload->'reference_documents','[]'::jsonb),coalesce(input_payload->'hold_points','[]'::jsonb),coalesce(input_payload->'witness_points','[]'::jsonb),btrim(input_payload->>'responsible_party'),'draft') returning * into i;
  select organisation_id into org_id from project.projects where id=target_project_id;
  perform audit.append_event(org_id,target_project_id,'site.itp.created','inspection_test_plan',i.id,null,to_jsonb(i),null,gen_random_uuid());
  return i.id;
end;$$;
revoke all on function public.create_inspection_test_plan(uuid,jsonb) from public,anon;
grant execute on function public.create_inspection_test_plan(uuid,jsonb) to authenticated;

create or replace function public.approve_inspection_test_plan(target_itp_id uuid,target_reason text default null)
returns text
language plpgsql security invoker
set search_path=public,project,audit,auth,pg_temp
as $$
declare i public.inspection_test_plans%rowtype; org_id uuid;
begin
  select * into i from public.inspection_test_plans where id=target_itp_id for update;
  if not found or auth.uid() is null or not project.can_manage_project(i.project_id) then raise exception 'itp_approval_authority_required'; end if;
  if i.status<>'draft' then raise exception 'itp_not_approvable'; end if;
  perform set_config('conceptspaces.site_phase','itp',true);
  update public.inspection_test_plans set status='approved',approved_by=auth.uid(),updated_at=now() where id=i.id returning * into i;
  select organisation_id into org_id from project.projects where id=i.project_id;
  perform audit.append_event(org_id,i.project_id,'site.itp.approved','inspection_test_plan',i.id,null,to_jsonb(i),target_reason,gen_random_uuid());
  return i.status;
end;$$;
revoke all on function public.approve_inspection_test_plan(uuid,text) from public,anon;
grant execute on function public.approve_inspection_test_plan(uuid,text) to authenticated;

create or replace function public.record_site_inspection(target_project_id uuid,input_payload jsonb)
returns uuid
language plpgsql security invoker
set search_path=public,cde,project,audit,auth,pg_temp
as $$
declare i public.inspection_records%rowtype; itp public.inspection_test_plans%rowtype; m cde.models%rowtype; n public.non_conformances%rowtype; itp_id_value uuid:=nullif(input_payload->>'itp_id','')::uuid; model_id_value uuid:=nullif(input_payload->>'source_model_id','')::uuid; result_value text:=lower(btrim(input_payload->>'result')); org_id uuid;
begin
  if auth.uid() is null or not project.can_access_project(target_project_id) then raise exception 'project_access_required'; end if;
  select * into itp from public.inspection_test_plans where id=itp_id_value and project_id=target_project_id and status='approved'; if not found then raise exception 'approved_itp_required'; end if;
  if result_value not in ('pass','pass_with_comments','fail') then raise exception 'inspection_result_invalid'; end if;
  if jsonb_typeof(coalesce(input_payload->'evidence_refs','[]'::jsonb))<>'array' or jsonb_array_length(coalesce(input_payload->'evidence_refs','[]'::jsonb))=0 then raise exception 'inspection_evidence_required'; end if;
  if model_id_value is not null then select * into m from cde.models where id=model_id_value and project_id=target_project_id and status in ('approved','issued'); if not found then raise exception 'current_approved_model_required'; end if; end if;
  perform set_config('conceptspaces.site_phase','inspection',true);
  insert into public.inspection_records(project_id,itp_id,activity_ref,location_ref,inspected_at,inspector_user_id,result,measurements,media_refs,evidence_refs,offline_package_id,source_model_id,source_revision_hash)
  values(target_project_id,itp.id,nullif(btrim(input_payload->>'activity_ref'),''),nullif(btrim(input_payload->>'location_ref'),''),coalesce(nullif(input_payload->>'inspected_at','')::timestamptz,now()),auth.uid(),result_value,coalesce(input_payload->'measurements','{}'::jsonb),coalesce(input_payload->'media_refs','[]'::jsonb),input_payload->'evidence_refs',nullif(input_payload->>'offline_package_id','')::uuid,model_id_value,m.checksum) returning * into i;
  if result_value='fail' then
    insert into public.non_conformances(project_id,number,title,description,criticality,location_ref,source_inspection_id,affected_object_refs,disposition,status)
    values(target_project_id,'NCR-'||upper(substr(replace(gen_random_uuid()::text,'-',''),1,8)),coalesce(nullif(btrim(input_payload->>'ncr_title'),''),'Inspection failure · '||itp.code),coalesce(nullif(btrim(input_payload->>'ncr_description'),''),'Inspection failed against approved ITP '||itp.code),upper(coalesce(nullif(btrim(input_payload->>'criticality'),''),'C2')),nullif(btrim(input_payload->>'location_ref'),''),i.id,coalesce(input_payload->'affected_object_refs','[]'::jsonb),'pending','open') returning * into n;
    update public.inspection_records set non_conformance_id=n.id where id=i.id;
  end if;
  select organisation_id into org_id from project.projects where id=target_project_id;
  perform audit.append_event(org_id,target_project_id,'site.inspection.recorded','inspection',i.id,null,to_jsonb(i),result_value,gen_random_uuid());
  if n.id is not null then perform audit.append_event(org_id,target_project_id,'site.ncr.opened','ncr',n.id,null,to_jsonb(n),null,gen_random_uuid()); end if;
  return i.id;
end;$$;
revoke all on function public.record_site_inspection(uuid,jsonb) from public,anon;
grant execute on function public.record_site_inspection(uuid,jsonb) to authenticated;

create or replace function public.transition_non_conformance(target_ncr_id uuid,target_status text,input_payload jsonb default '{}'::jsonb)
returns text
language plpgsql security invoker
set search_path=public,project,audit,auth,pg_temp
as $$
declare n public.non_conformances%rowtype; before_state jsonb; s text:=lower(btrim(target_status)); org_id uuid;
begin
  select * into n from public.non_conformances where id=target_ncr_id for update;
  if not found or auth.uid() is null or not project.can_manage_project(n.project_id) then raise exception 'ncr_manage_authority_required'; end if;
  if s not in ('corrective_action','verification','closed') then raise exception 'unsupported_ncr_transition'; end if;
  if n.status='closed' then raise exception 'terminal_ncr'; end if;
  if s='corrective_action' and (n.status<>'open' or nullif(btrim(input_payload->>'root_cause'),'') is null or nullif(btrim(input_payload->>'corrective_action'),'') is null) then raise exception 'ncr_root_cause_and_action_required'; end if;
  if s='verification' and n.status<>'corrective_action' then raise exception 'invalid_ncr_transition'; end if;
  if s='closed' and n.status<>'verification' then raise exception 'ncr_reinspection_required'; end if;
  before_state:=to_jsonb(n); perform set_config('conceptspaces.site_phase','ncr',true);
  update public.non_conformances set status=s,root_cause=coalesce(nullif(btrim(input_payload->>'root_cause'),''),root_cause),corrective_action=coalesce(nullif(btrim(input_payload->>'corrective_action'),''),corrective_action),closed_by=case when s='closed' then auth.uid() else closed_by end,closed_at=case when s='closed' then now() else closed_at end,updated_at=now() where id=n.id returning * into n;
  select organisation_id into org_id from project.projects where id=n.project_id;
  perform audit.append_event(org_id,n.project_id,'site.ncr.'||s,'ncr',n.id,before_state,to_jsonb(n),input_payload->>'reason',gen_random_uuid());
  return n.status;
end;$$;
revoke all on function public.transition_non_conformance(uuid,text,jsonb) from public,anon;
grant execute on function public.transition_non_conformance(uuid,text,jsonb) to authenticated;

create or replace function public.record_progress_measurement(target_project_id uuid,input_payload jsonb)
returns uuid
language plpgsql security invoker
set search_path=public,site,cost,cde,project,audit,auth,pg_temp
as $$
declare m site.progress_measurements%rowtype; b cost.boq_lines%rowtype; model cde.models%rowtype; boq_id uuid:=nullif(input_payload->>'boq_line_id','')::uuid; org_id uuid;
begin
  if auth.uid() is null or not project.can_access_project(target_project_id) then raise exception 'project_access_required'; end if;
  if jsonb_typeof(coalesce(input_payload->'evidence_refs','[]'::jsonb))<>'array' or jsonb_array_length(coalesce(input_payload->'evidence_refs','[]'::jsonb))=0 then raise exception 'PROGRESS_EVIDENCE_MISSING'; end if;
  if boq_id is not null then select bl.* into b from cost.boq_lines bl join cost.cost_plans cp on cp.id=bl.cost_plan_id where bl.id=boq_id and cp.project_id=target_project_id and cp.status='approved'; if not found then raise exception 'approved_boq_line_required'; end if; end if;
  if nullif(input_payload->>'source_model_id','') is not null then select * into model from cde.models where id=(input_payload->>'source_model_id')::uuid and project_id=target_project_id and status in ('approved','issued'); if not found then raise exception 'current_approved_model_required'; end if; end if;
  perform set_config('conceptspaces.site_phase','progress',true);
  insert into site.progress_measurements(project_id,activity_id,purchase_order_id,boq_line_id,location_ref,measured_quantity,unit,evidence_refs,source_revision_hash,status,measured_by)
  values(target_project_id,nullif(input_payload->>'activity_id','')::uuid,nullif(input_payload->>'purchase_order_id','')::uuid,boq_id,nullif(btrim(input_payload->>'location_ref'),''),(input_payload->>'measured_quantity')::numeric,coalesce(nullif(btrim(input_payload->>'unit'),''),b.unit),input_payload->'evidence_refs',model.checksum,'draft',auth.uid()) returning * into m;
  select organisation_id into org_id from project.projects where id=target_project_id;
  perform audit.append_event(org_id,target_project_id,'site.progress.measured','progress_measurement',m.id,null,to_jsonb(m),m.source_revision_hash,gen_random_uuid());
  return m.id;
end;$$;
revoke all on function public.record_progress_measurement(uuid,jsonb) from public,anon;
grant execute on function public.record_progress_measurement(uuid,jsonb) to authenticated;

create or replace function public.certify_progress_measurement(target_measurement_id uuid,target_decision text,target_reason text)
returns text
language plpgsql security invoker
set search_path=public,site,cost,project,audit,auth,pg_temp
as $$
declare m site.progress_measurements%rowtype; b cost.boq_lines%rowtype; prior_qty numeric; s text:=lower(btrim(target_decision)); org_id uuid;
begin
  select * into m from site.progress_measurements where id=target_measurement_id for update;
  if not found or auth.uid() is null or not project.can_manage_project(m.project_id) then raise exception 'progress_certification_authority_required'; end if;
  if m.status<>'draft' or s not in ('certified','rejected') then raise exception 'progress_measurement_not_decidable'; end if;
  if s='certified' and m.boq_line_id is not null then
    select * into b from cost.boq_lines where id=m.boq_line_id;
    select coalesce(sum(measured_quantity),0) into prior_qty from site.progress_measurements where project_id=m.project_id and boq_line_id=m.boq_line_id and status='certified' and id<>m.id;
    if prior_qty+m.measured_quantity>b.quantity then raise exception 'progress_exceeds_approved_boq_quantity'; end if;
  end if;
  perform set_config('conceptspaces.site_phase','progress_certify',true);
  update site.progress_measurements set status=s,certified_by=case when s='certified' then auth.uid() else null end,certified_at=case when s='certified' then now() else null end where id=m.id returning * into m;
  select organisation_id into org_id from project.projects where id=m.project_id;
  perform audit.append_event(org_id,m.project_id,'site.progress.'||s,'progress_measurement',m.id,null,to_jsonb(m),target_reason,gen_random_uuid());
  return m.status;
end;$$;
revoke all on function public.certify_progress_measurement(uuid,text,text) from public,anon;
grant execute on function public.certify_progress_measurement(uuid,text,text) to authenticated;

create or replace function public.propose_site_variation(target_project_id uuid,input_payload jsonb)
returns uuid
language plpgsql security invoker
set search_path=public,site,procurement,project,audit,auth,pg_temp
as $$
declare v site.variations%rowtype; po procurement.purchase_orders%rowtype; po_id uuid:=nullif(input_payload->>'purchase_order_id','')::uuid; org_id uuid;
begin
  if auth.uid() is null or not project.can_manage_project(target_project_id) then raise exception 'project_manage_authority_required'; end if;
  if po_id is not null then select * into po from procurement.purchase_orders where id=po_id and project_id=target_project_id and status in ('approved','issued','delivering'); if not found then raise exception 'active_po_required'; end if; end if;
  perform set_config('conceptspaces.site_phase','variation',true);
  insert into site.variations(project_id,purchase_order_id,variation_ref,description,amount,affected_boq_refs,evidence_refs,status,proposed_by)
  values(target_project_id,po_id,btrim(input_payload->>'variation_ref'),btrim(input_payload->>'description'),coalesce(nullif(input_payload->>'amount','')::numeric,0),coalesce(input_payload->'affected_boq_refs','[]'::jsonb),coalesce(input_payload->'evidence_refs','[]'::jsonb),'proposed',auth.uid()) returning * into v;
  select organisation_id into org_id from project.projects where id=target_project_id;
  perform audit.append_event(org_id,target_project_id,'site.variation.proposed','variation',v.id,null,to_jsonb(v),null,gen_random_uuid());
  return v.id;
end;$$;
revoke all on function public.propose_site_variation(uuid,jsonb) from public,anon;
grant execute on function public.propose_site_variation(uuid,jsonb) to authenticated;

create or replace function public.decide_site_variation(target_variation_id uuid,target_decision text,target_reason text)
returns text
language plpgsql security invoker
set search_path=public,site,procurement,project,audit,extensions,auth,pg_temp
as $$
declare v site.variations%rowtype; s text:=lower(btrim(target_decision)); org_id uuid; hash_value text; variation_total numeric;
begin
  select * into v from site.variations where id=target_variation_id for update;
  if not found or auth.uid() is null or not project.can_manage_project(v.project_id) then raise exception 'variation_decision_authority_required'; end if;
  if v.status<>'proposed' or s not in ('approved','rejected') then raise exception 'variation_not_decidable'; end if;
  if nullif(btrim(target_reason),'') is null then raise exception 'variation_decision_reason_required'; end if;
  hash_value:=encode(extensions.digest(jsonb_build_object('variation_id',v.id,'ref',v.variation_ref,'amount',v.amount,'affected_boq_refs',v.affected_boq_refs,'evidence_refs',v.evidence_refs,'decision',s,'reason',target_reason)::text,'sha256'),'hex');
  perform set_config('conceptspaces.site_phase','variation_decide',true);
  update site.variations set status=s,decision_hash=hash_value,approved_by=case when s='approved' then auth.uid() else null end,approved_at=case when s='approved' then now() else null end,updated_at=now() where id=v.id returning * into v;
  if v.purchase_order_id is not null and s='approved' then
    select coalesce(sum(amount),0) into variation_total from site.variations where purchase_order_id=v.purchase_order_id and status='approved';
    perform set_config('conceptspaces.procurement_phase','po_transition',true);
    update procurement.purchase_orders set approved_variation_total=variation_total,updated_at=now() where id=v.purchase_order_id;
  end if;
  select organisation_id into org_id from project.projects where id=v.project_id;
  perform audit.append_event(org_id,v.project_id,'site.variation.'||s,'variation',v.id,null,to_jsonb(v),target_reason,gen_random_uuid());
  return v.status;
end;$$;
revoke all on function public.decide_site_variation(uuid,text,text) from public,anon;
grant execute on function public.decide_site_variation(uuid,text,text) to authenticated;

create policy progress_claims_site_insert on public.progress_claims for insert to authenticated with check(project.can_access_project(project_id) and current_setting('conceptspaces.site_phase',true)='claim');
create policy progress_claims_site_update on public.progress_claims for update to authenticated using(project.can_manage_project(project_id)) with check(project.can_manage_project(project_id) and current_setting('conceptspaces.site_phase',true)='claim_certify');
grant insert,update on public.progress_claims to authenticated;

create or replace function public.create_progress_claim(target_project_id uuid,input_payload jsonb)
returns uuid
language plpgsql security invoker
set search_path=public,project,audit,auth,pg_temp
as $$
declare c public.progress_claims%rowtype; org_id uuid;
begin
  if auth.uid() is null or not project.can_access_project(target_project_id) then raise exception 'project_access_required'; end if;
  if jsonb_typeof(coalesce(input_payload->'evidence_refs','[]'::jsonb))<>'array' or jsonb_array_length(coalesce(input_payload->'evidence_refs','[]'::jsonb))=0 then raise exception 'PROGRESS_EVIDENCE_MISSING'; end if;
  perform set_config('conceptspaces.site_phase','claim',true);
  insert into public.progress_claims(project_id,contractor_id,period_from,period_to,currency,gross_claim,certified_work,material_on_site,retention,deductions,tax,certified_payable,evidence_refs,status)
  values(target_project_id,(input_payload->>'contractor_id')::uuid,(input_payload->>'period_from')::date,(input_payload->>'period_to')::date,upper(coalesce(nullif(btrim(input_payload->>'currency'),''),'INR')),coalesce(nullif(input_payload->>'gross_claim','')::numeric,0),0,coalesce(nullif(input_payload->>'material_on_site','')::numeric,0),coalesce(nullif(input_payload->>'retention','')::numeric,0),coalesce(nullif(input_payload->>'deductions','')::numeric,0),coalesce(nullif(input_payload->>'tax','')::numeric,0),0,input_payload->'evidence_refs','submitted') returning * into c;
  select organisation_id into org_id from project.projects where id=target_project_id;
  perform audit.append_event(org_id,target_project_id,'site.progress_claim.submitted','progress_claim',c.id,null,to_jsonb(c),null,gen_random_uuid());
  return c.id;
end;$$;
revoke all on function public.create_progress_claim(uuid,jsonb) from public,anon;
grant execute on function public.create_progress_claim(uuid,jsonb) to authenticated;

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
  select coalesce(sum(total+approved_variation_total),0) into po_limit from procurement.purchase_orders where project_id=c.project_id and vendor_id=c.contractor_id and status in ('approved','issued','delivering','closed');
  select coalesce(sum(certified_payable),0) into prior_certified from public.progress_claims where project_id=c.project_id and contractor_id=c.contractor_id and status in ('certified','paid') and id<>c.id;
  if certified_value<0 or prior_certified+certified_value>po_limit then raise exception 'progress_claim_exceeds_po_and_variation_authority'; end if;
  perform set_config('conceptspaces.site_phase','claim_certify',true);
  update public.progress_claims set certified_work=certified_work_value,certified_payable=certified_value,status='certified',certified_by=auth.uid(),updated_at=now() where id=c.id returning * into c;
  select organisation_id into org_id from project.projects where id=c.project_id;
  perform audit.append_event(org_id,c.project_id,'site.progress.certified','progress_claim',c.id,null,to_jsonb(c),input_payload->>'reason',gen_random_uuid());
  return c.status;
end;$$;
revoke all on function public.certify_progress_claim(uuid,jsonb) from public,anon;
grant execute on function public.certify_progress_claim(uuid,jsonb) to authenticated;

create or replace function public.sync_site_offline_changes(target_package_id uuid,target_changes jsonb)
returns jsonb
language plpgsql security invoker
set search_path=public,site,project,extensions,auth,pg_temp
as $$
declare p site.offline_packages%rowtype; current_snapshot jsonb; current_hash text; change_item jsonb; c site.offline_changes%rowtype; results jsonb:='[]'::jsonb; resource_id uuid;
begin
  select * into p from site.offline_packages where id=target_package_id for update;
  if not found or auth.uid() is null or p.user_id<>auth.uid() then raise exception 'offline_package_access_denied'; end if;
  if jsonb_typeof(target_changes)<>'array' then raise exception 'offline_changes_array_required'; end if;
  current_snapshot:=site.current_controlled_snapshot(p.project_id); current_hash:=encode(extensions.digest(current_snapshot::text,'sha256'),'hex');
  perform set_config('conceptspaces.site_phase','offline_sync',true);
  for change_item in select value from jsonb_array_elements(target_changes) loop
    insert into site.offline_changes(offline_package_id,project_id,user_id,local_change_id,entity_type,payload,client_created_at,status)
    values(p.id,p.project_id,auth.uid(),btrim(change_item->>'local_change_id'),lower(btrim(change_item->>'entity_type')),coalesce(change_item->'payload','{}'::jsonb),coalesce(nullif(change_item->>'client_created_at','')::timestamptz,now()),'queued')
    on conflict(offline_package_id,local_change_id) do update set payload=excluded.payload returning * into c;
    if p.source_hash<>current_hash or (p.expires_at is not null and p.expires_at<=now()) then
      update site.offline_changes set status='conflict',conflict_reason='STALE_SITE_PACKAGE' where id=c.id;
      results:=results||jsonb_build_array(jsonb_build_object('local_change_id',c.local_change_id,'status','conflict','error','STALE_SITE_PACKAGE'));
      continue;
    end if;
    resource_id:=null;
    if c.entity_type='site_diary' then resource_id:=public.record_site_diary(p.project_id,c.payload);
    elsif c.entity_type in ('observation','photo_note') then resource_id:=public.create_site_observation(p.project_id,c.payload||jsonb_build_object('offline_package_id',p.id));
    elsif c.entity_type='inspection' then resource_id:=public.record_site_inspection(p.project_id,c.payload||jsonb_build_object('offline_package_id',p.id));
    elsif c.entity_type='rfi' then resource_id:=public.create_coordination_issue(c.payload||jsonb_build_object('project_id',p.project_id,'issue_type','rfi'));
    end if;
    update site.offline_changes set status='synced',server_resource_id=resource_id,synced_at=now() where id=c.id;
    results:=results||jsonb_build_array(jsonb_build_object('local_change_id',c.local_change_id,'status','synced','resource_id',resource_id));
  end loop;
  if p.source_hash<>current_hash then update site.offline_packages set status='stale' where id=p.id; end if;
  return jsonb_build_object('package_id',p.id,'downloaded_hash',p.source_hash,'current_hash',current_hash,'results',results);
end;$$;
revoke all on function public.sync_site_offline_changes(uuid,jsonb) from public,anon;
grant execute on function public.sync_site_offline_changes(uuid,jsonb) to authenticated;

create or replace function public.list_site_delivery_workspace(target_project_id uuid)
returns jsonb
language plpgsql stable security invoker
set search_path=public,site,coordination,project,pg_temp
as $$
begin
  if auth.uid() is null or not project.can_access_project(target_project_id) then raise exception 'project_access_required'; end if;
  return jsonb_build_object(
    'activities',coalesce((select jsonb_agg(to_jsonb(a) order by a.wbs_code) from site.activities a where a.project_id=target_project_id),'[]'::jsonb),
    'diaries',coalesce((select jsonb_agg(to_jsonb(d) order by d.diary_date desc) from site.site_diaries d where d.project_id=target_project_id),'[]'::jsonb),
    'observations',coalesce((select jsonb_agg(to_jsonb(o) order by o.observed_at desc) from site.observations o where o.project_id=target_project_id),'[]'::jsonb),
    'rfis',coalesce((select jsonb_agg(to_jsonb(i) order by i.created_at desc) from coordination.issues i where i.project_id=target_project_id and i.issue_type='rfi'),'[]'::jsonb),
    'itps',coalesce((select jsonb_agg(to_jsonb(i) order by i.created_at desc) from public.inspection_test_plans i where i.project_id=target_project_id),'[]'::jsonb),
    'inspections',coalesce((select jsonb_agg(to_jsonb(i) order by i.inspected_at desc) from public.inspection_records i where i.project_id=target_project_id),'[]'::jsonb),
    'ncrs',coalesce((select jsonb_agg(to_jsonb(n) order by n.created_at desc) from public.non_conformances n where n.project_id=target_project_id),'[]'::jsonb),
    'measurements',coalesce((select jsonb_agg(to_jsonb(m) order by m.created_at desc) from site.progress_measurements m where m.project_id=target_project_id),'[]'::jsonb),
    'claims',coalesce((select jsonb_agg(to_jsonb(c) order by c.period_to desc) from public.progress_claims c where c.project_id=target_project_id),'[]'::jsonb),
    'variations',coalesce((select jsonb_agg(to_jsonb(v) order by v.created_at desc) from site.variations v where v.project_id=target_project_id),'[]'::jsonb),
    'offline_packages',coalesce((select jsonb_agg(to_jsonb(p) order by p.downloaded_at desc) from site.offline_packages p where p.project_id=target_project_id and (p.user_id=auth.uid() or project.can_manage_project(target_project_id))),'[]'::jsonb)
  );
end;$$;
revoke all on function public.list_site_delivery_workspace(uuid) from public,anon;
grant execute on function public.list_site_delivery_workspace(uuid) to authenticated;

commit;