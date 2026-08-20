begin;

create or replace function public.start_qto_run(target_project_id uuid,input_payload jsonb)
returns uuid
language plpgsql security invoker
set search_path=public,cost,cde,project,audit,extensions,auth,pg_temp
as $$
declare m cde.models%rowtype; q cost.qto_runs%rowtype; org_id uuid; model_id_value uuid:=nullif(input_payload->>'model_id','')::uuid; rule_ref text:=btrim(input_payload->>'measurement_rule_set_ref'); input_hash_value text;
begin
  if auth.uid() is null or not project.can_manage_project(target_project_id) then raise exception 'project_manage_authority_required'; end if;
  select * into m from cde.models where id=model_id_value and project_id=target_project_id;
  if not found then raise exception 'model_not_found'; end if;
  if m.status not in ('approved','issued') then raise exception 'approved_model_required'; end if;
  if nullif(rule_ref,'') is null then raise exception 'measurement_rule_set_required'; end if;
  input_hash_value:=encode(extensions.digest(jsonb_build_object('project_id',target_project_id,'model_id',m.id,'model_checksum',m.checksum,'measurement_rule_set_ref',rule_ref,'classification_ref',nullif(btrim(input_payload->>'classification_ref'),''),'exclusions',coalesce(input_payload->'exclusions','[]'::jsonb),'tolerance',coalesce(input_payload->'tolerance','{}'::jsonb))::text,'sha256'),'hex');
  perform set_config('conceptspaces.cost_phase','qto_create',true);
  insert into cost.qto_runs(project_id,model_id,model_checksum,measurement_rule_set_ref,classification_ref,exclusions,tolerance,input_hash,status,created_by)
  values(target_project_id,m.id,m.checksum,rule_ref,nullif(btrim(input_payload->>'classification_ref'),''),coalesce(input_payload->'exclusions','[]'::jsonb),coalesce(input_payload->'tolerance','{}'::jsonb),input_hash_value,'queued',auth.uid()) returning * into q;
  select organisation_id into org_id from project.projects where id=target_project_id;
  perform audit.append_event(org_id,target_project_id,'cost.qto.started','qto_run',q.id,null,to_jsonb(q),input_hash_value,gen_random_uuid());
  return q.id;
end;$$;
revoke all on function public.start_qto_run(uuid,jsonb) from public,anon;
grant execute on function public.start_qto_run(uuid,jsonb) to authenticated;

