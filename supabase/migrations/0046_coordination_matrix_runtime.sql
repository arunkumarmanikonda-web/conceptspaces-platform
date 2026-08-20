begin;

alter table engineering.coordination_matrix
  add column if not exists issue_id uuid references coordination.issues(id) on delete cascade,
  add column if not exists criticality text not null default 'C1' check (criticality in ('C0','C1','C2','C3','C4')),
  add column if not exists source_resource_type text check (source_resource_type is null or source_resource_type in ('document','model','truth_record','requirement','design_option','release')),
  add column if not exists source_resource_id uuid,
  add column if not exists source_resource_hash text,
  add column if not exists target_resource_type text check (target_resource_type is null or target_resource_type in ('document','model','truth_record','requirement','design_option','release')),
  add column if not exists target_resource_id uuid,
  add column if not exists target_resource_hash text,
  add column if not exists coordination_hash text,
  add column if not exists resolution_note text,
  add column if not exists resolution_evidence_refs jsonb not null default '[]'::jsonb,
  add column if not exists accepted_deviation_approval_id uuid references coordination.approval_requests(id) on delete set null,
  add column if not exists created_by uuid references auth.users(id),
  add column if not exists resolved_by uuid references auth.users(id),
  add column if not exists resolved_at timestamptz;

create unique index if not exists coordination_matrix_issue_unique_idx
  on engineering.coordination_matrix(issue_id) where issue_id is not null;
create index if not exists coordination_matrix_owner_idx
  on engineering.coordination_matrix(owner_user_id,state,updated_at desc);
create index if not exists coordination_matrix_source_resource_idx
  on engineering.coordination_matrix(source_resource_type,source_resource_id) where source_resource_id is not null;
create index if not exists coordination_matrix_target_resource_idx
  on engineering.coordination_matrix(target_resource_type,target_resource_id) where target_resource_id is not null;
create index if not exists coordination_matrix_deviation_approval_idx
  on engineering.coordination_matrix(accepted_deviation_approval_id) where accepted_deviation_approval_id is not null;
create index if not exists coordination_matrix_created_by_idx
  on engineering.coordination_matrix(created_by,created_at desc);
create index if not exists coordination_matrix_resolved_by_idx
  on engineering.coordination_matrix(resolved_by,resolved_at desc) where resolved_by is not null;

create table if not exists engineering.coordination_matrix_events (
  id uuid primary key default gen_random_uuid(),
  coordination_item_id uuid not null references engineering.coordination_matrix(id) on delete cascade,
  project_id uuid not null references project.projects(id) on delete cascade,
  actor_id uuid not null references auth.users(id) on delete restrict,
  event_type text not null check (event_type in ('raised','owner_changed','coordinating','resolved','deviation_requested','accepted_deviation','reopened')),
  reason text not null,
  evidence_refs jsonb not null default '[]'::jsonb,
  snapshot jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now()
);
create index if not exists coordination_matrix_events_item_idx on engineering.coordination_matrix_events(coordination_item_id,created_at desc);
create index if not exists coordination_matrix_events_project_idx on engineering.coordination_matrix_events(project_id,created_at desc);
create index if not exists coordination_matrix_events_actor_idx on engineering.coordination_matrix_events(actor_id,created_at desc);
alter table engineering.coordination_matrix_events enable row level security;

grant select,insert,update on engineering.coordination_matrix to authenticated;
grant select,insert on engineering.coordination_matrix_events to authenticated;
grant insert on coordination.issue_links to authenticated;

drop policy if exists coordination_matrix_governed_insert on engineering.coordination_matrix;
create policy coordination_matrix_governed_insert on engineering.coordination_matrix
for insert to authenticated with check (
  (select current_setting('conceptspaces.coordination_phase',true))='raise'
  and project.can_access_project(project_id)
  and created_by=(select auth.uid())
  and state='open'
);

drop policy if exists coordination_matrix_governed_update on engineering.coordination_matrix;
create policy coordination_matrix_governed_update on engineering.coordination_matrix
for update to authenticated
using (
  (select current_setting('conceptspaces.coordination_phase',true)) in ('transition','assign','request_deviation')
  and project.can_access_project(project_id)
)
with check (
  (select current_setting('conceptspaces.coordination_phase',true)) in ('transition','assign','request_deviation')
  and project.can_access_project(project_id)
);

