begin;

alter table engineering.coordination_matrix_events drop constraint if exists coordination_matrix_events_event_type_check;
alter table engineering.coordination_matrix_events add constraint coordination_matrix_events_event_type_check check (event_type in ('raised','owner_changed','coordinating','resolved','deviation_requested','accepted_deviation','reopened','resources_refreshed'));

drop policy if exists coordination_matrix_governed_update on engineering.coordination_matrix;
create policy coordination_matrix_governed_update on engineering.coordination_matrix
for update to authenticated
using ((select current_setting('conceptspaces.coordination_phase',true)) in ('transition','assign','request_deviation','refresh') and project.can_access_project(project_id))
with check ((select current_setting('conceptspaces.coordination_phase',true)) in ('transition','assign','request_deviation','refresh') and project.can_access_project(project_id));

create or replace function engineering.coordination_item_resources_current(target_item_id uuid)
returns boolean
language plpgsql stable security invoker
set search_path=engineering,coordination,public,pg_temp
as $$
declare item engineering.coordination_matrix%rowtype; source_now jsonb; target_now jsonb;
begin
  select * into item from engineering.coordination_matrix where id=target_item_id;
  if not found then return false; end if;
  begin
    source_now:=coordination.resource_snapshot(item.project_id,item.source_resource_type,item.source_resource_id);
    target_now:=coordination.resource_snapshot(item.project_id,item.target_resource_type,item.target_resource_id);
  exception when others then
    return false;
  end;
  if item.source_resource_id is not null and item.source_resource_hash is distinct from source_now->>'hash' then return false; end if;
  if item.target_resource_id is not null and item.target_resource_hash is distinct from target_now->>'hash' then return false; end if;
  return true;
end;$$;
revoke all on function engineering.coordination_item_resources_current(uuid) from public,anon;
grant execute on function engineering.coordination_item_resources_current(uuid) to authenticated;

create or replace function public.refresh_coordination_matrix_resources(target_item_id uuid,target_reason text)
returns void
language plpgsql security invoker
set search_path=public,coordination,engineering,project,audit,extensions,auth,pg_temp
as $$
declare item engineering.coordination_matrix%rowtype; before_item jsonb; source_now jsonb; target_now jsonb; hash_payload jsonb; next_hash text; org_id uuid;
begin
  select * into item from engineering.coordination_matrix where id=target_item_id for update; if not found then raise exception 'coordination_item_not_found'; end if;
  if auth.uid() is null or not project.can_access_project(item.project_id) then raise exception 'project_access_required'; end if;
  if nullif(btrim(target_reason),'') is null then raise exception 'resource_refresh_reason_required'; end if;
  source_now:=coordination.resource_snapshot(item.project_id,item.source_resource_type,item.source_resource_id);
  target_now:=coordination.resource_snapshot(item.project_id,item.target_resource_type,item.target_resource_id);
  if item.source_resource_hash is not distinct from source_now->>'hash' and item.target_resource_hash is not distinct from target_now->>'hash' then raise exception 'coordination_resources_already_current'; end if;
  hash_payload:=jsonb_build_object('project_id',item.project_id,'issue_id',item.issue_id,'source_discipline',item.source_discipline,'target_discipline',item.target_discipline,'subject',item.subject,'criticality',item.criticality,'source_resource',source_now,'target_resource',target_now);
  next_hash:=encode(extensions.digest(hash_payload::text,'sha256'),'hex'); before_item:=to_jsonb(item); select organisation_id into org_id from project.projects where id=item.project_id;
  perform set_config('conceptspaces.coordination_phase','refresh',true);
  update engineering.coordination_matrix set source_resource_hash=source_now->>'hash',target_resource_hash=target_now->>'hash',coordination_hash=next_hash,state='open',resolution_note=null,resolution_evidence_refs='[]'::jsonb,accepted_deviation_approval_id=null,resolved_by=null,resolved_at=null,updated_at=now() where id=item.id returning * into item;
  update coordination.issues set status='open',closed_at=null,updated_at=now() where id=item.issue_id;
  insert into coordination.issue_comments(issue_id,body,author_id,evidence_refs) values(item.issue_id,'Resource baseline refreshed. '||btrim(target_reason),auth.uid(),jsonb_build_array(source_now,target_now));
  insert into engineering.coordination_matrix_events(coordination_item_id,project_id,actor_id,event_type,reason,evidence_refs,snapshot) values(item.id,item.project_id,auth.uid(),'resources_refreshed',btrim(target_reason),jsonb_build_array(source_now,target_now),to_jsonb(item));
  perform audit.append_event(org_id,item.project_id,'coordination.matrix.resources_refreshed','coordination_matrix',item.id,before_item,to_jsonb(item),btrim(target_reason),gen_random_uuid());
