begin;

-- Coordination matrix rows are only valid when both sides are bound to an exact resource baseline.
alter table engineering.coordination_matrix drop constraint if exists coordination_matrix_source_baseline_required;
alter table engineering.coordination_matrix add constraint coordination_matrix_source_baseline_required
  check (source_resource_type is not null and source_resource_id is not null and nullif(source_resource_hash,'') is not null);
alter table engineering.coordination_matrix drop constraint if exists coordination_matrix_target_baseline_required;
alter table engineering.coordination_matrix add constraint coordination_matrix_target_baseline_required
  check (target_resource_type is not null and target_resource_id is not null and nullif(target_resource_hash,'') is not null);
alter table engineering.coordination_matrix drop constraint if exists coordination_matrix_governance_identity_required;
alter table engineering.coordination_matrix add constraint coordination_matrix_governance_identity_required
  check (issue_id is not null and nullif(coordination_hash,'') is not null);

-- Workspace reads must fail closed to a stale/missing resource state rather than throwing the whole page.
-- Strict mutation paths use require_resource_snapshot below.
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

  if result is null then
    return jsonb_build_object(
      'type',rtype,'id',target_resource_id,
      'label','Unavailable / superseded '||replace(rtype,'_',' '),
      'hash','', 'missing',true
    );
  end if;
  if nullif(result->>'hash','') is null then
    return result||jsonb_build_object('hash','', 'missing',true);
  end if;
  return result||jsonb_build_object('missing',false);
end;$$;
revoke all on function coordination.resource_snapshot(uuid,text,uuid) from public,anon;
grant execute on function coordination.resource_snapshot(uuid,text,uuid) to authenticated;

create or replace function coordination.require_resource_snapshot(
  target_project_id uuid,target_resource_type text,target_resource_id uuid
) returns jsonb
language plpgsql stable security invoker
set search_path=coordination,public,pg_temp
as $$
declare result jsonb;
begin
  result:=coordination.resource_snapshot(target_project_id,target_resource_type,target_resource_id);
  if result is null then raise exception 'coordination_resource_required'; end if;
  if coalesce((result->>'missing')::boolean,false) or nullif(result->>'hash','') is null then
    raise exception 'coordination_resource_not_found_or_superseded';
  end if;
  return result;
end;$$;
revoke all on function coordination.require_resource_snapshot(uuid,text,uuid) from public,anon;
grant execute on function coordination.require_resource_snapshot(uuid,text,uuid) to authenticated;

-- Re-baseline may keep the same resource IDs (new hash) or replace one/both resources when an old baseline is superseded.
create or replace function public.rebaseline_coordination_matrix_resources(target_item_id uuid,input_payload jsonb)
returns void
language plpgsql security invoker
set search_path=public,coordination,engineering,project,audit,extensions,auth,pg_temp
as $$
declare
  item engineering.coordination_matrix%rowtype;
  before_item jsonb;
  payload jsonb:=coalesce(input_payload,'{}'::jsonb);
  source_type_value text;
  target_type_value text;
  source_id_value uuid;
  target_id_value uuid;
  source_now jsonb;
  target_now jsonb;
  hash_payload jsonb;
  next_hash text;
  org_id uuid;
  reason_value text:=nullif(btrim(coalesce(input_payload->>'reason','')),'');