drop policy if exists coordination_matrix_events_read on engineering.coordination_matrix_events;
create policy coordination_matrix_events_read on engineering.coordination_matrix_events
for select to authenticated using (project.can_access_project(project_id));

drop policy if exists coordination_matrix_events_governed_insert on engineering.coordination_matrix_events;
create policy coordination_matrix_events_governed_insert on engineering.coordination_matrix_events
for insert to authenticated with check (
  project.can_access_project(project_id)
  and actor_id=(select auth.uid())
  and (select current_setting('conceptspaces.coordination_phase',true)) in ('raise','transition','assign','request_deviation')
);

drop policy if exists issue_links_coordination_insert on coordination.issue_links;
create policy issue_links_coordination_insert on coordination.issue_links
for insert to authenticated with check (
  (select current_setting('conceptspaces.coordination_phase',true))='raise'
  and exists(select 1 from coordination.issues i where i.id=issue_id and project.can_access_project(i.project_id))
);

create or replace function coordination.resource_snapshot(
  target_project_id uuid,target_resource_type text,target_resource_id uuid
) returns jsonb
language plpgsql stable security invoker
set search_path=coordination,cde,project,aec,governance,extensions,public,pg_temp
as $$
declare rtype text:=lower(nullif(btrim(target_resource_type),'')); result jsonb;
begin
  if rtype is null and target_resource_id is null then return null; end if;
  if rtype is null or target_resource_id is null then raise exception 'resource_type_and_id_required_together'; end if;
  if rtype='document' then
    select jsonb_build_object('type','document','id',d.id,'label',d.document_number::text||' · '||d.title||' · '||d.revision,'hash',v.checksum)
      into result from cde.documents d join cde.file_versions v on v.id=d.current_version_id
      where d.id=target_resource_id and d.project_id=target_project_id;
  elsif rtype='model' then
    select jsonb_build_object('type','model','id',m.id,'label',m.model_name||' · '||upper(m.discipline)||' · '||upper(m.format),'hash',m.checksum)
      into result from cde.models m where m.id=target_resource_id and m.project_id=target_project_id;
  elsif rtype='truth_record' then
    select jsonb_build_object('type','truth_record','id',t.id,'label',t.record_key,'hash',encode(extensions.digest(to_jsonb(t)::text,'sha256'),'hex'))
      into result from project.truth_records t where t.id=target_resource_id and t.project_id=target_project_id and t.status<>'superseded';
  elsif rtype='requirement' then
    select jsonb_build_object('type','requirement','id',q.id,'label',q.code::text||' · '||q.statement,'hash',encode(extensions.digest(to_jsonb(q)::text,'sha256'),'hex'))
      into result from project.requirements q where q.id=target_resource_id and q.project_id=target_project_id;
  elsif rtype='design_option' then
    select jsonb_build_object('type','design_option','id',o.id,'label',o.name,'hash',encode(extensions.digest(to_jsonb(o)::text,'sha256'),'hex'))
      into result from aec.design_options o where o.id=target_resource_id and o.project_id=target_project_id;
  elsif rtype='release' then
    select jsonb_build_object('type','release','id',s.id,'label',coalesce(s.package_reference,s.package_type),'hash',s.content_hash)
      into result from governance.release_safety_cases s where s.id=target_resource_id and s.project_id=target_project_id;
  else
    raise exception 'unsupported_coordination_resource_type';
  end if;
  if result is null then raise exception 'coordination_resource_not_found_in_project'; end if;
  if nullif(result->>'hash','') is null then raise exception 'coordination_resource_hash_required'; end if;
  return result;
end;$$;
revoke all on function coordination.resource_snapshot(uuid,text,uuid) from public,anon;
grant execute on function coordination.resource_snapshot(uuid,text,uuid) to authenticated;

