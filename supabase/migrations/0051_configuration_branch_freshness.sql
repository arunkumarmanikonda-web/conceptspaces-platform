begin;

alter table public.change_impacts add column if not exists analyzed_branch_head_hash text;
alter table public.project_change_requests add column if not exists applied_commit_hash text;

create index if not exists change_impacts_branch_head_idx on public.change_impacts(change_request_id,analyzed_branch_head_hash) where analysis_state='final';
create index if not exists project_change_requests_applied_commit_idx on public.project_change_requests(branch_id,applied_commit_hash) where applied_commit_hash is not null;

create or replace function public.analyze_project_change(target_change_request_id uuid,input_payload jsonb default '{}'::jsonb)
returns uuid
language plpgsql security invoker
set search_path=public,configuration,project,cde,engineering,regula,cost,operations,governance,coordination,audit,extensions,auth,pg_temp
as $$
declare
  req public.project_change_requests%rowtype; impact public.change_impacts%rowtype; baseline text; branch_head text; version_value int; disciplines text[]; org_id uuid;
  requirements_json jsonb; rules_json jsonb; documents_json jsonb; models_json jsonb; boq_json jsonb; contracts_json jsonb; coordination_json jsonb; releases_json jsonb; engineering_json jsonb; tasks_json jsonb; evidence_json jsonb; payload jsonb;
  analysis_hash_value text; cost_delta numeric:=nullif(input_payload->>'estimated_cost_delta','')::numeric; schedule_delta int:=nullif(input_payload->>'estimated_schedule_delta_days','')::int; reversal_cost numeric:=nullif(input_payload->>'decision_reversal_cost','')::numeric;
  confidence_value text:=upper(coalesce(nullif(btrim(input_payload->>'confidence'),''),'C')); requested_criticality text:=upper(coalesce(nullif(btrim(input_payload->>'criticality'),''),'C2')); criticality_value text;
