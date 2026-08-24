begin;

alter table coordination.approval_requests
  add column if not exists requested_resource_hash text;

create or replace function coordination.current_approval_resource_hash(
  target_project_id uuid,
  target_resource_type text,
  target_resource_id uuid
)
returns text
language plpgsql
stable
security definer
set search_path='coordination','cde','governance','aec','engineering','configuration','public','pg_temp'
as $$
declare
  h text;
  change_row public.project_change_requests%rowtype;
begin
  case lower(btrim(target_resource_type))
    when 'document' then
      select fv.checksum
        into h
      from cde.documents d
      join cde.file_versions fv on fv.id=d.current_version_id
      where d.id=target_resource_id
        and d.project_id=target_project_id
        and d.status not in ('superseded','withdrawn');

    when 'model' then
      select m.checksum
        into h
      from cde.models m
      where m.id=target_resource_id
        and m.project_id=target_project_id
        and m.status<>'superseded';

    when 'design_option' then
      select encode(extensions.digest((to_jsonb(o)-array['updated_at'])::text,'sha256'),'hex')
        into h
      from aec.design_options o
      where o.id=target_resource_id
        and o.project_id=target_project_id
        and o.status<>'superseded';

    when 'release' then
      select r.content_hash
        into h
      from governance.release_safety_cases r
      where r.id=target_resource_id
        and r.project_id=target_project_id;

    when 'commercial' then
      select coalesce(c.execution_hash,c.draft_hash,encode(extensions.digest((to_jsonb(c)-array['updated_at'])::text,'sha256'),'hex'))
        into h
      from public.contracts c
      where c.id=target_resource_id
        and c.project_id=target_project_id
        and c.status not in ('terminated','superseded')
      limit 1;

      if h is null then
        select coalesce(p.accepted_scope_hash,p.scope_hash,encode(extensions.digest((to_jsonb(p)-array['updated_at'])::text,'sha256'),'hex'))
          into h
        from public.proposals p
        where p.id=target_resource_id
          and p.status in ('sent','countered','accepted')
          and exists(
            select 1
            from public.contracts c
            where c.project_id=target_project_id
              and c.proposal_id=p.id
          )
        limit 1;
      end if;

    when 'change' then
      select *
        into change_row
      from public.project_change_requests cr
      where cr.id=target_resource_id
        and cr.project_id=target_project_id
        and cr.status in ('analyzed','approval_pending');

      if found then
        if configuration.assert_change_analysis_current(change_row.id) then
          select ci.analysis_hash
            into h
          from public.change_impacts ci
          where ci.id=change_row.latest_impact_id
            and ci.project_id=target_project_id
            and ci.analysis_state='final';
        end if;
      else
        select cm.coordination_hash
          into h
        from engineering.coordination_matrix cm
        where cm.id=target_resource_id
          and cm.project_id=target_project_id
          and cm.state in ('open','coordinating')
          and engineering.coordination_item_resources_current(cm.id);
      end if;

    else
      h:=null;
  end case;

  return nullif(h,'');
end;
$$;
revoke all on function coordination.current_approval_resource_hash(uuid,text,uuid) from public,anon,authenticated;

create or replace function public.request_governed_approval(input_payload jsonb)
returns uuid
language plpgsql
security invoker
set search_path='coordination','project','public','audit','auth','pg_temp'
as $$
declare
  project_id_value uuid:=nullif(input_payload->>'project_id','')::uuid;
  resource_id_value uuid:=nullif(input_payload->>'resource_id','')::uuid;
  resource_type_value text:=lower(btrim(input_payload->>'resource_type'));
  criticality_value text:=upper(coalesce(nullif(btrim(input_payload->>'criticality'),''),'C1'));
  resource_hash_value text;
  org_id uuid;
  approval coordination.approval_requests%rowtype;
begin
  if project_id_value is null or resource_id_value is null then
    raise exception 'project_and_resource_required';
  end if;
  if auth.uid() is null or not project.can_access_project(project_id_value) then
    raise exception 'project_access_required';
  end if;
  if resource_type_value not in ('document','model','design_option','release','commercial','change') then
    raise exception 'unsupported_approval_resource_type';
  end if;
  if criticality_value not in ('C0','C1','C2','C3','C4') then
    raise exception 'unsupported_criticality';
  end if;

  resource_hash_value:=coordination.current_approval_resource_hash(project_id_value,resource_type_value,resource_id_value);
  if resource_hash_value is null then
    raise exception 'approval_resource_not_current_or_hash_unavailable';
  end if;

  select organisation_id into org_id from project.projects where id=project_id_value;
  insert into coordination.approval_requests(
    project_id,resource_type,resource_id,requested_resource_hash,requested_from,
    role_required,criticality,decision,comments,requested_by
  ) values (
    project_id_value,resource_type_value,resource_id_value,resource_hash_value,
    nullif(input_payload->>'requested_from','')::uuid,
    nullif(lower(btrim(input_payload->>'role_required')),''),criticality_value,
    'pending',nullif(btrim(input_payload->>'comments'),''),auth.uid()
  ) returning * into approval;

  perform audit.append_event(
    org_id,project_id_value,'approval.requested','approval_request',approval.id,
    null,to_jsonb(approval),resource_hash_value,gen_random_uuid()
  );
  return approval.id;