create or replace function public.raise_coordination_matrix_item(input_payload jsonb)
returns uuid
language plpgsql security invoker
set search_path=public,coordination,engineering,project,audit,extensions,auth,pg_temp
as $$
declare
  project_id_value uuid:=nullif(input_payload->>'project_id','')::uuid;
  source_discipline_value text:=lower(btrim(input_payload->>'source_discipline'));
  target_discipline_value text:=lower(btrim(input_payload->>'target_discipline'));
  criticality_value text:=upper(coalesce(nullif(btrim(input_payload->>'criticality'),''),'C1'));
  priority_value text:=lower(coalesce(nullif(btrim(input_payload->>'priority'),''),'medium'));
  owner_value uuid:=coalesce(nullif(input_payload->>'owner_user_id','')::uuid,auth.uid());
  issue_id_value uuid;
  issue_row coordination.issues%rowtype;
  matrix_row engineering.coordination_matrix%rowtype;
  source_snapshot jsonb;
  target_snapshot jsonb;
  hash_payload jsonb;
  org_id uuid;
  issue_no text;
begin
  if auth.uid() is null or project_id_value is null or not project.can_access_project(project_id_value) then raise exception 'project_access_required'; end if;
  if nullif(source_discipline_value,'') is null or nullif(target_discipline_value,'') is null then raise exception 'source_and_target_disciplines_required'; end if;
  if source_discipline_value=target_discipline_value then raise exception 'cross_discipline_target_required'; end if;
  if nullif(btrim(input_payload->>'subject'),'') is null then raise exception 'coordination_subject_required'; end if;
  if criticality_value not in ('C0','C1','C2','C3','C4') then raise exception 'unsupported_criticality'; end if;
  if priority_value not in ('low','medium','high','critical') then raise exception 'unsupported_issue_priority'; end if;
  if owner_value<>auth.uid() and not exists(select 1 from project.project_members pm where pm.project_id=project_id_value and pm.user_id=owner_value and pm.status='active') then raise exception 'coordination_owner_must_be_active_project_member'; end if;

  source_snapshot:=coordination.resource_snapshot(project_id_value,input_payload->>'source_resource_type',nullif(input_payload->>'source_resource_id','')::uuid);
  target_snapshot:=coordination.resource_snapshot(project_id_value,input_payload->>'target_resource_type',nullif(input_payload->>'target_resource_id','')::uuid);
  issue_no:=coalesce(nullif(upper(btrim(input_payload->>'issue_number')),''),'COORD-'||upper(substr(replace(gen_random_uuid()::text,'-',''),1,8)));
  select organisation_id into org_id from project.projects where id=project_id_value;

  insert into coordination.issues(project_id,issue_number,issue_type,title,description,status,priority,criticality,assignee_id,due_at,bcf_topic_ref,location_ref,created_by)
  values(project_id_value,issue_no,'coordination',btrim(input_payload->>'subject'),coalesce(nullif(btrim(input_payload->>'description'),''),'Cross-discipline coordination item.'),'open',priority_value,criticality_value,owner_value,nullif(input_payload->>'due_at','')::timestamptz,nullif(btrim(input_payload->>'bcf_topic_ref'),''),nullif(btrim(input_payload->>'location_ref'),''),auth.uid())
  returning * into issue_row;
  issue_id_value:=issue_row.id;

  hash_payload:=jsonb_build_object(
    'project_id',project_id_value,'issue_id',issue_id_value,'source_discipline',source_discipline_value,'target_discipline',target_discipline_value,
    'subject',btrim(input_payload->>'subject'),'criticality',criticality_value,'source_resource',source_snapshot,'target_resource',target_snapshot
  );

  perform set_config('conceptspaces.coordination_phase','raise',true);
  insert into engineering.coordination_matrix(project_id,source_discipline,target_discipline,subject,requirement_ref,issue_ref,state,owner_user_id,issue_id,criticality,
    source_resource_type,source_resource_id,source_resource_hash,target_resource_type,target_resource_id,target_resource_hash,coordination_hash,created_by)
  values(project_id_value,source_discipline_value,target_discipline_value,btrim(input_payload->>'subject'),nullif(btrim(input_payload->>'requirement_ref'),''),issue_no,'open',owner_value,issue_id_value,criticality_value,
    nullif(lower(btrim(input_payload->>'source_resource_type')),''),nullif(input_payload->>'source_resource_id','')::uuid,source_snapshot->>'hash',nullif(lower(btrim(input_payload->>'target_resource_type')),''),nullif(input_payload->>'target_resource_id','')::uuid,target_snapshot->>'hash',encode(extensions.digest(hash_payload::text,'sha256'),'hex'),auth.uid())
  returning * into matrix_row;

  if source_snapshot is not null then insert into coordination.issue_links(issue_id,resource_type,resource_id,relationship) values(issue_id_value,source_snapshot->>'type',(source_snapshot->>'id')::uuid,'source') on conflict do nothing; end if;
  if target_snapshot is not null then insert into coordination.issue_links(issue_id,resource_type,resource_id,relationship) values(issue_id_value,target_snapshot->>'type',(target_snapshot->>'id')::uuid,'target') on conflict do nothing; end if;

  insert into engineering.coordination_matrix_events(coordination_item_id,project_id,actor_id,event_type,reason,evidence_refs,snapshot)
  values(matrix_row.id,project_id_value,auth.uid(),'raised',coalesce(nullif(btrim(input_payload->>'reason'),''),'Cross-discipline coordination item raised'),'[]'::jsonb,to_jsonb(matrix_row));
  perform audit.append_event(org_id,project_id_value,'coordination.matrix.raised','coordination_matrix',matrix_row.id,null,to_jsonb(matrix_row),coalesce(nullif(btrim(input_payload->>'reason'),''),'Coordination item raised'),gen_random_uuid());
  return matrix_row.id;