create or replace function public.complete_qto_run(target_qto_run_id uuid,input_payload jsonb)
returns text
language plpgsql security invoker
set search_path=public,cost,cde,project,audit,extensions,auth,pg_temp
as $$
declare q cost.qto_runs%rowtype; m cde.models%rowtype; item jsonb; qi cost.quantity_items%rowtype; prior cost.quantity_items%rowtype; revision_value int; org_id uuid; output_hash_value text:=lower(coalesce(input_payload->>'output_hash','')); item_hash text; quantity_value numeric; item_code text;
begin
  select * into q from cost.qto_runs where id=target_qto_run_id for update;
  if not found or auth.uid() is null or not project.can_manage_project(q.project_id) then raise exception 'qto_manage_authority_required'; end if;
  if q.status not in ('queued','running') then raise exception 'qto_not_completable'; end if;
  select * into m from cde.models where id=q.model_id;
  if not found or m.checksum<>q.model_checksum then raise exception 'qto_source_model_stale'; end if;
  perform set_config('conceptspaces.cost_phase','qto_complete',true);
  if nullif(btrim(input_payload->>'error_code'),'') is not null then
    update cost.qto_runs set status='failed',error_code=btrim(input_payload->>'error_code'),updated_at=now() where id=q.id returning * into q;
  else
    if output_hash_value !~ '^[0-9a-f]{64}$' then raise exception 'qto_output_hash_required'; end if;
    if jsonb_typeof(input_payload->'quantities')<>'array' or jsonb_array_length(input_payload->'quantities')=0 then raise exception 'qto_quantities_required'; end if;
    for item in select value from jsonb_array_elements(input_payload->'quantities') loop
      item_code:=btrim(item->>'code'); quantity_value:=nullif(item->>'quantity','')::numeric;
      if nullif(item_code,'') is null or nullif(btrim(item->>'description'),'') is null or nullif(btrim(item->>'unit'),'') is null then raise exception 'qto_quantity_identity_required'; end if;
      if quantity_value is null or quantity_value<0 then raise exception 'qto_quantity_invalid'; end if;
      if nullif(btrim(item->>'measurement_rule_ref'),'') is null or nullif(btrim(item->>'formula'),'') is null then raise exception 'qto_measurement_provenance_required'; end if;
      if jsonb_typeof(coalesce(item->'source_object_refs','[]'::jsonb))<>'array' or jsonb_array_length(coalesce(item->'source_object_refs','[]'::jsonb))=0 then raise exception 'qto_source_object_required'; end if;
      if upper(coalesce(nullif(btrim(item->>'confidence'),''),'D')) not in ('A','B','C','D') then raise exception 'qto_confidence_invalid'; end if;
      select * into prior from cost.quantity_items where project_id=q.project_id and code::text=item_code order by revision desc limit 1;
      revision_value:=coalesce(prior.revision,0)+1;
      item_hash:=encode(extensions.digest(jsonb_build_object('qto_run_id',q.id,'model_checksum',q.model_checksum,'code',item_code,'revision',revision_value,'quantity',quantity_value,'unit',btrim(item->>'unit'),'source_object_refs',item->'source_object_refs','measurement_rule_ref',btrim(item->>'measurement_rule_ref'),'formula',btrim(item->>'formula'))::text,'sha256'),'hex');
      insert into cost.quantity_items(project_id,code,description,discipline,unit,quantity,source,source_reference,confidence,revision,qto_run_id,source_object_refs,measurement_rule_ref,formula,source_revision_hash,supersedes_quantity_item_id,quantity_hash)
      values(q.project_id,item_code,btrim(item->>'description'),coalesce(nullif(btrim(item->>'discipline'),''),'GEN'),btrim(item->>'unit'),quantity_value,'model',q.model_id::text,upper(coalesce(nullif(btrim(item->>'confidence'),''),'D')),revision_value,q.id,item->'source_object_refs',btrim(item->>'measurement_rule_ref'),btrim(item->>'formula'),q.model_checksum,prior.id,item_hash) returning * into qi;
    end loop;
    update cost.qto_runs set status='completed',output_hash=output_hash_value,error_code=null,updated_at=now() where id=q.id returning * into q;
  end if;
  select organisation_id into org_id from project.projects where id=q.project_id;
  perform audit.append_event(org_id,q.project_id,'cost.qto.'||q.status,'qto_run',q.id,null,to_jsonb(q),coalesce(q.output_hash,q.error_code),gen_random_uuid());
  return q.status;
end;$$;
revoke all on function public.complete_qto_run(uuid,jsonb) from public,anon;
grant execute on function public.complete_qto_run(uuid,jsonb) to authenticated;

create or replace function public.approve_qto_run(target_qto_run_id uuid,target_reason text default null)
returns text
language plpgsql security invoker
set search_path=public,cost,cde,project,audit,auth,pg_temp
as $$
declare q cost.qto_runs%rowtype; m cde.models%rowtype; org_id uuid;
begin
  select * into q from cost.qto_runs where id=target_qto_run_id for update;
  if not found or auth.uid() is null or not project.can_manage_project(q.project_id) then raise exception 'qto_manage_authority_required'; end if;
  if q.status<>'completed' or q.output_hash is null then raise exception 'completed_qto_required'; end if;
  select * into m from cde.models where id=q.model_id;
  if not found or m.checksum<>q.model_checksum or m.status not in ('approved','issued') then raise exception 'qto_source_model_stale'; end if;
  if not exists(select 1 from cost.quantity_items qi where qi.qto_run_id=q.id) then raise exception 'qto_quantities_required'; end if;
  perform set_config('conceptspaces.cost_phase','qto_approve',true);
  update cost.qto_runs set status='approved',approved_by=auth.uid(),approved_at=now(),updated_at=now() where id=q.id returning * into q;
  select organisation_id into org_id from project.projects where id=q.project_id;
  perform audit.append_event(org_id,q.project_id,'cost.qto.approved','qto_run',q.id,null,to_jsonb(q),target_reason,gen_random_uuid());
  return q.status;
end;$$;
revoke all on function public.approve_qto_run(uuid,text) from public,anon;
grant execute on function public.approve_qto_run(uuid,text) to authenticated;

