begin;

create or replace function public.create_work_task(input_payload jsonb)
returns uuid
language plpgsql
security invoker
set search_path = operations, core, project, audit, public
as $$
declare
  org_id uuid := nullif(input_payload->>'organisation_id','')::uuid;
  project_id_value uuid := nullif(input_payload->>'project_id','')::uuid;
  t operations.tasks%rowtype;
  priority_value text := lower(coalesce(nullif(btrim(input_payload->>'priority'),''),'normal'));
begin
  if org_id is null then raise exception 'organisation_required'; end if;
  if project_id_value is not null and not project.can_access_project(project_id_value) then raise exception 'project_access_required'; end if;
  if project_id_value is null and not core.is_internal_org_member(org_id) then raise exception 'organisation_access_required'; end if;
  if nullif(btrim(input_payload->>'title'),'') is null then raise exception 'task_title_required'; end if;
  if priority_value not in ('low','normal','high','urgent') then raise exception 'unsupported_task_priority'; end if;

  insert into operations.tasks(
    organisation_id, project_id, title, task_type, state, priority,
    assignee_user_id, assignee_role_code, due_at, maker_user_id, evidence_refs
  ) values (
    org_id, project_id_value, btrim(input_payload->>'title'),
    coalesce(nullif(lower(btrim(input_payload->>'task_type')),''),'manual'),
    'open', priority_value, nullif(input_payload->>'assignee_user_id','')::uuid,
    nullif(btrim(input_payload->>'assignee_role_code'),''),
    nullif(input_payload->>'due_at','')::timestamptz,auth.uid(),
    coalesce(input_payload->'evidence_refs','[]'::jsonb)
  ) returning * into t;

  perform audit.append_event(org_id,project_id_value,'operations.task.created','task',t.id,null,to_jsonb(t),null,gen_random_uuid());
  return t.id;
end;
$$;
revoke all on function public.create_work_task(jsonb) from public, anon;
grant execute on function public.create_work_task(jsonb) to authenticated;

create or replace function public.transition_work_task(target_task_id uuid,new_state text,evidence_refs jsonb default '[]'::jsonb)
returns void
language plpgsql
security invoker
set search_path = operations, core, project, audit, public
as $$
declare
  t operations.tasks%rowtype;
  before_state jsonb;
  state_value text := lower(btrim(new_state));
begin
  if state_value not in ('open','in_progress','submitted','approved','rejected','cancelled') then raise exception 'unsupported_task_state'; end if;
  select * into t from operations.tasks where id=target_task_id for update;
  if not found then raise exception 'task_not_found'; end if;
  if t.project_id is not null and not project.can_access_project(t.project_id) then raise exception 'project_access_required'; end if;
  if t.project_id is null and not core.is_internal_org_member(t.organisation_id) then raise exception 'organisation_access_required'; end if;

  if state_value in ('approved','rejected') then
    if t.state <> 'submitted' then raise exception 'task_not_submitted'; end if;
    if t.maker_user_id = auth.uid() then raise exception 'maker_cannot_check_own_task'; end if;
    if t.assignee_user_id is not null
       and t.assignee_user_id <> auth.uid()
       and not core.has_org_role(t.organisation_id,array['super_admin','org_admin']) then
      raise exception 'task_checker_not_assigned';
    end if;
  end if;

  before_state := to_jsonb(t);
  update operations.tasks
  set state=state_value,
      checker_user_id=case when state_value in ('approved','rejected') then auth.uid() else checker_user_id end,
      evidence_refs=case when coalesce(evidence_refs,'[]'::jsonb)='[]'::jsonb then operations.tasks.evidence_refs else evidence_refs end,
      updated_at=now()
  where id=t.id returning * into t;
  perform audit.append_event(t.organisation_id,t.project_id,'operations.task.'||state_value,'task',t.id,before_state,to_jsonb(t),null,gen_random_uuid());