end;$$;
revoke all on function public.raise_coordination_matrix_item(jsonb) from public,anon;
grant execute on function public.raise_coordination_matrix_item(jsonb) to authenticated;

create or replace function public.assign_coordination_matrix_owner(target_item_id uuid,target_owner_user_id uuid,target_reason text)
returns void
language plpgsql security invoker
set search_path=public,coordination,engineering,project,audit,auth,pg_temp
as $$
declare item engineering.coordination_matrix%rowtype; before_item jsonb; org_id uuid;
begin
  select * into item from engineering.coordination_matrix where id=target_item_id for update; if not found then raise exception 'coordination_item_not_found'; end if;
  if auth.uid() is null or not project.can_manage_project(item.project_id) then raise exception 'project_manage_authority_required'; end if;
  if not exists(select 1 from project.project_members pm where pm.project_id=item.project_id and pm.user_id=target_owner_user_id and pm.status='active') and target_owner_user_id<>auth.uid() then raise exception 'coordination_owner_must_be_active_project_member'; end if;
  if nullif(btrim(target_reason),'') is null then raise exception 'owner_change_reason_required'; end if;
  before_item:=to_jsonb(item); select organisation_id into org_id from project.projects where id=item.project_id;
  perform set_config('conceptspaces.coordination_phase','assign',true);
  update engineering.coordination_matrix set owner_user_id=target_owner_user_id,updated_at=now() where id=item.id returning * into item;
  update coordination.issues set assignee_id=target_owner_user_id,updated_at=now() where id=item.issue_id;
  insert into engineering.coordination_matrix_events(coordination_item_id,project_id,actor_id,event_type,reason,evidence_refs,snapshot) values(item.id,item.project_id,auth.uid(),'owner_changed',btrim(target_reason),'[]'::jsonb,to_jsonb(item));
  perform audit.append_event(org_id,item.project_id,'coordination.matrix.owner_changed','coordination_matrix',item.id,before_item,to_jsonb(item),btrim(target_reason),gen_random_uuid());
end;$$;
revoke all on function public.assign_coordination_matrix_owner(uuid,uuid,text) from public,anon;
grant execute on function public.assign_coordination_matrix_owner(uuid,uuid,text) to authenticated;

