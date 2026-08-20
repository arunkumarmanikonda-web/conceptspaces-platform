begin;

create schema if not exists configuration;

create table if not exists public.project_change_requests (
  id uuid primary key default gen_random_uuid(),
  project_id uuid not null references project.projects(id) on delete cascade,
  branch_id uuid not null references public.project_branches(id) on delete restrict,
  change_ref text not null,
  title text not null,
  description text not null,
  source_object_refs jsonb not null default '[]'::jsonb,
  proposed_disciplines jsonb not null default '[]'::jsonb,
  status text not null default 'draft' check (status in ('draft','analyzed','approval_pending','approved','rejected','applied','cancelled')),
  latest_impact_id uuid,
  approval_request_id uuid references coordination.approval_requests(id) on delete set null,
  requested_by uuid not null references auth.users(id),
  approved_by uuid references auth.users(id),
  approved_at timestamptz,
  applied_by uuid references auth.users(id),
  applied_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique(project_id,change_ref)
);

alter table public.change_impacts add column if not exists change_request_id uuid references public.project_change_requests(id) on delete cascade;
alter table public.change_impacts add column if not exists analysis_version integer not null default 1;
alter table public.change_impacts add column if not exists analysis_hash text;
alter table public.change_impacts add column if not exists baseline_hash text;
alter table public.change_impacts add column if not exists affected_coordination jsonb not null default '[]'::jsonb;
alter table public.change_impacts add column if not exists affected_releases jsonb not null default '[]'::jsonb;
alter table public.change_impacts add column if not exists affected_engineering_runs jsonb not null default '[]'::jsonb;
alter table public.change_impacts add column if not exists affected_programme_tasks jsonb not null default '[]'::jsonb;
alter table public.change_impacts add column if not exists analyzed_by uuid references auth.users(id);
alter table public.change_impacts add column if not exists analysis_state text not null default 'final' check (analysis_state in ('final','superseded'));

alter table public.project_change_requests drop constraint if exists project_change_requests_latest_impact_fk;
alter table public.project_change_requests add constraint project_change_requests_latest_impact_fk
  foreign key (latest_impact_id) references public.change_impacts(id) on delete set null deferrable initially deferred;

create unique index if not exists project_change_requests_latest_impact_uidx on public.project_change_requests(latest_impact_id) where latest_impact_id is not null;
create index if not exists project_change_requests_project_status_idx on public.project_change_requests(project_id,status,updated_at desc);
create index if not exists project_change_requests_branch_idx on public.project_change_requests(branch_id,updated_at desc);
create index if not exists change_impacts_request_idx on public.change_impacts(change_request_id,analysis_version desc);
create index if not exists project_commits_branch_time_idx on public.project_commits(branch_id,created_at desc);

alter table public.project_change_requests enable row level security;

drop policy if exists project_change_requests_read on public.project_change_requests;
create policy project_change_requests_read on public.project_change_requests for select to authenticated using (project.can_access_project(project_id));
drop policy if exists project_change_requests_governed_insert on public.project_change_requests;
create policy project_change_requests_governed_insert on public.project_change_requests for insert to authenticated with check (
  project.can_access_project(project_id) and requested_by=(select auth.uid())
  and (select current_setting('conceptspaces.configuration_phase',true)) in ('propose')
);
drop policy if exists project_change_requests_governed_update on public.project_change_requests;
create policy project_change_requests_governed_update on public.project_change_requests for update to authenticated using (project.can_access_project(project_id)) with check (
  project.can_access_project(project_id)
  and (select current_setting('conceptspaces.configuration_phase',true)) in ('analyze','request_approval','sync_approval','apply','cancel')
);