begin
  select * into item from engineering.coordination_matrix where id=target_item_id for update;
  if not found then raise exception 'coordination_item_not_found'; end if;
  if auth.uid() is null or not project.can_access_project(item.project_id) then raise exception 'project_access_required'; end if;
  if reason_value is null then raise exception 'resource_rebaseline_reason_required'; end if;

  source_type_value:=coalesce(nullif(lower(btrim(payload->>'source_resource_type')),''),item.source_resource_type);
  target_type_value:=coalesce(nullif(lower(btrim(payload->>'target_resource_type')),''),item.target_resource_type);
  source_id_value:=coalesce(nullif(payload->>'source_resource_id','')::uuid,item.source_resource_id);
  target_id_value:=coalesce(nullif(payload->>'target_resource_id','')::uuid,item.target_resource_id);

  source_now:=coordination.require_resource_snapshot(item.project_id,source_type_value,source_id_value);
  target_now:=coordination.require_resource_snapshot(item.project_id,target_type_value,target_id_value);

  if item.source_resource_type is not distinct from source_type_value
     and item.source_resource_id is not distinct from source_id_value
     and item.source_resource_hash is not distinct from source_now->>'hash'
     and item.target_resource_type is not distinct from target_type_value
     and item.target_resource_id is not distinct from target_id_value
     and item.target_resource_hash is not distinct from target_now->>'hash' then
    raise exception 'coordination_resources_already_current';
  end if;

  hash_payload:=jsonb_build_object(
    'project_id',item.project_id,'issue_id',item.issue_id,
    'source_discipline',item.source_discipline,'target_discipline',item.target_discipline,
    'subject',item.subject,'criticality',item.criticality,
    'source_resource',source_now,'target_resource',target_now
  );
  next_hash:=encode(extensions.digest(hash_payload::text,'sha256'),'hex');
  before_item:=to_jsonb(item);
  select organisation_id into org_id from project.projects where id=item.project_id;

  perform set_config('conceptspaces.coordination_phase','refresh',true);
  update engineering.coordination_matrix
  set source_resource_type=source_type_value,
      source_resource_id=source_id_value,
      source_resource_hash=source_now->>'hash',
      target_resource_type=target_type_value,
      target_resource_id=target_id_value,
      target_resource_hash=target_now->>'hash',
      coordination_hash=next_hash,
      state='open',resolution_note=null,resolution_evidence_refs='[]'::jsonb,
      accepted_deviation_approval_id=null,resolved_by=null,resolved_at=null,updated_at=now()
  where id=item.id returning * into item;

  update coordination.issues set status='open',assignee_id=item.owner_user_id,closed_at=null,updated_at=now() where id=item.issue_id;
  insert into coordination.issue_links(issue_id,resource_type,resource_id,relationship)
    values(item.issue_id,source_type_value,source_id_value,'source') on conflict do nothing;
  insert into coordination.issue_links(issue_id,resource_type,resource_id,relationship)
    values(item.issue_id,target_type_value,target_id_value,'target') on conflict do nothing;
  insert into coordination.issue_comments(issue_id,body,author_id,evidence_refs)
    values(item.issue_id,'Coordination resource baseline re-established. '||reason_value,auth.uid(),jsonb_build_array(source_now,target_now));
  insert into engineering.coordination_matrix_events(coordination_item_id,project_id,actor_id,event_type,reason,evidence_refs,snapshot)
    values(item.id,item.project_id,auth.uid(),'resources_refreshed',reason_value,jsonb_build_array(source_now,target_now),to_jsonb(item));
  perform audit.append_event(org_id,item.project_id,'coordination.matrix.resources_refreshed','coordination_matrix',item.id,before_item,to_jsonb(item),reason_value,gen_random_uuid());
end;$$;
revoke all on function public.rebaseline_coordination_matrix_resources(uuid,jsonb) from public,anon;
grant execute on function public.rebaseline_coordination_matrix_resources(uuid,jsonb) to authenticated;

-- Preserve the original refresh API for same-resource hash changes.
create or replace function public.refresh_coordination_matrix_resources(target_item_id uuid,target_reason text)
returns void
language plpgsql security invoker
set search_path=public,pg_temp
as $$
begin
  perform public.rebaseline_coordination_matrix_resources(target_item_id,jsonb_build_object('reason',target_reason));
end;$$;
revoke all on function public.refresh_coordination_matrix_resources(uuid,text) from public,anon;
grant execute on function public.refresh_coordination_matrix_resources(uuid,text) to authenticated;