create or replace function public.request_coordination_deviation_approval(target_item_id uuid,target_role_required text,target_reason text)
returns uuid
language plpgsql security invoker
set search_path=public,coordination,engineering,project,audit,auth,pg_temp
as $$
declare item engineering.coordination_matrix%rowtype; approval_id uuid; org_id uuid;
begin
  select * into item from engineering.coordination_matrix where id=target_item_id; if not found then raise exception 'coordination_item_not_found'; end if;
  if auth.uid() is null or not project.can_access_project(item.project_id) then raise exception 'project_access_required'; end if;
  if item.state not in ('open','coordinating') then raise exception 'deviation_request_requires_open_coordination_item'; end if;
  if nullif(btrim(target_role_required),'') is null then raise exception 'professional_role_required_for_deviation'; end if;
  if nullif(btrim(target_reason),'') is null then raise exception 'deviation_reason_required'; end if;
  approval_id:=public.request_governed_approval(jsonb_build_object('project_id',item.project_id,'resource_type','change','resource_id',item.id,'role_required',lower(btrim(target_role_required)),'criticality',item.criticality,'comments','Accepted-deviation review for exact coordination hash '||item.coordination_hash||'. '||btrim(target_reason)));
  select organisation_id into org_id from project.projects where id=item.project_id;
  perform set_config('conceptspaces.coordination_phase','request_deviation',true);
  insert into engineering.coordination_matrix_events(coordination_item_id,project_id,actor_id,event_type,reason,evidence_refs,snapshot)
  values(item.id,item.project_id,auth.uid(),'deviation_requested',btrim(target_reason),jsonb_build_array(approval_id::text),jsonb_build_object('approval_id',approval_id,'coordination_hash',item.coordination_hash));
  perform audit.append_event(org_id,item.project_id,'coordination.matrix.deviation_requested','coordination_matrix',item.id,to_jsonb(item),jsonb_build_object('approval_id',approval_id,'coordination_hash',item.coordination_hash),btrim(target_reason),gen_random_uuid());
  return approval_id;
end;$$;
revoke all on function public.request_coordination_deviation_approval(uuid,text,text) from public,anon;
grant execute on function public.request_coordination_deviation_approval(uuid,text,text) to authenticated;

create or replace function public.transition_coordination_matrix_item(target_item_id uuid,target_state text,target_reason text,target_evidence_refs jsonb default '[]'::jsonb)
returns void
language plpgsql security invoker
set search_path=public,coordination,engineering,project,audit,auth,pg_temp
as $$
declare item engineering.coordination_matrix%rowtype; before_item jsonb; next_state text:=lower(btrim(target_state)); approval coordination.approval_requests%rowtype; org_id uuid; event_value text;
begin
  select * into item from engineering.coordination_matrix where id=target_item_id for update; if not found then raise exception 'coordination_item_not_found'; end if;
  if auth.uid() is null or not project.can_access_project(item.project_id) then raise exception 'project_access_required'; end if;
  if next_state not in ('open','coordinating','resolved','accepted_deviation') then raise exception 'unsupported_coordination_state'; end if;
  if next_state=item.state then raise exception 'coordination_state_unchanged'; end if;
  if nullif(btrim(target_reason),'') is null then raise exception 'coordination_transition_reason_required'; end if;
  if jsonb_typeof(coalesce(target_evidence_refs,'[]'::jsonb))<>'array' then raise exception 'coordination_evidence_refs_must_be_array'; end if;
  if item.state='open' and next_state not in ('coordinating','resolved','accepted_deviation') then raise exception 'invalid_coordination_transition'; end if;
  if item.state='coordinating' and next_state not in ('open','resolved','accepted_deviation') then raise exception 'invalid_coordination_transition'; end if;
  if item.state in ('resolved','accepted_deviation') and next_state<>'open' then raise exception 'resolved_coordination_can_only_reopen'; end if;
  if next_state='resolved' and jsonb_array_length(coalesce(target_evidence_refs,'[]'::jsonb))=0 then raise exception 'resolution_evidence_required'; end if;
  if next_state='accepted_deviation' then
    select * into approval from coordination.approval_requests a
    where a.project_id=item.project_id and a.resource_type='change' and a.resource_id=item.id
      and a.decision in ('approved','approved_with_comments') and a.decision_evidence_hash=item.coordination_hash
    order by a.decided_at desc limit 1;
    if not found or approval.decided_by is null then raise exception 'matching_governed_deviation_approval_required'; end if;
  end if;
  before_item:=to_jsonb(item); select organisation_id into org_id from project.projects where id=item.project_id;
  perform set_config('conceptspaces.coordination_phase','transition',true);
  update engineering.coordination_matrix set state=next_state,resolution_note=case when next_state in ('resolved','accepted_deviation') then btrim(target_reason) else null end,
    resolution_evidence_refs=case when next_state in ('resolved','accepted_deviation') then coalesce(target_evidence_refs,'[]'::jsonb) else '[]'::jsonb end,
    accepted_deviation_approval_id=case when next_state='accepted_deviation' then approval.id else null end,
    resolved_by=case when next_state in ('resolved','accepted_deviation') then auth.uid() else null end,resolved_at=case when next_state in ('resolved','accepted_deviation') then now() else null end,updated_at=now()
  where id=item.id returning * into item;
  update coordination.issues set status=case when next_state='open' then 'open' when next_state='coordinating' then 'in_progress' else 'resolved' end,assignee_id=item.owner_user_id,updated_at=now(),closed_at=null where id=item.issue_id;
  insert into coordination.issue_comments(issue_id,body,author_id,evidence_refs) values(item.issue_id,btrim(target_reason),auth.uid(),coalesce(target_evidence_refs,'[]'::jsonb));
  event_value:=case when next_state='open' then 'reopened' else next_state end;
  insert into engineering.coordination_matrix_events(coordination_item_id,project_id,actor_id,event_type,reason,evidence_refs,snapshot) values(item.id,item.project_id,auth.uid(),event_value,btrim(target_reason),coalesce(target_evidence_refs,'[]'::jsonb),to_jsonb(item));
  perform audit.append_event(org_id,item.project_id,'coordination.matrix.'||event_value,'coordination_matrix',item.id,before_item,to_jsonb(item),btrim(target_reason),gen_random_uuid());