drop policy if exists project_branches_governed_insert on public.project_branches;
create policy project_branches_governed_insert on public.project_branches for insert to authenticated with check (
  project.can_access_project(project_id) and created_by=(select auth.uid())
  and (select current_setting('conceptspaces.configuration_phase',true)) in ('bootstrap','branch')
);
drop policy if exists project_branches_governed_update on public.project_branches;
create policy project_branches_governed_update on public.project_branches for update to authenticated using (project.can_access_project(project_id)) with check (
  project.can_access_project(project_id)
  and (select current_setting('conceptspaces.configuration_phase',true)) in ('commit','merge','branch_state')
);
drop policy if exists project_commits_governed_insert on public.project_commits;
create policy project_commits_governed_insert on public.project_commits for insert to authenticated with check (
  project.can_access_project(project_id)
  and (select current_setting('conceptspaces.configuration_phase',true)) in ('bootstrap','commit','merge')
);
drop policy if exists change_impacts_governed_insert on public.change_impacts;
create policy change_impacts_governed_insert on public.change_impacts for insert to authenticated with check (
  project.can_access_project(project_id) and analyzed_by=(select auth.uid())
  and (select current_setting('conceptspaces.configuration_phase',true))='analyze'
);
drop policy if exists change_impacts_governed_update on public.change_impacts;
create policy change_impacts_governed_update on public.change_impacts for update to authenticated using (project.can_access_project(project_id)) with check (
  project.can_access_project(project_id)
  and (select current_setting('conceptspaces.configuration_phase',true))='analyze'
);

create or replace function configuration.project_configuration_hash(target_project_id uuid)
returns text
language plpgsql stable security invoker
set search_path=configuration,project,cde,engineering,regula,cost,governance,extensions,public,pg_temp
as $$
declare payload jsonb;
begin
  if not project.can_access_project(target_project_id) then raise exception 'project_access_required'; end if;
  select jsonb_build_object(
    'truth',coalesce((select jsonb_agg(jsonb_build_array(t.id,t.record_key,t.status,t.updated_at) order by t.record_key,t.id) from project.truth_records t where t.project_id=target_project_id and t.status<>'superseded'),'[]'::jsonb),
    'requirements',coalesce((select jsonb_agg(jsonb_build_array(r.id,r.code,r.status,r.updated_at) order by r.code,r.id) from project.requirements r where r.project_id=target_project_id),'[]'::jsonb),
    'documents',coalesce((select jsonb_agg(jsonb_build_array(d.id,d.document_number,d.revision,v.checksum) order by d.document_number,d.id) from cde.documents d left join cde.file_versions v on v.id=d.current_version_id where d.project_id=target_project_id),'[]'::jsonb),
    'models',coalesce((select jsonb_agg(jsonb_build_array(m.id,m.model_name,m.checksum,m.status) order by m.model_name,m.id) from cde.models m where m.project_id=target_project_id),'[]'::jsonb),
    'coordination',coalesce((select jsonb_agg(jsonb_build_array(cm.id,cm.coordination_hash,cm.state,cm.updated_at) order by cm.id) from engineering.coordination_matrix cm where cm.project_id=target_project_id),'[]'::jsonb),
    'regula',coalesce((select jsonb_build_array(er.id,er.result_hash,er.status,er.completed_at) from regula.evaluation_runs er where er.project_id=target_project_id order by er.created_at desc limit 1),'[]'::jsonb),
    'cost',coalesce((select jsonb_agg(jsonb_build_array(cp.id,cp.version,cp.total,cp.status) order by cp.version,cp.id) from cost.cost_plans cp where cp.project_id=target_project_id),'[]'::jsonb),
    'releases',coalesce((select jsonb_agg(jsonb_build_array(rs.id,rs.content_hash,rs.status,rs.updated_at) order by rs.id) from governance.release_safety_cases rs where rs.project_id=target_project_id),'[]'::jsonb)
  ) into payload;
  return encode(extensions.digest(payload::text,'sha256'),'hex');
end;$$;
revoke all on function configuration.project_configuration_hash(uuid) from public,anon;
grant execute on function configuration.project_configuration_hash(uuid) to authenticated;