create or replace function public.create_cost_plan(target_project_id uuid,input_payload jsonb)
returns uuid
language plpgsql security invoker
set search_path=public,cost,project,configuration,audit,auth,pg_temp
as $$
declare p cost.cost_plans%rowtype; q cost.qto_runs%rowtype; baseline cost.cost_plans%rowtype; version_value int; qto_id uuid:=nullif(input_payload->>'qto_run_id','')::uuid; org_id uuid; confidence_value text:=upper(coalesce(nullif(btrim(input_payload->>'confidence'),''),'C'));
begin
  if auth.uid() is null or not project.can_manage_project(target_project_id) then raise exception 'project_manage_authority_required'; end if;
  if confidence_value not in ('A','B','C','D') then raise exception 'cost_confidence_invalid'; end if;
  if qto_id is not null then
    select * into q from cost.qto_runs where id=qto_id and project_id=target_project_id;
    if not found or q.status<>'approved' then raise exception 'approved_qto_required'; end if;
  end if;
  select * into baseline from cost.cost_plans where project_id=target_project_id and status='approved' order by version desc limit 1;
  select coalesce(max(version),0)+1 into version_value from cost.cost_plans where project_id=target_project_id;
  perform set_config('conceptspaces.cost_phase','plan_create',true);
  insert into cost.cost_plans(project_id,version,stage,currency,contingencies,professional_fees,taxes,total,confidence,basis_date,status,created_by,qto_run_id,baseline_plan_id,configuration_hash)
  values(target_project_id,version_value,coalesce(nullif(btrim(input_payload->>'stage'),''),'cost_plan'),upper(coalesce(nullif(btrim(input_payload->>'currency'),''),'INR')),coalesce(nullif(input_payload->>'contingencies','')::numeric,0),coalesce(nullif(input_payload->>'professional_fees','')::numeric,0),coalesce(nullif(input_payload->>'taxes','')::numeric,0),0,confidence_value,coalesce(nullif(input_payload->>'basis_date','')::date,current_date),'draft',auth.uid(),qto_id,baseline.id,configuration.project_configuration_hash(target_project_id)) returning * into p;
  select organisation_id into org_id from project.projects where id=target_project_id;
  perform audit.append_event(org_id,target_project_id,'cost.plan.created','cost_plan',p.id,null,to_jsonb(p),p.configuration_hash,gen_random_uuid());
  return p.id;
end;$$;
revoke all on function public.create_cost_plan(uuid,jsonb) from public,anon;
grant execute on function public.create_cost_plan(uuid,jsonb) to authenticated;