begin
  select * into req from public.project_change_requests where id=target_change_request_id for update;
  if not found then raise exception 'change_request_not_found'; end if;
  if auth.uid() is null or not project.can_access_project(req.project_id) then raise exception 'project_access_required'; end if;
  if req.status in ('applied','cancelled') then raise exception 'terminal_change_request_state'; end if;
  if confidence_value not in ('A','B','C','D') then raise exception 'unsupported_confidence'; end if;
  if requested_criticality not in ('C0','C1','C2','C3','C4') then raise exception 'unsupported_criticality'; end if;
  select array_agg(lower(value)) into disciplines from jsonb_array_elements_text(req.proposed_disciplines);
  if disciplines is null or cardinality(disciplines)=0 then raise exception 'affected_disciplines_required'; end if;
  baseline:=configuration.project_configuration_hash(req.project_id);
  select b.head_commit_hash into branch_head from public.project_branches b where b.id=req.branch_id and b.project_id=req.project_id and b.status='active';
  if branch_head is null then raise exception 'active_branch_required'; end if;
  select coalesce(max(ci.analysis_version),0)+1 into version_value from public.change_impacts ci where ci.change_request_id=req.id;

  select coalesce(jsonb_agg(jsonb_build_object('id',r.id,'code',r.code::text,'statement',r.statement,'category',r.category,'status',r.status,'criticality',r.criticality) order by r.code,r.id),'[]'::jsonb)
    into requirements_json from project.requirements r where r.project_id=req.project_id and r.status<>'rejected';
  select coalesce(jsonb_agg(jsonb_build_object('id',f.id,'rule_id',f.rule_id,'status',f.status,'disposition',f.disposition,'explanation',f.explanation) order by f.checked_at desc nulls last,f.id),'[]'::jsonb)
    into rules_json from regula.compliance_findings f where f.project_id=req.project_id and f.evaluation_run_id=(select er.id from regula.evaluation_runs er where er.project_id=req.project_id order by er.created_at desc limit 1);
  select coalesce(jsonb_agg(jsonb_build_object('id',d.id,'number',d.document_number::text,'title',d.title,'discipline',d.discipline,'revision',d.revision,'checksum',v.checksum,'status',d.status) order by d.document_number,d.id),'[]'::jsonb)
    into documents_json from cde.documents d left join cde.file_versions v on v.id=d.current_version_id where d.project_id=req.project_id and lower(d.discipline)=any(disciplines);
  select coalesce(jsonb_agg(jsonb_build_object('id',m.id,'name',m.model_name,'discipline',m.discipline,'format',m.format,'checksum',m.checksum,'status',m.status) order by m.model_name,m.id),'[]'::jsonb)
    into models_json from cde.models m where m.project_id=req.project_id and lower(m.discipline)=any(disciplines);
  select coalesce(jsonb_agg(jsonb_build_object('id',b.id,'code',b.code::text,'description',b.description,'discipline',q.discipline,'total',b.total,'currency',b.currency) order by b.code,b.id),'[]'::jsonb)
    into boq_json from cost.boq_lines b join cost.cost_plans cp on cp.id=b.cost_plan_id left join cost.quantity_items q on q.id=b.quantity_item_id where cp.project_id=req.project_id and (q.discipline is null or lower(q.discipline)=any(disciplines));
  select coalesce(jsonb_agg(jsonb_build_object('id',c.id,'version',c.version,'status',c.status,'effective_at',c.effective_at,'expires_at',c.expires_at) order by c.version,c.id),'[]'::jsonb)
    into contracts_json from public.contracts c where c.project_id=req.project_id and c.status not in ('completed','terminated');
  select coalesce(jsonb_agg(jsonb_build_object('id',cm.id,'issue_id',cm.issue_id,'source_discipline',cm.source_discipline,'target_discipline',cm.target_discipline,'subject',cm.subject,'state',cm.state,'criticality',cm.criticality,'hash',cm.coordination_hash,'resources_current',engineering.coordination_item_resources_current(cm.id)) order by cm.updated_at desc,cm.id),'[]'::jsonb)
    into coordination_json from engineering.coordination_matrix cm where cm.project_id=req.project_id and (lower(cm.source_discipline)=any(disciplines) or lower(cm.target_discipline)=any(disciplines));
  select coalesce(jsonb_agg(jsonb_build_object('id',s.id,'package_reference',s.package_reference,'package_type',s.package_type,'state',s.state,'content_hash',s.content_hash,'unresolved_critical_defects',s.unresolved_critical_defects) order by s.updated_at desc,s.id),'[]'::jsonb)
    into releases_json from governance.release_safety_cases s where s.project_id=req.project_id and s.state<>'issued';
  select coalesce(jsonb_agg(jsonb_build_object('id',cr.id,'discipline',cr.discipline,'calculation_type',cr.calculation_type,'status',cr.status,'engine_version',cr.engine_version,'output_hash',cr.output_hash) order by cr.created_at desc,cr.id),'[]'::jsonb)
    into engineering_json from engineering.calculation_runs cr where cr.project_id=req.project_id and lower(cr.discipline)=any(disciplines);
  select coalesce(jsonb_agg(jsonb_build_object('id',t.id,'title',t.title,'state',t.state,'priority',t.priority,'due_at',t.due_at,'assignee_role_code',t.assignee_role_code) order by t.due_at nulls last,t.id),'[]'::jsonb)
    into tasks_json from operations.tasks t where t.project_id=req.project_id and t.state not in ('approved','cancelled');

  if jsonb_array_length(releases_json)>0 or jsonb_array_length(coordination_json)>0 then criticality_value:=case when requested_criticality='C4' then 'C4' else 'C3' end;
  else criticality_value:=requested_criticality; end if;
  evidence_json:=jsonb_build_array(jsonb_build_object('type','configuration_baseline','hash',baseline),jsonb_build_object('type','branch_head','hash',branch_head));
  payload:=jsonb_build_object('change_request_id',req.id,'version',version_value,'baseline_hash',baseline,'branch_head',branch_head,'source_object_refs',req.source_object_refs,'disciplines',req.proposed_disciplines,'requirements',requirements_json,'rules',rules_json,'documents',documents_json,'models',models_json,'boq',boq_json,'contracts',contracts_json,'coordination',coordination_json,'releases',releases_json,'engineering',engineering_json,'tasks',tasks_json,'estimated_cost_delta',cost_delta,'estimated_schedule_delta_days',schedule_delta,'decision_reversal_cost',reversal_cost,'criticality',criticality_value,'confidence',confidence_value);
  analysis_hash_value:=encode(extensions.digest(payload::text,'sha256'),'hex');

  perform set_config('conceptspaces.configuration_phase','analyze',true);
  update public.change_impacts set analysis_state='superseded' where change_request_id=req.id and analysis_state='final';
  insert into public.change_impacts(project_id,change_ref,source_object_refs,affected_requirements,affected_rules,affected_disciplines,affected_documents,affected_model_objects,affected_boq_lines,affected_contracts,estimated_cost_delta,estimated_schedule_delta_days,decision_reversal_cost,criticality,confidence,analysis_evidence_refs,change_request_id,analysis_version,analysis_hash,baseline_hash,analyzed_branch_head_hash,affected_coordination,affected_releases,affected_engineering_runs,affected_programme_tasks,analyzed_by,analysis_state)
    values(req.project_id,req.change_ref,req.source_object_refs,requirements_json,rules_json,req.proposed_disciplines,documents_json,models_json,boq_json,contracts_json,cost_delta,schedule_delta,reversal_cost,criticality_value,confidence_value,evidence_json,req.id,version_value,analysis_hash_value,baseline,branch_head,coordination_json,releases_json,engineering_json,tasks_json,auth.uid(),'final') returning * into impact;
  update public.project_change_requests set latest_impact_id=impact.id,status='analyzed',approval_request_id=null,approved_by=null,approved_at=null,applied_commit_hash=null,updated_at=now() where id=req.id returning * into req;
  select organisation_id into org_id from project.projects where id=req.project_id;
  perform audit.append_event(org_id,req.project_id,'configuration.change.analyzed','change_impact',impact.id,null,to_jsonb(impact),analysis_hash_value,gen_random_uuid());
  return impact.id;