end;
$$;
revoke all on function public.request_governed_approval(jsonb) from public,anon;
grant execute on function public.request_governed_approval(jsonb) to authenticated;

create or replace function public.decide_governed_approval(
  target_approval_id uuid,
  new_decision text,
  decision_comments text,
  reviewed_resource_hash text
)
returns void
language plpgsql
security invoker
set search_path='coordination','project','core','public','audit','auth','pg_temp'
as $$
declare
  approval coordination.approval_requests%rowtype;
  org_id uuid;
  before_state jsonb;
  decision_value text:=lower(btrim(new_decision));
  role_ok boolean:=false;
  current_hash text;
begin
  if decision_value not in ('approved','approved_with_comments','rejected') then
    raise exception 'unsupported_approval_decision';
  end if;

  select * into approval
  from coordination.approval_requests
  where id=target_approval_id
  for update;
  if not found then raise exception 'approval_not_found'; end if;
  if approval.decision<>'pending' then raise exception 'approval_already_decided'; end if;
  if auth.uid() is null or not project.can_access_project(approval.project_id) then
    raise exception 'project_access_required';
  end if;
  if approval.requested_resource_hash is null then
    raise exception 'APPROVAL_UNPINNED_LEGACY_REREQUEST_REQUIRED';
  end if;
  if approval.requested_by=auth.uid() and approval.criticality in ('C2','C3','C4') then
    raise exception 'maker_cannot_approve_own_controlled_action';
  end if;
  if approval.requested_from is not null and approval.requested_from<>auth.uid() then
    raise exception 'approval_not_assigned_to_current_user';
  end if;
  if nullif(btrim(reviewed_resource_hash),'') is null
     or btrim(reviewed_resource_hash)<>approval.requested_resource_hash then
    raise exception 'REVIEWED_RESOURCE_HASH_MISMATCH';
  end if;

  current_hash:=coordination.current_approval_resource_hash(
    approval.project_id,approval.resource_type,approval.resource_id
  );
  if current_hash is null or current_hash<>approval.requested_resource_hash then
    raise exception 'APPROVAL_VERSION_STALE';
  end if;

  if approval.role_required is null then
    role_ok:=true;
  else
    role_ok:=exists(
      select 1 from project.project_members pm
      where pm.project_id=approval.project_id
        and pm.user_id=auth.uid()
        and pm.status='active'
        and pm.role_code=approval.role_required
    ) or exists(
      select 1 from project.projects p
      where p.id=approval.project_id
        and core.has_org_role(p.organisation_id,array[approval.role_required,'super_admin','org_admin'])
    );
  end if;
  if not role_ok then raise exception 'approval_role_authority_required'; end if;

  if approval.criticality in ('C3','C4') then
    if approval.role_required not in ('lead_architect','architect','structural_engineer','mep_engineer','quantity_surveyor','regulatory_reviewer') then
      raise exception 'professional_role_required_for_c3_c4';
    end if;
    if not core.has_verified_professional_eligibility(auth.uid(),approval.role_required) then
      raise exception 'verified_professional_eligibility_required';
    end if;
  end if;

  select organisation_id into org_id from project.projects where id=approval.project_id;
  before_state:=to_jsonb(approval);
  update coordination.approval_requests
  set decision=decision_value,
      comments=decision_comments,
      decided_at=now(),
      decided_by=auth.uid(),
      decision_evidence_hash=approval.requested_resource_hash
  where id=approval.id
  returning * into approval;

  perform audit.append_event(
    org_id,approval.project_id,'approval.'||decision_value,'approval_request',approval.id,
    before_state,to_jsonb(approval),decision_comments,gen_random_uuid()
  );
end;
$$;
revoke all on function public.decide_governed_approval(uuid,text,text,text) from public,anon;
grant execute on function public.decide_governed_approval(uuid,text,text,text) to authenticated;

create or replace function public.list_project_approval_workspace(target_project_id uuid)
returns jsonb
language plpgsql
stable
security invoker
set search_path='coordination','project','auth','pg_temp'
as $$
begin
  if auth.uid() is null or not project.can_access_project(target_project_id) then
    raise exception 'project_access_required';
  end if;
  return jsonb_build_object(
    'approvals',coalesce((
      select jsonb_agg(jsonb_build_object(
        'id',a.id,
        'resource_type',a.resource_type,
        'resource_id',a.resource_id,
        'requested_resource_hash',a.requested_resource_hash,
        'requested_from',a.requested_from,
        'role_required',a.role_required,
        'criticality',a.criticality,
        'decision',a.decision,
        'comments',a.comments,
        'requested_by',a.requested_by,
        'requested_at',a.requested_at,
        'decided_at',a.decided_at,
        'decision_evidence_hash',a.decision_evidence_hash,
        'decided_by',a.decided_by
      ) order by case when a.decision='pending' then 0 else 1 end,a.requested_at desc)
      from coordination.approval_requests a
      where a.project_id=target_project_id
    ),'[]'::jsonb)
  );
end;
$$;
revoke all on function public.list_project_approval_workspace(uuid) from public,anon;
grant execute on function public.list_project_approval_workspace(uuid) to authenticated;

commit;