create or replace function public.bootstrap_project_main_branch(target_project_id uuid)
returns uuid
language plpgsql security invoker
set search_path=public,configuration,project,audit,extensions,auth,pg_temp
as $$
declare branch_rec public.project_branches%rowtype; snapshot_hash text; org_id uuid;
begin
  if auth.uid() is null or not project.can_access_project(target_project_id) then raise exception 'project_access_required'; end if;
  select * into branch_rec from public.project_branches where project_id=target_project_id and name='main';
  if found then return branch_rec.id; end if;
  snapshot_hash:=configuration.project_configuration_hash(target_project_id);
  perform set_config('conceptspaces.configuration_phase','bootstrap',true);
  insert into public.project_branches(project_id,name,parent_branch_id,parent_commit_hash,head_commit_hash,purpose,status,created_by)
    values(target_project_id,'main',null,null,snapshot_hash,'Approved project configuration','active',auth.uid()) returning * into branch_rec;
  insert into public.project_commits(project_id,branch_id,parent_commit_hashes,content_hash,message,changed_object_refs,author_type,author_ref)
    values(target_project_id,branch_rec.id,'[]'::jsonb,snapshot_hash,'Genesis project configuration','[]'::jsonb,'human',auth.uid()::text);
  select organisation_id into org_id from project.projects where id=target_project_id;
  perform audit.append_event(org_id,target_project_id,'configuration.branch.bootstrapped','project_branch',branch_rec.id,null,to_jsonb(branch_rec),snapshot_hash,gen_random_uuid());
  return branch_rec.id;
end;$$;
revoke all on function public.bootstrap_project_main_branch(uuid) from public,anon;
grant execute on function public.bootstrap_project_main_branch(uuid) to authenticated;

create or replace function public.create_project_configuration_branch(input_payload jsonb)
returns uuid
language plpgsql security invoker
set search_path=public,project,audit,auth,pg_temp
as $$
declare project_id_value uuid:=nullif(input_payload->>'project_id','')::uuid; parent_id uuid:=nullif(input_payload->>'parent_branch_id','')::uuid; parent_rec public.project_branches%rowtype; branch_rec public.project_branches%rowtype; org_id uuid; branch_name text:=lower(nullif(btrim(input_payload->>'name'),''));
begin
  if project_id_value is null or auth.uid() is null or not project.can_access_project(project_id_value) then raise exception 'project_access_required'; end if;
  if branch_name is null or branch_name='main' then raise exception 'branch_name_required_and_main_reserved'; end if;
  if branch_name !~ '^[a-z0-9][a-z0-9._-]{1,62}$' then raise exception 'invalid_branch_name'; end if;
  if nullif(btrim(input_payload->>'purpose'),'') is null then raise exception 'branch_purpose_required'; end if;
  if parent_id is null then parent_id:=public.bootstrap_project_main_branch(project_id_value); end if;
  select * into parent_rec from public.project_branches where id=parent_id and project_id=project_id_value;
  if not found or parent_rec.status not in ('active','frozen') then raise exception 'eligible_parent_branch_required'; end if;
  perform set_config('conceptspaces.configuration_phase','branch',true);
  insert into public.project_branches(project_id,name,parent_branch_id,parent_commit_hash,head_commit_hash,purpose,status,created_by)
    values(project_id_value,branch_name,parent_rec.id,parent_rec.head_commit_hash,parent_rec.head_commit_hash,btrim(input_payload->>'purpose'),'active',auth.uid()) returning * into branch_rec;
  select organisation_id into org_id from project.projects where id=project_id_value;
  perform audit.append_event(org_id,project_id_value,'configuration.branch.created','project_branch',branch_rec.id,to_jsonb(parent_rec),to_jsonb(branch_rec),branch_rec.purpose,gen_random_uuid());
  return branch_rec.id;
end;$$;
revoke all on function public.create_project_configuration_branch(jsonb) from public,anon;
grant execute on function public.create_project_configuration_branch(jsonb) to authenticated;