end;$$;
revoke all on function public.refresh_coordination_matrix_resources(uuid,text) from public,anon;
grant execute on function public.refresh_coordination_matrix_resources(uuid,text) to authenticated;

-- Replace the transition function with a resource-freshness gate before any positive coordination state.
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
  if next_state in ('coordinating','resolved','accepted_deviation') and not engineering.coordination_item_resources_current(item.id) then raise exception 'coordination_resources_changed_refresh_baseline_required'; end if;
  if next_state='resolved' and jsonb_array_length(coalesce(target_evidence_refs,'[]'::jsonb))=0 then raise exception 'resolution_evidence_required'; end if;
  if next_state='accepted_deviation' then
    select * into approval from coordination.approval_requests a where a.project_id=item.project_id and a.resource_type='change' and a.resource_id=item.id and a.decision in ('approved','approved_with_comments') and a.decision_evidence_hash=item.coordination_hash order by a.decided_at desc limit 1;
    if not found or approval.decided_by is null then raise exception 'matching_governed_deviation_approval_required'; end if;
  end if;
  before_item:=to_jsonb(item); select organisation_id into org_id from project.projects where id=item.project_id;
  perform set_config('conceptspaces.coordination_phase','transition',true);
  update engineering.coordination_matrix set state=next_state,resolution_note=case when next_state in ('resolved','accepted_deviation') then btrim(target_reason) else null end,resolution_evidence_refs=case when next_state in ('resolved','accepted_deviation') then coalesce(target_evidence_refs,'[]'::jsonb) else '[]'::jsonb end,accepted_deviation_approval_id=case when next_state='accepted_deviation' then approval.id else null end,resolved_by=case when next_state in ('resolved','accepted_deviation') then auth.uid() else null end,resolved_at=case when next_state in ('resolved','accepted_deviation') then now() else null end,updated_at=now() where id=item.id returning * into item;
  update coordination.issues set status=case when next_state='open' then 'open' when next_state='coordinating' then 'in_progress' else 'resolved' end,assignee_id=item.owner_user_id,updated_at=now(),closed_at=null where id=item.issue_id;
  insert into coordination.issue_comments(issue_id,body,author_id,evidence_refs) values(item.issue_id,btrim(target_reason),auth.uid(),coalesce(target_evidence_refs,'[]'::jsonb));
  event_value:=case when next_state='open' then 'reopened' else next_state end;
  insert into engineering.coordination_matrix_events(coordination_item_id,project_id,actor_id,event_type,reason,evidence_refs,snapshot) values(item.id,item.project_id,auth.uid(),event_value,btrim(target_reason),coalesce(target_evidence_refs,'[]'::jsonb),to_jsonb(item));
  perform audit.append_event(org_id,item.project_id,'coordination.matrix.'||event_value,'coordination_matrix',item.id,before_item,to_jsonb(item),btrim(target_reason),gen_random_uuid());
end;$$;

-- Any mutation of a linked mutable resource invalidates already-captured release coordination evidence by touching matrix.updated_at.
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
  elsif tg_table_schema='project' and tg_table_name='truth_records' then rtype:='truth_record'; rid:=new.id;
  elsif tg_table_schema='project' and tg_table_name='requirements' then rtype:='requirement'; rid:=new.id;
  elsif tg_table_schema='aec' and tg_table_name='design_options' then rtype:='design_option'; rid:=new.id;
  elsif tg_table_schema='governance' and tg_table_name='release_safety_cases' then rtype:='release'; rid:=new.id;
  else return new;
  end if;
  update engineering.coordination_matrix set updated_at=now() where (source_resource_type=rtype and source_resource_id=rid) or (target_resource_type=rtype and target_resource_id=rid);
  return new;
end;$$;
revoke all on function engineering.touch_linked_coordination_items() from public,anon,authenticated;

drop trigger if exists coordination_touch_document_change on cde.documents;
create trigger coordination_touch_document_change after update of current_version_id on cde.documents for each row execute function engineering.touch_linked_coordination_items();
drop trigger if exists coordination_touch_truth_change on project.truth_records;
create trigger coordination_touch_truth_change after update on project.truth_records for each row execute function engineering.touch_linked_coordination_items();
drop trigger if exists coordination_touch_requirement_change on project.requirements;
create trigger coordination_touch_requirement_change after update on project.requirements for each row execute function engineering.touch_linked_coordination_items();
drop trigger if exists coordination_touch_design_option_change on aec.design_options;
create trigger coordination_touch_design_option_change after update on aec.design_options for each row execute function engineering.touch_linked_coordination_items();
drop trigger if exists coordination_touch_release_change on governance.release_safety_cases;
create trigger coordination_touch_release_change after update of content_hash on governance.release_safety_cases for each row execute function engineering.touch_linked_coordination_items();