end;
$$;
revoke all on function public.transition_work_task(uuid,text,jsonb) from public, anon;
grant execute on function public.transition_work_task(uuid,text,jsonb) to authenticated;

create or replace function public.list_work_tasks(target_organisation_id uuid,target_project_id uuid default null)
returns table(
  id uuid,title text,task_type text,state text,priority text,assignee_user_id uuid,
  assignee_role_code text,due_at timestamptz,sla_breached boolean,maker_user_id uuid,
  checker_user_id uuid,project_id uuid,created_at timestamptz
)
language sql
stable
security invoker
set search_path = operations, public
as $$
  select t.id,t.title,t.task_type,t.state,t.priority,t.assignee_user_id,
         t.assignee_role_code,t.due_at,t.sla_breached,t.maker_user_id,
         t.checker_user_id,t.project_id,t.created_at
  from operations.tasks t
  where t.organisation_id=target_organisation_id
    and (target_project_id is null or t.project_id=target_project_id)
  order by case t.priority when 'urgent' then 1 when 'high' then 2 when 'normal' then 3 else 4 end,
           t.due_at nulls last,t.created_at desc;
$$;
revoke all on function public.list_work_tasks(uuid,uuid) from public, anon;
grant execute on function public.list_work_tasks(uuid,uuid) to authenticated;

create or replace function public.create_coordination_issue(input_payload jsonb)
returns uuid
language plpgsql
security invoker
set search_path = coordination, project, core, audit, public, extensions
as $$
declare
  project_id_value uuid := nullif(input_payload->>'project_id','')::uuid;
  org_id uuid;
  i coordination.issues%rowtype;
  issue_no text;
  issue_type_value text := lower(coalesce(nullif(btrim(input_payload->>'issue_type'),''),'coordination'));
  priority_value text := lower(coalesce(nullif(btrim(input_payload->>'priority'),''),'medium'));
  criticality_value text := upper(coalesce(nullif(btrim(input_payload->>'criticality'),''),'C1'));
begin
  if project_id_value is null then raise exception 'project_required'; end if;
  if not project.can_access_project(project_id_value) then raise exception 'project_access_required'; end if;
  if nullif(btrim(input_payload->>'title'),'') is null then raise exception 'issue_title_required'; end if;
  if issue_type_value not in ('coordination','design','rfi','quality','regulatory','commercial','site') then raise exception 'unsupported_issue_type'; end if;
  if priority_value not in ('low','medium','high','critical') then raise exception 'unsupported_issue_priority'; end if;
  if criticality_value not in ('C0','C1','C2','C3','C4') then raise exception 'unsupported_criticality'; end if;

  select organisation_id into org_id from project.projects where id=project_id_value;
  issue_no := coalesce(nullif(btrim(input_payload->>'issue_number'),''),'ISS-'||upper(substr(replace(gen_random_uuid()::text,'-',''),1,8)));
  insert into coordination.issues(
    project_id,issue_number,issue_type,title,description,status,priority,criticality,
    assignee_id,due_at,bcf_topic_ref,location_ref,created_by
  ) values (
    project_id_value,issue_no,issue_type_value,btrim(input_payload->>'title'),
    coalesce(nullif(btrim(input_payload->>'description'),''),'No description provided.'),
    'open',priority_value,criticality_value,nullif(input_payload->>'assignee_id','')::uuid,
    nullif(input_payload->>'due_at','')::timestamptz,nullif(btrim(input_payload->>'bcf_topic_ref'),''),
    nullif(btrim(input_payload->>'location_ref'),''),auth.uid()
  ) returning * into i;
  perform audit.append_event(org_id,project_id_value,'coordination.issue.created','issue',i.id,null,to_jsonb(i),null,gen_random_uuid());
  return i.id;
end;
$$;
revoke all on function public.create_coordination_issue(jsonb) from public, anon;
grant execute on function public.create_coordination_issue(jsonb) to authenticated;