end;$$;
revoke all on function public.analyze_project_change(uuid,jsonb) from public,anon;
grant execute on function public.analyze_project_change(uuid,jsonb) to authenticated;

create or replace function configuration.assert_change_analysis_current(target_change_request_id uuid)
returns boolean
language plpgsql stable security invoker
set search_path=configuration,public,project,pg_temp
as $$
declare req public.project_change_requests%rowtype; impact public.change_impacts%rowtype; current_branch_head text;
begin
  select * into req from public.project_change_requests where id=target_change_request_id;
  if not found or not project.can_access_project(req.project_id) then return false; end if;
  select * into impact from public.change_impacts where id=req.latest_impact_id and analysis_state='final';
  if not found or nullif(impact.analysis_hash,'') is null or nullif(impact.analyzed_branch_head_hash,'') is null then return false; end if;
  select head_commit_hash into current_branch_head from public.project_branches where id=req.branch_id and project_id=req.project_id and status='active';
  return current_branch_head is not null
     and current_branch_head=impact.analyzed_branch_head_hash
     and configuration.project_configuration_hash(req.project_id)=impact.baseline_hash;
end;$$;
revoke all on function configuration.assert_change_analysis_current(uuid) from public,anon;
grant execute on function configuration.assert_change_analysis_current(uuid) to authenticated;