-- Release capture now refuses coordination rows whose linked resource hashes are stale.
create or replace function public.capture_release_coordination_check(target_safety_case_id uuid,target_reason text)
returns uuid
language plpgsql security invoker
set search_path=public,governance,project,engineering,coordination,extensions,auth,pg_temp
as $$
declare s governance.release_safety_cases%rowtype; snapshot jsonb; snapshot_hash text; new_id uuid;
begin
  select * into s from governance.release_safety_cases where id=target_safety_case_id;
  if not found then raise exception 'release_safety_case_not_found'; end if;
  if auth.uid() is null or not project.can_manage_project(s.project_id) then raise exception 'project_manage_authority_required'; end if;
  if exists(select 1 from engineering.coordination_matrix c where c.project_id=s.project_id and c.state in ('open','coordinating')) then raise exception 'open_coordination_items_block_release'; end if;
  if exists(select 1 from engineering.coordination_matrix c where c.project_id=s.project_id and not engineering.coordination_item_resources_current(c.id)) then raise exception 'stale_coordination_resource_baseline_blocks_release'; end if;
  select coalesce(jsonb_agg(jsonb_build_object('id',c.id,'issue_id',c.issue_id,'source_discipline',c.source_discipline,'target_discipline',c.target_discipline,'subject',c.subject,'state',c.state,'criticality',c.criticality,'coordination_hash',c.coordination_hash,'source_resource_type',c.source_resource_type,'source_resource_id',c.source_resource_id,'source_resource_hash',c.source_resource_hash,'target_resource_type',c.target_resource_type,'target_resource_id',c.target_resource_id,'target_resource_hash',c.target_resource_hash,'resolution_evidence_refs',c.resolution_evidence_refs,'accepted_deviation_approval_id',c.accepted_deviation_approval_id,'updated_at',c.updated_at) order by c.id),'[]'::jsonb)
    into snapshot from engineering.coordination_matrix c where c.project_id=s.project_id;
  snapshot_hash:=encode(extensions.digest(snapshot::text,'sha256'),'hex');
  perform set_config('conceptspaces.release_capture','coordination_check',true);
  new_id:=public.add_release_evidence(s.id,'coordination_check','coordination_matrix:'||s.project_id::text,snapshot_hash,true,jsonb_build_object('item_count',jsonb_array_length(snapshot),'snapshot_hash',snapshot_hash,'all_linked_resources_current',true),coalesce(nullif(btrim(target_reason),''),'Captured resolved current coordination state'));
  return new_id;
end;$$;

-- Replace workspace list so displayed resources show captured-vs-current hash freshness.
create or replace function public.list_coordination_matrix_workspace()
returns jsonb
language plpgsql stable security invoker
set search_path=public,coordination,engineering,project,cde,aec,governance,auth,pg_temp
as $$
begin
  if auth.uid() is null then raise exception 'authentication_required'; end if;
  return jsonb_build_object(
    'items',coalesce((select jsonb_agg(jsonb_build_object(
      'id',m.id,'project_id',m.project_id,'project_code',p.code::text,'project_name',p.name,'issue_id',m.issue_id,'issue_number',i.issue_number::text,'issue_status',i.status,'priority',i.priority,'source_discipline',m.source_discipline,'target_discipline',m.target_discipline,'subject',m.subject,'requirement_ref',m.requirement_ref,'state',m.state,'criticality',m.criticality,'owner_user_id',m.owner_user_id,
      'source_resource',case when m.source_resource_id is null then null else coordination.resource_snapshot(m.project_id,m.source_resource_type,m.source_resource_id)||jsonb_build_object('captured_hash',m.source_resource_hash,'fresh',(coordination.resource_snapshot(m.project_id,m.source_resource_type,m.source_resource_id)->>'hash')=m.source_resource_hash) end,
      'target_resource',case when m.target_resource_id is null then null else coordination.resource_snapshot(m.project_id,m.target_resource_type,m.target_resource_id)||jsonb_build_object('captured_hash',m.target_resource_hash,'fresh',(coordination.resource_snapshot(m.project_id,m.target_resource_type,m.target_resource_id)->>'hash')=m.target_resource_hash) end,
      'resources_current',engineering.coordination_item_resources_current(m.id),'coordination_hash',m.coordination_hash,'resolution_note',m.resolution_note,'resolution_evidence_refs',m.resolution_evidence_refs,'accepted_deviation_approval_id',m.accepted_deviation_approval_id,'created_by',m.created_by,'resolved_by',m.resolved_by,'resolved_at',m.resolved_at,'created_at',m.created_at,'updated_at',m.updated_at
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

commit;