create or replace function public.add_issue_comment(target_issue_id uuid,comment_body text,evidence_refs jsonb default '[]'::jsonb)
returns uuid
language plpgsql
security invoker
set search_path = coordination, project, audit, public
as $$
declare
  i coordination.issues%rowtype;
  org_id uuid;
  c coordination.issue_comments%rowtype;
begin
  select * into i from coordination.issues where id=target_issue_id;
  if not found then raise exception 'issue_not_found'; end if;
  if not project.can_access_project(i.project_id) then raise exception 'project_access_required'; end if;
  if nullif(btrim(comment_body),'') is null then raise exception 'comment_required'; end if;
  select organisation_id into org_id from project.projects where id=i.project_id;
  insert into coordination.issue_comments(issue_id,body,author_id,evidence_refs)
  values(i.id,btrim(comment_body),auth.uid(),coalesce(evidence_refs,'[]'::jsonb)) returning * into c;
  perform audit.append_event(org_id,i.project_id,'coordination.issue.comment_added','issue_comment',c.id,null,to_jsonb(c),null,gen_random_uuid());
  return c.id;
end;
$$;
revoke all on function public.add_issue_comment(uuid,text,jsonb) from public, anon;
grant execute on function public.add_issue_comment(uuid,text,jsonb) to authenticated;

create or replace function public.list_project_issues(target_project_id uuid)
returns table(
  id uuid,issue_number text,issue_type text,title text,description text,status text,
  priority text,criticality text,assignee_id uuid,due_at timestamptz,created_by uuid,
  created_at timestamptz,updated_at timestamptz
)
language sql
stable
security invoker
set search_path = coordination, public
as $$
  select i.id,i.issue_number::text,i.issue_type,i.title,i.description,i.status,
         i.priority,i.criticality,i.assignee_id,i.due_at,i.created_by,i.created_at,i.updated_at
  from coordination.issues i
  where i.project_id=target_project_id
  order by i.created_at desc;
$$;
revoke all on function public.list_project_issues(uuid) from public, anon;
grant execute on function public.list_project_issues(uuid) to authenticated;

create or replace function public.request_governed_approval(input_payload jsonb)
returns uuid
language plpgsql
security invoker
set search_path = coordination, project, audit, public
as $$
declare
  project_id_value uuid := nullif(input_payload->>'project_id','')::uuid;
  org_id uuid;
  a coordination.approval_requests%rowtype;
  resource_type_value text := lower(btrim(input_payload->>'resource_type'));
  criticality_value text := upper(coalesce(nullif(btrim(input_payload->>'criticality'),''),'C1'));
begin
  if project_id_value is null then raise exception 'project_required'; end if;
  if not project.can_access_project(project_id_value) then raise exception 'project_access_required'; end if;
  if nullif(input_payload->>'resource_id','') is null then raise exception 'resource_id_required'; end if;
  if resource_type_value not in ('document','model','design_option','release','commercial','change') then raise exception 'unsupported_approval_resource_type'; end if;
  if criticality_value not in ('C0','C1','C2','C3','C4') then raise exception 'unsupported_criticality'; end if;

  select organisation_id into org_id from project.projects where id=project_id_value;
  insert into coordination.approval_requests(
    project_id,resource_type,resource_id,requested_from,role_required,criticality,
    decision,comments,requested_by
  ) values (
    project_id_value,resource_type_value,nullif(input_payload->>'resource_id','')::uuid,
    nullif(input_payload->>'requested_from','')::uuid,
    nullif(lower(btrim(input_payload->>'role_required')),''),criticality_value,
    'pending',nullif(btrim(input_payload->>'comments'),''),auth.uid()
  ) returning * into a;
  perform audit.append_event(org_id,project_id_value,'approval.requested','approval_request',a.id,null,to_jsonb(a),null,gen_random_uuid());
  return a.id;