create or replace function public.propose_project_change(input_payload jsonb)
returns uuid
language plpgsql security invoker
set search_path=public,project,audit,auth,extensions,pg_temp
as $$
declare project_id_value uuid:=nullif(input_payload->>'project_id','')::uuid; branch_id_value uuid:=nullif(input_payload->>'branch_id','')::uuid; branch_rec public.project_branches%rowtype; request_rec public.project_change_requests%rowtype; org_id uuid; change_ref_value text;
begin
  if project_id_value is null or auth.uid() is null or not project.can_access_project(project_id_value) then raise exception 'project_access_required'; end if;
  if branch_id_value is null then branch_id_value:=public.bootstrap_project_main_branch(project_id_value); end if;
  select * into branch_rec from public.project_branches where id=branch_id_value and project_id=project_id_value;
  if not found or branch_rec.status<>'active' then raise exception 'active_branch_required'; end if;
  if nullif(btrim(input_payload->>'title'),'') is null or nullif(btrim(input_payload->>'description'),'') is null then raise exception 'change_title_and_description_required'; end if;
  if jsonb_typeof(coalesce(input_payload->'source_object_refs','[]'::jsonb))<>'array' then raise exception 'source_object_refs_must_be_array'; end if;
  if jsonb_typeof(coalesce(input_payload->'proposed_disciplines','[]'::jsonb))<>'array' or jsonb_array_length(coalesce(input_payload->'proposed_disciplines','[]'::jsonb))=0 then raise exception 'at_least_one_affected_discipline_required'; end if;
  change_ref_value:=coalesce(nullif(btrim(input_payload->>'change_ref'),''),'CHG-'||upper(substr(replace(gen_random_uuid()::text,'-',''),1,8)));
  perform set_config('conceptspaces.configuration_phase','propose',true);
  insert into public.project_change_requests(project_id,branch_id,change_ref,title,description,source_object_refs,proposed_disciplines,status,requested_by)
    values(project_id_value,branch_id_value,change_ref_value,btrim(input_payload->>'title'),btrim(input_payload->>'description'),coalesce(input_payload->'source_object_refs','[]'::jsonb),coalesce(input_payload->'proposed_disciplines','[]'::jsonb),'draft',auth.uid()) returning * into request_rec;
  select organisation_id into org_id from project.projects where id=project_id_value;
  perform audit.append_event(org_id,project_id_value,'configuration.change.proposed','project_change_request',request_rec.id,null,to_jsonb(request_rec),request_rec.description,gen_random_uuid());
  return request_rec.id;
end;$$;
revoke all on function public.propose_project_change(jsonb) from public,anon;
grant execute on function public.propose_project_change(jsonb) to authenticated;