create or replace function public.request_project_change_approval(target_change_request_id uuid,target_role_required text default 'lead_architect')
returns uuid
language plpgsql security invoker
set search_path=public,configuration,project,audit,auth,pg_temp
as $$
declare req public.project_change_requests%rowtype; impact public.change_impacts%rowtype; approval_id uuid; org_id uuid;
begin
  select * into req from public.project_change_requests where id=target_change_request_id for update;
  if not found or auth.uid() is null or not project.can_access_project(req.project_id) then raise exception 'change_request_access_required'; end if;
  if req.status<>'analyzed' or req.latest_impact_id is null then raise exception 'final_change_analysis_required'; end if;
  select * into impact from public.change_impacts where id=req.latest_impact_id and analysis_state='final';
  if not found or nullif(impact.analysis_hash,'') is null then raise exception 'final_change_analysis_required'; end if;
  if not configuration.assert_change_analysis_current(req.id) then raise exception 'project_or_branch_changed_reanalysis_required'; end if;
  approval_id:=public.request_governed_approval(jsonb_build_object('project_id',req.project_id,'resource_type','change','resource_id',req.id,'role_required',lower(btrim(target_role_required)),'criticality',impact.criticality,'comments','Project change '||req.change_ref||' exact impact analysis hash '||impact.analysis_hash));
  perform set_config('conceptspaces.configuration_phase','request_approval',true);
  update public.project_change_requests set status='approval_pending',approval_request_id=approval_id,updated_at=now() where id=req.id returning * into req;
  select organisation_id into org_id from project.projects where id=req.project_id;
  perform audit.append_event(org_id,req.project_id,'configuration.change.approval_requested','project_change_request',req.id,null,to_jsonb(req),impact.analysis_hash,gen_random_uuid());
  return approval_id;
end;$$;
revoke all on function public.request_project_change_approval(uuid,text) from public,anon;
grant execute on function public.request_project_change_approval(uuid,text) to authenticated;

create or replace function public.apply_project_change(target_change_request_id uuid,target_message text default null)
returns text
language plpgsql security invoker
set search_path=public,configuration,project,audit,extensions,auth,pg_temp
as $$
declare req public.project_change_requests%rowtype; impact public.change_impacts%rowtype; b public.project_branches%rowtype; before_branch jsonb; before_req jsonb; commit_hash text; org_id uuid;
begin
  select * into req from public.project_change_requests where id=target_change_request_id for update;
  if not found or auth.uid() is null or not project.can_access_project(req.project_id) then raise exception 'change_request_access_required'; end if;
  if req.status<>'approved' or req.latest_impact_id is null then raise exception 'approved_change_required'; end if;
  select * into impact from public.change_impacts where id=req.latest_impact_id and analysis_state='final'; if not found then raise exception 'final_change_analysis_required'; end if;
  if not configuration.assert_change_analysis_current(req.id) then raise exception 'project_or_branch_changed_reanalysis_required'; end if;
  select * into b from public.project_branches where id=req.branch_id and project_id=req.project_id for update; if not found or b.status<>'active' then raise exception 'active_branch_required'; end if;
  commit_hash:=encode(extensions.digest(jsonb_build_object('project_id',req.project_id,'branch_id',b.id,'parent',b.head_commit_hash,'change_ref',req.change_ref,'analysis_hash',impact.analysis_hash,'source_object_refs',req.source_object_refs)::text,'sha256'),'hex');
  before_branch:=to_jsonb(b); before_req:=to_jsonb(req);
  perform set_config('conceptspaces.configuration_phase','commit',true);
  insert into public.project_commits(project_id,branch_id,parent_commit_hashes,content_hash,message,changed_object_refs,author_type,author_ref)
    values(req.project_id,b.id,jsonb_build_array(b.head_commit_hash),commit_hash,coalesce(nullif(btrim(target_message),''),req.change_ref||' · '||req.title),req.source_object_refs,'human',auth.uid()::text);
  update public.project_branches set head_commit_hash=commit_hash where id=b.id returning * into b;
  perform set_config('conceptspaces.configuration_phase','apply',true);
  update public.project_change_requests set status='applied',applied_by=auth.uid(),applied_at=now(),applied_commit_hash=commit_hash,updated_at=now() where id=req.id returning * into req;
  select organisation_id into org_id from project.projects where id=req.project_id;
  perform audit.append_event(org_id,req.project_id,'configuration.change.applied','project_change_request',req.id,before_req,to_jsonb(req),commit_hash,gen_random_uuid());
  perform audit.append_event(org_id,req.project_id,'configuration.branch.commit','project_branch',b.id,before_branch,to_jsonb(b),commit_hash,gen_random_uuid());
  return commit_hash;