end;
$$;
revoke all on function public.request_governed_approval(jsonb) from public, anon;
grant execute on function public.request_governed_approval(jsonb) to authenticated;

create or replace function public.decide_governed_approval(
  target_approval_id uuid,new_decision text,decision_comments text,reviewed_resource_hash text
)
returns void
language plpgsql
security invoker
set search_path = coordination, project, core, audit, public
as $$
declare
  a coordination.approval_requests%rowtype;
  org_id uuid;
  before_state jsonb;
  decision_value text := lower(btrim(new_decision));
  role_ok boolean := false;
begin
  if decision_value not in ('approved','approved_with_comments','rejected') then raise exception 'unsupported_approval_decision'; end if;
  select * into a from coordination.approval_requests where id=target_approval_id for update;
  if not found then raise exception 'approval_not_found'; end if;
  if a.decision <> 'pending' then raise exception 'approval_already_decided'; end if;
  if not project.can_access_project(a.project_id) then raise exception 'project_access_required'; end if;
  if a.requested_by=auth.uid() and a.criticality in ('C2','C3','C4') then raise exception 'maker_cannot_approve_own_controlled_action'; end if;
  if a.requested_from is not null and a.requested_from<>auth.uid() then raise exception 'approval_not_assigned_to_current_user'; end if;
  if nullif(btrim(reviewed_resource_hash),'') is null then raise exception 'reviewed_resource_hash_required'; end if;

  if a.role_required is null then
    role_ok := true;
  else
    role_ok := exists(
      select 1 from project.project_members pm
      where pm.project_id=a.project_id and pm.user_id=auth.uid()
        and pm.status='active' and pm.role_code=a.role_required
    ) or exists(
      select 1 from project.projects p
      where p.id=a.project_id
        and core.has_org_role(p.organisation_id,array[a.role_required,'super_admin','org_admin'])
    );
  end if;
  if not role_ok then raise exception 'approval_role_authority_required'; end if;

  if a.criticality in ('C3','C4') then
    if a.role_required not in ('lead_architect','architect','structural_engineer','mep_engineer','quantity_surveyor','regulatory_reviewer') then
      raise exception 'professional_role_required_for_c3_c4';
    end if;
    if not core.has_verified_professional_eligibility(auth.uid(),a.role_required) then
      raise exception 'verified_professional_eligibility_required';
    end if;
  end if;

  select organisation_id into org_id from project.projects where id=a.project_id;
  before_state := to_jsonb(a);
  update coordination.approval_requests
  set decision=decision_value,comments=decision_comments,decided_at=now(),
      decision_evidence_hash=btrim(reviewed_resource_hash)
  where id=a.id returning * into a;
  perform audit.append_event(org_id,a.project_id,'approval.'||decision_value,'approval_request',a.id,before_state,to_jsonb(a),decision_comments,gen_random_uuid());
end;
$$;
revoke all on function public.decide_governed_approval(uuid,text,text,text) from public, anon;
grant execute on function public.decide_governed_approval(uuid,text,text,text) to authenticated;

create or replace function public.list_project_approvals(target_project_id uuid)
returns table(
  id uuid,resource_type text,resource_id uuid,requested_from uuid,role_required text,
  criticality text,decision text,comments text,requested_by uuid,requested_at timestamptz,
  decided_at timestamptz,decision_evidence_hash text
)
language sql
stable
security invoker
set search_path = coordination, public
as $$
  select a.id,a.resource_type,a.resource_id,a.requested_from,a.role_required,
         a.criticality,a.decision,a.comments,a.requested_by,a.requested_at,
         a.decided_at,a.decision_evidence_hash
  from coordination.approval_requests a
  where a.project_id=target_project_id
  order by case when a.decision='pending' then 0 else 1 end,a.requested_at desc;
$$;
revoke all on function public.list_project_approvals(uuid) from public, anon;
grant execute on function public.list_project_approvals(uuid) to authenticated;

commit;