-- Refresh/replacement is a governed matrix mutation and event/link creation phase.
drop policy if exists coordination_matrix_events_governed_insert on engineering.coordination_matrix_events;
create policy coordination_matrix_events_governed_insert on engineering.coordination_matrix_events
for insert to authenticated with check (
  project.can_access_project(project_id)
  and actor_id=(select auth.uid())
  and (select current_setting('conceptspaces.coordination_phase',true)) in ('raise','transition','assign','request_deviation','refresh')
);

drop policy if exists issue_links_coordination_insert on coordination.issue_links;
create policy issue_links_coordination_insert on coordination.issue_links
for insert to authenticated with check (
  (select current_setting('conceptspaces.coordination_phase',true)) in ('raise','refresh')
  and exists(select 1 from coordination.issues i where i.id=issue_id and project.can_access_project(i.project_id))
);

-- Do not create a professional deviation review against an already-stale coordination hash.
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
  if not engineering.coordination_item_resources_current(item.id) then raise exception 'coordination_resources_changed_rebaseline_required'; end if;
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

-- A linked issue cannot be resolved/closed while its matrix baseline is stale.
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
  if found and next_status in ('resolved','closed') then
    if matrix_item.state not in ('resolved','accepted_deviation') then raise exception 'coordination_matrix_resolution_required_before_issue_resolution'; end if;
    if not engineering.coordination_item_resources_current(matrix_item.id) then raise exception 'stale_coordination_baseline_blocks_issue_resolution'; end if;
  end if;
  if next_status='closed' and nullif(btrim(resolution_note),'') is null then raise exception 'closure_note_required'; end if;
  select organisation_id into org_id from project.projects where id=i.project_id; before_state:=to_jsonb(i);
  update coordination.issues set status=next_status,closed_at=case when next_status='closed' then now() else null end,updated_at=now() where id=i.id returning * into i;
  if nullif(btrim(resolution_note),'') is not null then insert into coordination.issue_comments(issue_id,body,author_id,evidence_refs) values(i.id,btrim(resolution_note),auth.uid(),'[]'::jsonb); end if;
  perform audit.append_event(org_id,i.project_id,'coordination.issue.'||next_status,'issue',i.id,before_state,to_jsonb(i),resolution_note,gen_random_uuid());
end;$$;
revoke all on function public.transition_coordination_issue(uuid,text,text) from public,anon;
grant execute on function public.transition_coordination_issue(uuid,text,text) to authenticated;

-- Model checksum changes must invalidate coordination freshness exactly like new document versions and truth changes.
create or replace function engineering.touch_linked_coordination_items()
returns trigger
language plpgsql security definer
set search_path=engineering,public,pg_temp
as $$
declare rtype text; rid uuid;
begin
  if tg_table_schema='cde' and tg_table_name='documents' then
    if tg_op='UPDATE' and new.current_version_id is not distinct from old.current_version_id then return new; end if;
    rtype:='document'; rid:=new.id;
  elsif tg_table_schema='cde' and tg_table_name='models' then
    if tg_op='UPDATE' and new.checksum is not distinct from old.checksum then return new; end if;
    rtype:='model'; rid:=new.id;
  elsif tg_table_schema='project' and tg_table_name='truth_records' then rtype:='truth_record'; rid:=new.id;
  elsif tg_table_schema='project' and tg_table_name='requirements' then rtype:='requirement'; rid:=new.id;
  elsif tg_table_schema='aec' and tg_table_name='design_options' then rtype:='design_option'; rid:=new.id;
  elsif tg_table_schema='governance' and tg_table_name='release_safety_cases' then rtype:='release'; rid:=new.id;
  else return new;
  end if;
  update engineering.coordination_matrix set updated_at=now()
    where (source_resource_type=rtype and source_resource_id=rid) or (target_resource_type=rtype and target_resource_id=rid);
  return new;
end;$$;
revoke all on function engineering.touch_linked_coordination_items() from public,anon,authenticated;

drop trigger if exists coordination_touch_model_change on cde.models;
create trigger coordination_touch_model_change after update of checksum on cde.models
for each row execute function engineering.touch_linked_coordination_items();

commit;