end;$$;
revoke all on function public.apply_project_change(uuid,text) from public,anon;
grant execute on function public.apply_project_change(uuid,text) to authenticated;

create or replace function public.merge_project_configuration_branch(source_branch_id uuid,target_branch_id uuid,target_change_request_id uuid,target_reason text)
returns text
language plpgsql security invoker
set search_path=public,project,audit,extensions,auth,pg_temp
as $$
declare source_branch public.project_branches%rowtype; target_branch public.project_branches%rowtype; req public.project_change_requests%rowtype; impact public.change_impacts%rowtype; before_source jsonb; before_target jsonb; merge_hash text; org_id uuid;
begin
  if source_branch_id=target_branch_id then raise exception 'source_and_target_branch_must_differ'; end if;
  select * into source_branch from public.project_branches where id=source_branch_id for update; if not found then raise exception 'source_branch_not_found'; end if;
  select * into target_branch from public.project_branches where id=target_branch_id for update; if not found then raise exception 'target_branch_not_found'; end if;
  if source_branch.project_id is distinct from target_branch.project_id then raise exception 'same_project_branches_required'; end if;
  if auth.uid() is null or not project.can_access_project(source_branch.project_id) then raise exception 'project_access_required'; end if;
  if source_branch.status<>'active' or target_branch.status<>'active' then raise exception 'active_source_and_target_required'; end if;
  if nullif(btrim(target_reason),'') is null then raise exception 'merge_reason_required'; end if;
  select * into req from public.project_change_requests where id=target_change_request_id and project_id=source_branch.project_id and branch_id=source_branch.id;
  if not found or req.status<>'applied' or req.latest_impact_id is null or nullif(req.applied_commit_hash,'') is null then raise exception 'applied_source_branch_change_required'; end if;
  if source_branch.head_commit_hash<>req.applied_commit_hash then raise exception 'source_branch_advanced_after_approved_change_new_change_control_required'; end if;
  select * into impact from public.change_impacts where id=req.latest_impact_id and analysis_state='final'; if not found then raise exception 'final_impact_required'; end if;
  merge_hash:=encode(extensions.digest(jsonb_build_object('project_id',source_branch.project_id,'target_parent',target_branch.head_commit_hash,'source_head',source_branch.head_commit_hash,'change_ref',req.change_ref,'analysis_hash',impact.analysis_hash,'reason',btrim(target_reason))::text,'sha256'),'hex');
  before_source:=to_jsonb(source_branch); before_target:=to_jsonb(target_branch);
  perform set_config('conceptspaces.configuration_phase','merge',true);
  insert into public.project_commits(project_id,branch_id,parent_commit_hashes,content_hash,message,changed_object_refs,author_type,author_ref)
    values(source_branch.project_id,target_branch.id,jsonb_build_array(target_branch.head_commit_hash,source_branch.head_commit_hash),merge_hash,'Merge '||source_branch.name||' → '||target_branch.name||': '||btrim(target_reason),req.source_object_refs,'human',auth.uid()::text);
  update public.project_branches set head_commit_hash=merge_hash where id=target_branch.id returning * into target_branch;
  update public.project_branches set status='merged' where id=source_branch.id returning * into source_branch;
  select organisation_id into org_id from project.projects where id=source_branch.project_id;
  perform audit.append_event(org_id,source_branch.project_id,'configuration.branch.merged','project_branch',source_branch.id,before_source,to_jsonb(source_branch),merge_hash,gen_random_uuid());
  perform audit.append_event(org_id,target_branch.project_id,'configuration.branch.merge_commit','project_branch',target_branch.id,before_target,to_jsonb(target_branch),merge_hash,gen_random_uuid());
  return merge_hash;
end;$$;
revoke all on function public.merge_project_configuration_branch(uuid,uuid,uuid,text) from public,anon;
grant execute on function public.merge_project_configuration_branch(uuid,uuid,uuid,text) to authenticated;

commit;