end;$$;
revoke all on function public.transition_coordination_matrix_item(uuid,text,text,jsonb) from public,anon;
grant execute on function public.transition_coordination_matrix_item(uuid,text,text,jsonb) to authenticated;

create or replace function public.transition_coordination_issue(target_issue_id uuid,new_status text,resolution_note text default null)
returns void
language plpgsql security invoker
set search_path=coordination,engineering,project,audit,public
as $$
declare i coordination.issues%rowtype; matrix_item engineering.coordination_matrix%rowtype; before_state jsonb; org_id uuid; next_status text:=lower(btrim(new_status));
begin
  select * into i from coordination.issues where id=target_issue_id; if not found then raise exception 'issue_not_found'; end if;
  if not project.can_access_project(i.project_id) then raise exception 'project_access_required'; end if;
  if next_status not in ('open','in_progress','answered','resolved','closed') then raise exception 'unsupported_issue_status'; end if;
  if i.status='closed' then raise exception 'closed_issue_is_terminal'; end if;
  select * into matrix_item from engineering.coordination_matrix m where m.issue_id=i.id;
  if found and next_status in ('resolved','closed') and matrix_item.state not in ('resolved','accepted_deviation') then raise exception 'coordination_matrix_resolution_required_before_issue_resolution'; end if;
  if next_status='closed' and nullif(btrim(resolution_note),'') is null then raise exception 'closure_note_required'; end if;
  select organisation_id into org_id from project.projects where id=i.project_id; before_state:=to_jsonb(i);
  update coordination.issues set status=next_status,closed_at=case when next_status='closed' then now() else null end,updated_at=now() where id=i.id returning * into i;
  if nullif(btrim(resolution_note),'') is not null then insert into coordination.issue_comments(issue_id,body,author_id,evidence_refs) values(i.id,btrim(resolution_note),auth.uid(),'[]'::jsonb); end if;
  perform audit.append_event(org_id,i.project_id,'coordination.issue.'||next_status,'issue',i.id,before_state,to_jsonb(i),resolution_note,gen_random_uuid());
end;$$;