create or replace function public.add_boq_line(target_cost_plan_id uuid,input_payload jsonb)
returns uuid
language plpgsql security invoker
set search_path=public,cost,project,audit,extensions,auth,pg_temp
as $$
declare p cost.cost_plans%rowtype; qi cost.quantity_items%rowtype; b cost.boq_lines%rowtype; org_id uuid; qi_id uuid:=nullif(input_payload->>'quantity_item_id','')::uuid; manual_value boolean:=coalesce((input_payload->>'manual_item')::boolean,false); quantity_value numeric; rate_value numeric:=coalesce(nullif(input_payload->>'rate','')::numeric,0); wastage_value numeric:=coalesce(nullif(input_payload->>'wastage_percent','')::numeric,0); tax_value numeric:=coalesce(nullif(input_payload->>'tax_amount','')::numeric,0); total_value numeric; source_hash_value text;
begin
  select * into p from cost.cost_plans where id=target_cost_plan_id for update;
  if not found or auth.uid() is null or not project.can_manage_project(p.project_id) then raise exception 'cost_plan_manage_authority_required'; end if;
  if p.status<>'draft' then raise exception 'cost_plan_not_editable'; end if;
  if qi_id is null and not manual_value then raise exception 'boq_quantity_source_required'; end if;
  if qi_id is not null then
    select * into qi from cost.quantity_items where id=qi_id and project_id=p.project_id;
    if not found then raise exception 'quantity_item_not_found'; end if;
    quantity_value:=coalesce(nullif(input_payload->>'quantity','')::numeric,qi.quantity);
    source_hash_value:=qi.quantity_hash;
  else
    quantity_value:=nullif(input_payload->>'quantity','')::numeric;
    if quantity_value is null or nullif(btrim(input_payload->>'notes'),'') is null then raise exception 'manual_boq_basis_required'; end if;
    source_hash_value:=encode(extensions.digest(jsonb_build_object('manual',true,'quantity',quantity_value,'unit',input_payload->>'unit','notes',input_payload->>'notes')::text,'sha256'),'hex');
  end if;
  if quantity_value<0 or rate_value<0 or wastage_value<0 then raise exception 'boq_numeric_value_invalid'; end if;
  if nullif(btrim(input_payload->>'rate_source'),'') is null or nullif(input_payload->>'rate_date','') is null then raise exception 'rate_provenance_required'; end if;
  total_value:=round((quantity_value*rate_value*(1+wastage_value/100))+tax_value,2);
  perform set_config('conceptspaces.cost_phase','boq_edit',true);
  insert into cost.boq_lines(cost_plan_id,quantity_item_id,code,description,unit,quantity,rate,currency,material_amount,labour_amount,equipment_amount,wastage_percent,tax_amount,total,confidence,specification_ref,rate_source,rate_date,package_category,revision,notes,manual_item,source_hash)
  values(p.id,qi_id,btrim(input_payload->>'code'),btrim(input_payload->>'description'),coalesce(nullif(btrim(input_payload->>'unit'),''),qi.unit),quantity_value,rate_value,upper(coalesce(nullif(btrim(input_payload->>'currency'),''),p.currency)),coalesce(nullif(input_payload->>'material_amount','')::numeric,0),coalesce(nullif(input_payload->>'labour_amount','')::numeric,0),coalesce(nullif(input_payload->>'equipment_amount','')::numeric,0),wastage_value,tax_value,total_value,upper(coalesce(nullif(btrim(input_payload->>'confidence'),''),coalesce(qi.confidence,p.confidence))),nullif(btrim(input_payload->>'specification_ref'),''),btrim(input_payload->>'rate_source'),(input_payload->>'rate_date')::date,nullif(btrim(input_payload->>'package_category'),''),coalesce(nullif(btrim(input_payload->>'revision'),''),'P01'),nullif(btrim(input_payload->>'notes'),''),manual_value,source_hash_value) returning * into b;
  select organisation_id into org_id from project.projects where id=p.project_id;
  perform audit.append_event(org_id,p.project_id,'cost.boq.line_added','boq_line',b.id,null,to_jsonb(b),source_hash_value,gen_random_uuid());
  return b.id;
end;$$;
revoke all on function public.add_boq_line(uuid,jsonb) from public,anon;
grant execute on function public.add_boq_line(uuid,jsonb) to authenticated;

create or replace function public.transition_cost_plan(target_cost_plan_id uuid,target_status text,target_reason text default null)
returns text
language plpgsql security invoker
set search_path=public,cost,project,configuration,audit,extensions,auth,pg_temp
as $$
declare p cost.cost_plans%rowtype; before_state jsonb; status_value text:=lower(btrim(target_status)); org_id uuid; line_total numeric; lines_payload jsonb; approved_hash_value text;
begin
  select * into p from cost.cost_plans where id=target_cost_plan_id for update;
  if not found or auth.uid() is null or not project.can_manage_project(p.project_id) then raise exception 'cost_plan_manage_authority_required'; end if;
  if status_value not in ('draft','for_review','approved','superseded') then raise exception 'unsupported_cost_plan_status'; end if;
  if p.status='superseded' then raise exception 'terminal_cost_plan'; end if;
  if status_value='for_review' and p.status<>'draft' then raise exception 'invalid_cost_plan_transition'; end if;
  if status_value='draft' and p.status<>'for_review' then raise exception 'invalid_cost_plan_transition'; end if;
  if status_value='approved' and p.status<>'for_review' then raise exception 'invalid_cost_plan_transition'; end if;
  if status_value='superseded' and p.status<>'approved' then raise exception 'invalid_cost_plan_transition'; end if;
  before_state:=to_jsonb(p);
  if status_value='approved' then
    if p.configuration_hash is distinct from configuration.project_configuration_hash(p.project_id) then raise exception 'project_configuration_changed_recost_required'; end if;
    if p.qto_run_id is not null and not exists(select 1 from cost.qto_runs q where q.id=p.qto_run_id and q.status='approved') then raise exception 'approved_qto_required'; end if;
    if not exists(select 1 from cost.boq_lines b where b.cost_plan_id=p.id) then raise exception 'boq_lines_required'; end if;
    if exists(select 1 from cost.boq_lines b where b.cost_plan_id=p.id and ((b.quantity_item_id is null and not b.manual_item) or b.rate_source is null or b.rate_date is null or b.source_hash is null)) then raise exception 'boq_traceability_incomplete'; end if;
    select coalesce(sum(total),0),coalesce(jsonb_agg(to_jsonb(b) order by b.code,b.id),'[]'::jsonb) into line_total,lines_payload from cost.boq_lines b where b.cost_plan_id=p.id;
    approved_hash_value:=encode(extensions.digest(jsonb_build_object('plan_id',p.id,'version',p.version,'configuration_hash',p.configuration_hash,'lines',lines_payload,'contingencies',p.contingencies,'professional_fees',p.professional_fees,'taxes',p.taxes)::text,'sha256'),'hex');
    perform set_config('conceptspaces.cost_phase','plan_approve',true);
    update cost.cost_plans set status='superseded' where project_id=p.project_id and status='approved' and id<>p.id;
    update cost.cost_plans set status='approved',total=line_total+p.contingencies+p.professional_fees+p.taxes,approved_by=auth.uid(),approved_at=now(),approved_hash=approved_hash_value where id=p.id returning * into p;
  else
    perform set_config('conceptspaces.cost_phase','plan_transition',true);
    update cost.cost_plans set status=status_value where id=p.id returning * into p;
  end if;
  select organisation_id into org_id from project.projects where id=p.project_id;
  perform audit.append_event(org_id,p.project_id,'cost.plan.'||status_value,'cost_plan',p.id,before_state,to_jsonb(p),coalesce(target_reason,p.approved_hash),gen_random_uuid());
  return p.status;