create or replace function public.analyze_project_change(target_change_request_id uuid,input_payload jsonb default '{}'::jsonb)
returns uuid
language plpgsql security invoker
set search_path=public,configuration,project,cde,engineering,regula,cost,operations,governance,coordination,audit,extensions,auth,pg_temp
as $$
declare req public.project_change_requests%rowtype; impact public.change_impacts%rowtype; baseline text; version_value int; disciplines text[]; org_id uuid; requirements_json jsonb; rules_json jsonb; documents_json jsonb; models_json jsonb; boq_json jsonb; contracts_json jsonb; coordination_json jsonb; releases_json jsonb; engineering_json jsonb; tasks_json jsonb; evidence_json jsonb; payload jsonb; analysis_hash_value text; cost_delta numeric:=nullif(input_payload->>'estimated_cost_delta','')::numeric; schedule_delta int:=nullif(input_payload->>'estimated_schedule_delta_days','')::int; reversal_cost numeric:=nullif(input_payload->>'decision_reversal_cost','')::numeric; confidence_value text:=upper(coalesce(nullif(btrim(input_payload->>'confidence'),''),'C'));
begin
  select * into req from public.project_change_requests where id=target_change_request_id for update;
  if not found then raise exception 'change_request_not_found'; end if;
  if auth.uid() is null or not project.can_access_project(req.project_id) then raise exception 'project_access_required'; end if;
  if req.status in ('applied','cancelled') then raise exception 'terminal_change_request_state'; end if;
  if confidence_value not in ('A','B','C','D') then raise exception 'unsupported_confidence'; end if;
  select array_agg(lower(value)) into disciplines from jsonb_array_elements_text(req.proposed_disciplines);
  baseline:=configuration.project_configuration_hash(req.project_id);
  select coalesce(max(ci.analysis_version),0)+1 into version_value from public.change_impacts ci where ci.change_request_id=req.id;

  select coalesce(jsonb_agg(jsonb_build_object('id',r.id,'code',r.code,'statement',r.statement,'status',r.status) order by r.code,r.id),'[]'::jsonb) into requirements_json from project.requirements r where r.project_id=req.project_id;
  select coalesce(jsonb_agg(jsonb_build_object('id',f.id,'rule_id',f.rule_id,'status',f.status,'disposition',f.disposition,'explanation',f.explanation) order by f.checked_at desc nulls last,f.id),'[]'::jsonb) into rules_json from regula.compliance_findings f where f.project_id=req.project_id and f.evaluation_run_id=(select er.id from regula.evaluation_runs er where er.project_id=req.project_id order by er.created_at desc limit 1);
  select coalesce(jsonb_agg(jsonb_build_object('id',d.id,'number',d.document_number::text,'title',d.title,'discipline',d.discipline,'revision',d.revision,'checksum',v.checksum) order by d.document_number,d.id),'[]'::jsonb) into documents_json from cde.documents d left join cde.file_versions v on v.id=d.current_version_id where d.project_id=req.project_id and lower(d.discipline)=any(disciplines);
  select coalesce(jsonb_agg(jsonb_build_object('id',m.id,'name',m.model_name,'discipline',m.discipline,'format',m.format,'checksum',m.checksum,'status',m.status) order by m.model_name,m.id),'[]'::jsonb) into models_json from cde.models m where m.project_id=req.project_id and lower(m.discipline)=any(disciplines);
  select coalesce(jsonb_agg(jsonb_build_object('id',b.id,'code',b.code::text,'description',b.description,'discipline',q.discipline,'total',b.total,'currency',b.currency) order by b.code,b.id),'[]'::jsonb) into boq_json from cost.boq_lines b join cost.cost_plans cp on cp.id=b.cost_plan_id left join cost.quantity_items q on q.id=b.quantity_item_id where cp.project_id=req.project_id and (q.discipline is null or lower(q.discipline)=any(disciplines));
  select coalesce(jsonb_agg(jsonb_build_object('id',c.id,'version',c.version,'status',c.status,'effective_at',c.effective_at,'expires_at',c.expires_at) order by c.version,c.id),'[]'::jsonb) into contracts_json from public.contracts c where c.project_id=req.project_id and c.status not in ('completed','terminated');
  select coalesce(jsonb_agg(jsonb_build_object('id',cm.id,'issue_id',cm.issue_id,'source_discipline',cm.source_discipline,'target_discipline',cm.target_discipline,'subject',cm.subject,'state',cm.state,'criticality',cm.criticality,'hash',cm.coordination_hash,'resources_current',engineering.coordination_item_resources_current(cm.id)) order by cm.updated_at desc,cm.id),'[]'::jsonb) into coordination_json from engineering.coordination_matrix cm where cm.project_id=req.project_id and (lower(cm.source_discipline)=any(disciplines) or lower(cm.target_discipline)=any(disciplines));
  select coalesce(jsonb_agg(jsonb_build_object('id',s.id,'package_reference',s.package_reference,'package_type',s.package_type,'status',s.status,'criticality',s.criticality,'content_hash',s.content_hash) order by s.updated_at desc,s.id),'[]'::jsonb) into releases_json from governance.release_safety_cases s where s.project_id=req.project_id and s.status<>'issued';
  select coalesce(jsonb_agg(jsonb_build_object('id',cr.id,'discipline',cr.discipline,'calculation_type',cr.calculation_type,'status',cr.status,'result_hash',cr.result_hash,'verification_status',cr.verification_status) order by cr.created_at desc,cr.id),'[]'::jsonb) into engineering_json from engineering.calculation_runs cr where cr.project_id=req.project_id and lower(cr.discipline)=any(disciplines);
  select coalesce(jsonb_agg(jsonb_build_object('id',t.id,'title',t.title,'state',t.state,'priority',t.priority,'due_at',t.due_at,'assignee_role_code',t.assignee_role_code) order by t.due_at nulls last,t.id),'[]'::jsonb) into tasks_json from operations.tasks t where t.project_id=req.project_id and t.state not in ('approved','cancelled');
  evidence_json:=jsonb_build_array(jsonb_build_object('type','configuration_baseline','hash',baseline),jsonb_build_object('type','branch_head','hash',(select b.head_commit_hash from public.project_branches b where b.id=req.branch_id)));
  payload:=jsonb_build_object('change_request_id',req.id,'version',version_value,'baseline_hash',baseline,'source_object_refs',req.source_object_refs,'disciplines',req.proposed_disciplines,'requirements',requirements_json,'rules',rules_json,'documents',documents_json,'models',models_json,'boq',boq_json,'contracts',contracts_json,'coordination',coordination_json,'releases',releases_json,'engineering',engineering_json,'tasks',tasks_json,'estimated_cost_delta',cost_delta,'estimated_schedule_delta_days',schedule_delta,'decision_reversal_cost',reversal_cost,'criticality',coalesce(nullif(input_payload->>'criticality',''),case when jsonb_array_length(releases_json)>0 or jsonb_array_length(coordination_json)>0 then 'C3' else 'C2' end),'confidence',confidence_value);
  analysis_hash_value:=encode(extensions.digest(payload::text,'sha256'),'hex');
  perform set_config('conceptspaces.configuration_phase','analyze',true);
  update public.change_impacts set analysis_state='superseded' where change_request_id=req.id and analysis_state='final';
  insert into public.change_impacts(project_id,change_ref,source_object_refs,affected_requirements,affected_rules,affected_disciplines,affected_documents,affected_model_objects,affected_boq_lines,affected_contracts,estimated_cost_delta,estimated_schedule_delta_days,decision_reversal_cost,criticality,confidence,analysis_evidence_refs,change_request_id,analysis_version,analysis_hash,baseline_hash,affected_coordination,affected_releases,affected_engineering_runs,affected_programme_tasks,analyzed_by,analysis_state)
    values(req.project_id,req.change_ref,req.source_object_refs,requirements_json,rules_json,req.proposed_disciplines,documents_json,models_json,boq_json,contracts_json,cost_delta,schedule_delta,reversal_cost,payload->>'criticality',confidence_value,evidence_json,req.id,version_value,analysis_hash_value,baseline,coordination_json,releases_json,engineering_json,tasks_json,auth.uid(),'final') returning * into impact;
  update public.project_change_requests set latest_impact_id=impact.id,status='analyzed',approval_request_id=null,approved_by=null,approved_at=null,updated_at=now() where id=req.id returning * into req;
  select organisation_id into org_id from project.projects where id=req.project_id;
  perform audit.append_event(org_id,req.project_id,'configuration.change.analyzed','change_impact',impact.id,null,to_jsonb(impact),analysis_hash_value,gen_random_uuid());
  return impact.id;