create or replace function public.list_coordination_matrix_workspace()
returns jsonb
language plpgsql stable security invoker
set search_path=public,coordination,engineering,project,cde,aec,governance,auth,pg_temp
as $$
begin
  if auth.uid() is null then raise exception 'authentication_required'; end if;
  return jsonb_build_object(
    'items',coalesce((select jsonb_agg(jsonb_build_object(
      'id',m.id,'project_id',m.project_id,'project_code',p.code::text,'project_name',p.name,'issue_id',m.issue_id,'issue_number',i.issue_number::text,'issue_status',i.status,'priority',i.priority,
      'source_discipline',m.source_discipline,'target_discipline',m.target_discipline,'subject',m.subject,'requirement_ref',m.requirement_ref,'state',m.state,'criticality',m.criticality,'owner_user_id',m.owner_user_id,
      'source_resource',coordination.resource_snapshot(m.project_id,m.source_resource_type,m.source_resource_id),'target_resource',coordination.resource_snapshot(m.project_id,m.target_resource_type,m.target_resource_id),
      'coordination_hash',m.coordination_hash,'resolution_note',m.resolution_note,'resolution_evidence_refs',m.resolution_evidence_refs,'accepted_deviation_approval_id',m.accepted_deviation_approval_id,'created_by',m.created_by,'resolved_by',m.resolved_by,'resolved_at',m.resolved_at,'created_at',m.created_at,'updated_at',m.updated_at
    ) order by case m.state when 'open' then 0 when 'coordinating' then 1 else 2 end,engineering.criticality_rank(m.criticality) desc,m.updated_at desc) from engineering.coordination_matrix m join project.projects p on p.id=m.project_id join coordination.issues i on i.id=m.issue_id where project.can_access_project(m.project_id)),'[]'::jsonb),
    'events',coalesce((select jsonb_agg(to_jsonb(e) order by e.created_at desc) from engineering.coordination_matrix_events e where project.can_access_project(e.project_id)),'[]'::jsonb),
    'approvals',coalesce((select jsonb_agg(to_jsonb(a) order by a.requested_at desc) from coordination.approval_requests a where a.resource_type='change' and exists(select 1 from engineering.coordination_matrix m where m.id=a.resource_id and project.can_access_project(m.project_id))),'[]'::jsonb),
    'documents',coalesce((select jsonb_agg(jsonb_build_object('id',d.id,'project_id',d.project_id,'label',d.document_number::text||' · '||d.title||' · '||d.revision,'hash',v.checksum,'discipline',d.discipline,'status',d.status) order by d.updated_at desc) from cde.documents d join cde.file_versions v on v.id=d.current_version_id where project.can_access_project(d.project_id)),'[]'::jsonb),
    'models',coalesce((select jsonb_agg(jsonb_build_object('id',m.id,'project_id',m.project_id,'label',m.model_name||' · '||upper(m.discipline)||' · '||upper(m.format),'hash',m.checksum,'discipline',m.discipline,'status',m.status,'schema_version',m.schema_version,'coordinate_system',m.coordinate_system) order by m.updated_at desc) from cde.models m where project.can_access_project(m.project_id)),'[]'::jsonb),
    'requirements',coalesce((select jsonb_agg(jsonb_build_object('id',r.id,'project_id',r.project_id,'label',r.code::text||' · '||r.statement,'status',r.status,'criticality',r.criticality) order by r.updated_at desc) from project.requirements r where project.can_access_project(r.project_id)),'[]'::jsonb),
    'truth_records',coalesce((select jsonb_agg(jsonb_build_object('id',t.id,'project_id',t.project_id,'label',t.record_key,'status',t.status,'criticality',t.criticality,'confidence',t.confidence) order by t.updated_at desc) from project.truth_records t where t.status<>'superseded' and project.can_access_project(t.project_id)),'[]'::jsonb),
    'releases',coalesce((select jsonb_agg(jsonb_build_object('id',s.id,'project_id',s.project_id,'label',coalesce(s.package_reference,s.package_type),'state',s.state,'hash',s.content_hash) order by s.updated_at desc) from governance.release_safety_cases s where project.can_access_project(s.project_id)),'[]'::jsonb),
    'members',coalesce((select jsonb_agg(jsonb_build_object('project_id',pm.project_id,'user_id',pm.user_id,'role_code',pm.role_code,'discipline',pm.discipline,'status',pm.status) order by pm.project_id,pm.role_code) from project.project_members pm where pm.status='active' and project.can_access_project(pm.project_id)),'[]'::jsonb)
  );
end;$$;
revoke all on function public.list_coordination_matrix_workspace() from public,anon;
grant execute on function public.list_coordination_matrix_workspace() to authenticated;

commit;