end;$$;
revoke all on function public.transition_cost_plan(uuid,text,text) from public,anon;
grant execute on function public.transition_cost_plan(uuid,text,text) to authenticated;

create or replace function public.propose_value_engineering_option(target_project_id uuid,input_payload jsonb)
returns uuid
language plpgsql security invoker
set search_path=public,feasibility,cost,project,audit,auth,pg_temp
as $$
declare v feasibility.value_engineering_options%rowtype; org_id uuid; source_line uuid:=nullif(input_payload->>'source_boq_line_id','')::uuid; quality_value text:=lower(coalesce(nullif(btrim(input_payload->>'quality_impact'),''),'neutral')); carbon_value text:=lower(coalesce(nullif(btrim(input_payload->>'carbon_impact'),''),'neutral'));
begin
  if auth.uid() is null or not project.can_manage_project(target_project_id) then raise exception 'project_manage_authority_required'; end if;
  if source_line is not null and not exists(select 1 from cost.boq_lines b join cost.cost_plans p on p.id=b.cost_plan_id where b.id=source_line and p.project_id=target_project_id) then raise exception 've_source_boq_line_invalid'; end if;
  perform set_config('conceptspaces.cost_phase','ve_create',true);
  insert into feasibility.value_engineering_options(project_id,scenario_id,discipline,proposal,reason,capex_impact,opex_impact,programme_impact_days,quality_impact,carbon_impact,requirement_impact_refs,decision_state,source_boq_line_id,alternative_ref,lifecycle_impact,performance_impact,lead_time_impact_days,approved_deviation_ref)
  values(target_project_id,nullif(input_payload->>'scenario_id','')::uuid,nullif(btrim(input_payload->>'discipline'),''),btrim(input_payload->>'proposal'),btrim(input_payload->>'reason'),coalesce(nullif(input_payload->>'capex_impact','')::numeric,0),nullif(input_payload->>'opex_impact','')::numeric,nullif(input_payload->>'programme_impact_days','')::int,quality_value,carbon_value,coalesce(input_payload->'requirement_impact_refs','[]'::jsonb),'proposed',source_line,nullif(btrim(input_payload->>'alternative_ref'),''),coalesce(input_payload->'lifecycle_impact','{}'::jsonb),coalesce(input_payload->'performance_impact','{}'::jsonb),nullif(input_payload->>'lead_time_impact_days','')::int,nullif(btrim(input_payload->>'approved_deviation_ref'),'')) returning * into v;
  select organisation_id into org_id from project.projects where id=target_project_id;
  perform audit.append_event(org_id,target_project_id,'cost.ve.proposed','value_engineering_option',v.id,null,to_jsonb(v),null,gen_random_uuid());
  return v.id;
end;$$;
revoke all on function public.propose_value_engineering_option(uuid,jsonb) from public,anon;
grant execute on function public.propose_value_engineering_option(uuid,jsonb) to authenticated;