end;$$;
revoke all on function public.analyze_project_change(uuid,jsonb) from public,anon;
grant execute on function public.analyze_project_change(uuid,jsonb) to authenticated;

create or replace function public.request_project_change_approval(target_change_request_id uuid,target_role_required text default 'lead_architect')
returns uuid
language plpgsql security invoker
set search_path=public,project,audit,auth,pg_temp
as $$
declare req public.project_change_requests%rowtype; impact public.change_impacts%rowtype; approval_id uuid; org_id uuid;
begin
  select * into req from public.project_change_requests where id=target_change_request_id for update;
  if not found or auth.uid() is null or not project.can_access_project(req.project_id) then raise exception 'change_request_access_required'; end if;
  if req.status<>'analyzed' or req.latest_impact_id is null then raise exception 'final_change_analysis_required'; end if;
  select * into impact from public.change_impacts where id=req.latest_impact_id and analysis_state='final';
  if not found or nullif(impact.analysis_hash,'') is null then raise exception 'final_change_analysis_required'; end if;
  if configuration.project_configuration_hash(req.project_id)<>impact.baseline_hash then raise exception 'project_changed_reanalysis_required'; end if;
  approval_id:=public.request_governed_approval(jsonb_build_object('project_id',req.project_id,'resource_type','change','resource_id',req.id,'role_required',lower(btrim(target_role_required)),'criticality',impact.criticality,'comments','Project change '||req.change_ref||' exact impact analysis hash '||impact.analysis_hash));
  perform set_config('conceptspaces.configuration_phase','request_approval',true);
  update public.project_change_requests set status='approval_pending',approval_request_id=approval_id,updated_at=now() where id=req.id returning * into req;
  select organisation_id into org_id from project.projects where id=req.project_id;
  perform audit.append_event(org_id,req.project_id,'configuration.change.approval_requested','project_change_request',req.id,null,to_jsonb(req),impact.analysis_hash,gen_random_uuid());
  return approval_id;
end;$$;
revoke all on function public.request_project_change_approval(uuid,text) from public,anon;
grant execute on function public.request_project_change_approval(uuid,text) to authenticated;