create or replace function public.decide_value_engineering_option(target_option_id uuid,target_decision text,target_reason text)
returns text
language plpgsql security invoker
set search_path=public,feasibility,project,audit,extensions,auth,pg_temp
as $$
declare v feasibility.value_engineering_options%rowtype; before_state jsonb; decision_value text:=lower(btrim(target_decision)); org_id uuid; hash_value text;
begin
  select * into v from feasibility.value_engineering_options where id=target_option_id for update;
  if not found or auth.uid() is null or not project.can_manage_project(v.project_id) then raise exception 've_manage_authority_required'; end if;
  if decision_value not in ('review','accepted','rejected') then raise exception 'unsupported_ve_decision'; end if;
  if v.decision_state in ('accepted','rejected') then raise exception 'terminal_ve_decision'; end if;
  if decision_value='accepted' and lower(coalesce(v.performance_impact->>'mandatory_performance','unchanged')) in ('degraded','reduced','fail') and nullif(v.approved_deviation_ref,'') is null then raise exception 've_mandatory_performance_deviation_required'; end if;
  if decision_value in ('accepted','rejected') and nullif(btrim(target_reason),'') is null then raise exception 've_decision_reason_required'; end if;
  hash_value:=encode(extensions.digest(jsonb_build_object('option_id',v.id,'proposal',v.proposal,'capex',v.capex_impact,'opex',v.opex_impact,'programme',v.programme_impact_days,'quality',v.quality_impact,'carbon',v.carbon_impact,'lifecycle',v.lifecycle_impact,'performance',v.performance_impact,'lead_time',v.lead_time_impact_days,'decision',decision_value)::text,'sha256'),'hex');
  before_state:=to_jsonb(v); perform set_config('conceptspaces.cost_phase','ve_decide',true);
  update feasibility.value_engineering_options set decision_state=decision_value,decided_by=case when decision_value in ('accepted','rejected') then auth.uid() else decided_by end,decided_at=case when decision_value in ('accepted','rejected') then now() else decided_at end,decision_hash=case when decision_value in ('accepted','rejected') then hash_value else decision_hash end,updated_at=now() where id=v.id returning * into v;
  select organisation_id into org_id from project.projects where id=v.project_id;
  perform audit.append_event(org_id,v.project_id,'cost.ve.'||decision_value,'value_engineering_option',v.id,before_state,to_jsonb(v),target_reason,gen_random_uuid());
  return v.decision_state;
end;$$;
revoke all on function public.decide_value_engineering_option(uuid,text,text) from public,anon;
grant execute on function public.decide_value_engineering_option(uuid,text,text) to authenticated;

create or replace function public.list_cost_workspace(target_project_id uuid)
returns jsonb
language plpgsql stable security invoker
set search_path=public,cost,feasibility,cde,project,configuration,pg_temp
as $$
begin
  if auth.uid() is null or not project.can_access_project(target_project_id) then raise exception 'project_access_required'; end if;
  return jsonb_build_object(
    'configuration_hash',configuration.project_configuration_hash(target_project_id),
    'models',coalesce((select jsonb_agg(to_jsonb(m) order by m.updated_at desc) from cde.models m where m.project_id=target_project_id and m.status in ('approved','issued')),'[]'::jsonb),
    'qto_runs',coalesce((select jsonb_agg(to_jsonb(q) order by q.created_at desc) from cost.qto_runs q where q.project_id=target_project_id),'[]'::jsonb),
    'quantities',coalesce((select jsonb_agg(to_jsonb(qi) order by qi.code,qi.revision desc) from cost.quantity_items qi where qi.project_id=target_project_id),'[]'::jsonb),
    'cost_plans',coalesce((select jsonb_agg(to_jsonb(p) order by p.version desc) from cost.cost_plans p where p.project_id=target_project_id),'[]'::jsonb),
    'boq_lines',coalesce((select jsonb_agg(to_jsonb(b) order by p.version desc,b.code) from cost.boq_lines b join cost.cost_plans p on p.id=b.cost_plan_id where p.project_id=target_project_id),'[]'::jsonb),
    've_options',coalesce((select jsonb_agg(to_jsonb(v) order by v.created_at desc) from feasibility.value_engineering_options v where v.project_id=target_project_id),'[]'::jsonb)
  );
end;$$;
revoke all on function public.list_cost_workspace(uuid) from public,anon;
grant execute on function public.list_cost_workspace(uuid) to authenticated;

commit;