create or replace function public.sync_project_change_approval(target_change_request_id uuid)
returns text
language plpgsql security invoker
set search_path=public,project,audit,auth,pg_temp
as $$
declare req public.project_change_requests%rowtype; impact public.change_impacts%rowtype; approval coordination.approval_requests%rowtype; org_id uuid; before_state jsonb;
begin
  select * into req from public.project_change_requests where id=target_change_request_id for update;
  if not found or auth.uid() is null or not project.can_access_project(req.project_id) then raise exception 'change_request_access_required'; end if;
  if req.approval_request_id is null or req.latest_impact_id is null then raise exception 'approval_request_required'; end if;
  select * into impact from public.change_impacts where id=req.latest_impact_id and analysis_state='final';
  select * into approval from coordination.approval_requests where id=req.approval_request_id;
  if approval.decision='pending' then return 'pending'; end if;
  before_state:=to_jsonb(req);
  perform set_config('conceptspaces.configuration_phase','sync_approval',true);
  if approval.decision in ('approved','approved_with_comments') then
    if approval.decision_evidence_hash is distinct from impact.analysis_hash then raise exception 'approval_hash_mismatch_reapproval_required'; end if;
    update public.project_change_requests set status='approved',approved_by=approval.decided_by,approved_at=approval.decided_at,updated_at=now() where id=req.id returning * into req;
  else
    update public.project_change_requests set status='rejected',approved_by=approval.decided_by,approved_at=approval.decided_at,updated_at=now() where id=req.id returning * into req;
  end if;
  select organisation_id into org_id from project.projects where id=req.project_id;
  perform audit.append_event(org_id,req.project_id,'configuration.change.'||req.status,'project_change_request',req.id,before_state,to_jsonb(req),approval.decision_evidence_hash,gen_random_uuid());
  return req.status;
end;$$;
revoke all on function public.sync_project_change_approval(uuid) from public,anon;
grant execute on function public.sync_project_change_approval(uuid) to authenticated;

create or replace function public.apply_project_change(target_change_request_id uuid,target_message text default null)
returns text
language plpgsql security invoker
set search_path=public,configuration,project,audit,extensions,auth,pg_temp
as $$
declare req public.project_change_requests%rowtype; impact public.change_impacts%rowtype; branch_rec public.project_branches%rowtype; before_branch jsonb; before_req jsonb; commit_hash text; org_id uuid;
begin
  select * into req from public.project_change_requests where id=target_change_request_id for update;
  if not found or auth.uid() is null or not project.can_access_project(req.project_id) then raise exception 'change_request_access_required'; end if;
  if req.status<>'approved' or req.latest_impact_id is null then raise exception 'approved_change_required'; end if;
  select * into impact from public.change_impacts where id=req.latest_impact_id and analysis_state='final';
  if configuration.project_configuration_hash(req.project_id)<>impact.baseline_hash then raise exception 'project_changed_reanalysis_required'; end if;
  select * into branch_rec from public.project_branches where id=req.branch_id and project_id=req.project_id for update;
  if not found or branch_rec.status<>'active' then raise exception 'active_branch_required'; end if;
  commit_hash:=encode(extensions.digest(jsonb_build_object('project_id',req.project_id,'branch_id',branch_rec.id,'parent',branch_rec.head_commit_hash,'change_ref',req.change_ref,'analysis_hash',impact.analysis_hash,'source_object_refs',req.source_object_refs)::text,'sha256'),'hex');
  before_branch:=to_jsonb(branch_rec); before_req:=to_jsonb(req);
  perform set_config('conceptspaces.configuration_phase','commit',true);
  insert into public.project_commits(project_id,branch_id,parent_commit_hashes,content_hash,message,changed_object_refs,author_type,author_ref)
    values(req.project_id,branch_rec.id,jsonb_build_array(branch_rec.head_commit_hash),commit_hash,coalesce(nullif(btrim(target_message),''),req.change_ref||' · '||req.title),req.source_object_refs,'human',auth.uid()::text);
  update public.project_branches set head_commit_hash=commit_hash where id=branch_rec.id returning * into branch_rec;
  perform set_config('conceptspaces.configuration_phase','apply',true);
  update public.project_change_requests set status='applied',applied_by=auth.uid(),applied_at=now(),updated_at=now() where id=req.id returning * into req;
  select organisation_id into org_id from project.projects where id=req.project_id;
  perform audit.append_event(org_id,req.project_id,'configuration.change.applied','project_change_request',req.id,before_req,to_jsonb(req),commit_hash,gen_random_uuid());
  perform audit.append_event(org_id,req.project_id,'configuration.branch.commit','project_branch',branch_rec.id,before_branch,to_jsonb(branch_rec),commit_hash,gen_random_uuid());
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
  select * into source_branch from public.project_branches where id=source_branch_id for update;
  select * into target_branch from public.project_branches where id=target_branch_id for update;
  if not found or source_branch.project_id is distinct from target_branch.project_id then raise exception 'same_project_branches_required'; end if;
  if auth.uid() is null or not project.can_access_project(source_branch.project_id) then raise exception 'project_access_required'; end if;
  if source_branch.status<>'active' or target_branch.status<>'active' then raise exception 'active_source_and_target_required'; end if;
  if nullif(btrim(target_reason),'') is null then raise exception 'merge_reason_required'; end if;
  select * into req from public.project_change_requests where id=target_change_request_id and project_id=source_branch.project_id and branch_id=source_branch.id;
  if not found or req.status<>'applied' or req.latest_impact_id is null then raise exception 'applied_source_branch_change_required'; end if;
  select * into impact from public.change_impacts where id=req.latest_impact_id and analysis_state='final';
  if impact is null or nullif(impact.analysis_hash,'') is null then raise exception 'final_impact_required'; end if;
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

create or replace function public.transition_project_configuration_branch(target_branch_id uuid,target_status text,target_reason text)
returns void
language plpgsql security invoker
set search_path=public,project,audit,auth,pg_temp
as $$
declare b public.project_branches%rowtype; before_state jsonb; next_status text:=lower(btrim(target_status)); org_id uuid;
begin
  select * into b from public.project_branches where id=target_branch_id for update;
  if not found or auth.uid() is null or not project.can_access_project(b.project_id) then raise exception 'branch_access_required'; end if;
  if b.name='main' then raise exception 'main_branch_state_is_governed_by_merge_only'; end if;
  if next_status not in ('active','frozen','abandoned') then raise exception 'unsupported_branch_state'; end if;
  if b.status in ('merged','abandoned') then raise exception 'terminal_branch_state'; end if;
  if nullif(btrim(target_reason),'') is null then raise exception 'branch_state_reason_required'; end if;
  before_state:=to_jsonb(b);
  perform set_config('conceptspaces.configuration_phase','branch_state',true);
  update public.project_branches set status=next_status where id=b.id returning * into b;
  select organisation_id into org_id from project.projects where id=b.project_id;
  perform audit.append_event(org_id,b.project_id,'configuration.branch.'||next_status,'project_branch',b.id,before_state,to_jsonb(b),btrim(target_reason),gen_random_uuid());
end;$$;
revoke all on function public.transition_project_configuration_branch(uuid,text,text) from public,anon;
grant execute on function public.transition_project_configuration_branch(uuid,text,text) to authenticated;

create or replace function public.list_project_configuration_workspace(target_project_id uuid)
returns jsonb
language sql stable security invoker
set search_path=public,project,coordination
as $$
  select jsonb_build_object(
    'branches',coalesce((select jsonb_agg(to_jsonb(b) order by case when b.name='main' then 0 else 1 end,b.created_at) from public.project_branches b where b.project_id=target_project_id),'[]'::jsonb),
    'commits',coalesce((select jsonb_agg(to_jsonb(c) order by c.created_at desc) from public.project_commits c where c.project_id=target_project_id),'[]'::jsonb),
    'changes',coalesce((select jsonb_agg(to_jsonb(r) order by r.updated_at desc) from public.project_change_requests r where r.project_id=target_project_id),'[]'::jsonb),
    'impacts',coalesce((select jsonb_agg(to_jsonb(i) order by i.created_at desc) from public.change_impacts i where i.project_id=target_project_id),'[]'::jsonb),
    'approvals',coalesce((select jsonb_agg(to_jsonb(a) order by a.requested_at desc) from coordination.approval_requests a where a.project_id=target_project_id and a.resource_type='change'),'[]'::jsonb)
  );
$$;
revoke all on function public.list_project_configuration_workspace(uuid) from public,anon;
grant execute on function public.list_project_configuration_workspace(uuid) to authenticated;

commit;
