begin;

alter table coordination.approval_requests add column if not exists requested_resource_hash text;

create or replace function public.request_governed_approval(input_payload jsonb)
returns uuid language plpgsql security invoker set search_path='coordination','project','cde','governance','aec','public','audit','extensions','auth','pg_temp' as $$
declare project_id_value uuid:=nullif(input_payload->>'project_id','')::uuid; org_id uuid; a coordination.approval_requests%rowtype; resource_type_value text:=lower(btrim(input_payload->>'resource_type')); resource_id_value uuid:=nullif(input_payload->>'resource_id','')::uuid; criticality_value text:=upper(coalesce(nullif(btrim(input_payload->>'criticality'),''),'C1')); resource_hash_value text;
begin
 if project_id_value is null then raise exception 'project_required'; end if;
 if auth.uid() is null or not project.can_access_project(project_id_value) then raise exception 'project_access_required'; end if;
 if resource_id_value is null then raise exception 'resource_id_required'; end if;
 if resource_type_value not in ('document','model','design_option','release','commercial','change') then raise exception 'unsupported_approval_resource_type'; end if;
 if criticality_value not in ('C0','C1','C2','C3','C4') then raise exception 'unsupported_criticality'; end if;
 if resource_type_value='document' then
   select fv.checksum into resource_hash_value from cde.documents d join cde.file_versions fv on fv.id=d.current_version_id where d.id=resource_id_value and d.project_id=project_id_value and d.status not in ('superseded','withdrawn');
 elsif resource_type_value='model' then
   select m.checksum into resource_hash_value from cde.models m where m.id=resource_id_value and m.project_id=project_id_value and m.status<>'superseded';
 elsif resource_type_value='design_option' then
   select encode(extensions.digest((to_jsonb(o)-array['updated_at'])::text,'sha256'),'hex') into resource_hash_value from aec.design_options o where o.id=resource_id_value and o.project_id=project_id_value and o.status<>'superseded';
 elsif resource_type_value='release' then
   select r.content_hash into resource_hash_value from governance.release_safety_cases r where r.id=resource_id_value and r.project_id=project_id_value and r.state<>'superseded';
 elsif resource_type_value='commercial' then
   select coalesce(p.scope_hash,encode(extensions.digest((to_jsonb(p)-array['updated_at'])::text,'sha256'),'hex')) into resource_hash_value from public.proposals p join public.opportunities o on o.id=p.opportunity_id where p.id=resource_id_value and o.project_id=project_id_value and p.status not in ('superseded','withdrawn') limit 1;
   if resource_hash_value is null then select coalesce(c.execution_hash,c.draft_hash,encode(extensions.digest((to_jsonb(c)-array['updated_at'])::text,'sha256'),'hex')) into resource_hash_value from public.contracts c where c.id=resource_id_value and c.project_id=project_id_value and c.status not in ('superseded','terminated') limit 1; end if;
 elsif resource_type_value='change' then
   select encode(extensions.digest((to_jsonb(cr)-array['updated_at','approved_by','approved_at','applied_by','applied_at','applied_commit_hash'])::text,'sha256'),'hex') into resource_hash_value from public.project_change_requests cr where cr.id=resource_id_value and cr.project_id=project_id_value and cr.status not in ('superseded','applied');
 end if;
 if nullif(resource_hash_value,'') is null then raise exception 'approval_resource_not_current_or_hash_unavailable'; end if;
 select organisation_id into org_id from project.projects where id=project_id_value;
 insert into coordination.approval_requests(project_id,resource_type,resource_id,requested_resource_hash,requested_from,role_required,criticality,decision,comments,requested_by)
 values(project_id_value,resource_type_value,resource_id_value,resource_hash_value,nullif(input_payload->>'requested_from','')::uuid,nullif(lower(btrim(input_payload->>'role_required')),''),criticality_value,'pending',nullif(btrim(input_payload->>'comments'),''),auth.uid()) returning * into a;
 perform audit.append_event(org_id,project_id_value,'approval.requested','approval_request',a.id,null,to_jsonb(a),resource_hash_value,gen_random_uuid());
 return a.id;
end;$$;
revoke all on function public.request_governed_approval(jsonb) from public,anon;
grant execute on function public.request_governed_approval(jsonb) to authenticated;

create or replace function public.decide_governed_approval(target_approval_id uuid,new_decision text,decision_comments text,reviewed_resource_hash text)
returns void language plpgsql security invoker set search_path='coordination','project','core','cde','governance','aec','public','audit','extensions','auth','pg_temp' as $$
declare a coordination.approval_requests%rowtype; org_id uuid; before_state jsonb; decision_value text:=lower(btrim(new_decision)); role_ok boolean:=false; current_hash text;
begin
 if decision_value not in ('approved','approved_with_comments','rejected') then raise exception 'unsupported_approval_decision'; end if;
 select * into a from coordination.approval_requests where id=target_approval_id for update;
 if not found then raise exception 'approval_not_found'; end if;
 if a.decision<>'pending' then raise exception 'approval_already_decided'; end if;
 if auth.uid() is null or not project.can_access_project(a.project_id) then raise exception 'project_access_required'; end if;
 if a.requested_resource_hash is null then raise exception 'APPROVAL_UNPINNED_LEGACY_REREQUEST_REQUIRED'; end if;
 if a.requested_by=auth.uid() and a.criticality in ('C2','C3','C4') then raise exception 'maker_cannot_approve_own_controlled_action'; end if;
 if a.requested_from is not null and a.requested_from<>auth.uid() then raise exception 'approval_not_assigned_to_current_user'; end if;
 if nullif(btrim(reviewed_resource_hash),'') is null or btrim(reviewed_resource_hash)<>a.requested_resource_hash then raise exception 'REVIEWED_RESOURCE_HASH_MISMATCH'; end if;
 if a.resource_type='document' then select fv.checksum into current_hash from cde.documents d join cde.file_versions fv on fv.id=d.current_version_id where d.id=a.resource_id and d.project_id=a.project_id and d.status not in ('superseded','withdrawn');
 elsif a.resource_type='model' then select m.checksum into current_hash from cde.models m where m.id=a.resource_id and m.project_id=a.project_id and m.status<>'superseded';
 elsif a.resource_type='design_option' then select encode(extensions.digest((to_jsonb(o)-array['updated_at'])::text,'sha256'),'hex') into current_hash from aec.design_options o where o.id=a.resource_id and o.project_id=a.project_id and o.status<>'superseded';
 elsif a.resource_type='release' then select r.content_hash into current_hash from governance.release_safety_cases r where r.id=a.resource_id and r.project_id=a.project_id and r.state<>'superseded';
 elsif a.resource_type='commercial' then
   select coalesce(p.scope_hash,encode(extensions.digest((to_jsonb(p)-array['updated_at'])::text,'sha256'),'hex')) into current_hash from public.proposals p join public.opportunities o on o.id=p.opportunity_id where p.id=a.resource_id and o.project_id=a.project_id and p.status not in ('superseded','withdrawn') limit 1;
   if current_hash is null then select coalesce(c.execution_hash,c.draft_hash,encode(extensions.digest((to_jsonb(c)-array['updated_at'])::text,'sha256'),'hex')) into current_hash from public.contracts c where c.id=a.resource_id and c.project_id=a.project_id and c.status not in ('superseded','terminated') limit 1; end if;
 elsif a.resource_type='change' then select encode(extensions.digest((to_jsonb(cr)-array['updated_at','approved_by','approved_at','applied_by','applied_at','applied_commit_hash'])::text,'sha256'),'hex') into current_hash from public.project_change_requests cr where cr.id=a.resource_id and cr.project_id=a.project_id and cr.status not in ('superseded','applied');
 end if;
 if current_hash is null or current_hash<>a.requested_resource_hash then raise exception 'APPROVAL_VERSION_STALE'; end if;
 if a.role_required is null then role_ok:=true; else role_ok:=exists(select 1 from project.project_members pm where pm.project_id=a.project_id and pm.user_id=auth.uid() and pm.status='active' and pm.role_code=a.role_required) or exists(select 1 from project.projects p where p.id=a.project_id and core.has_org_role(p.organisation_id,array[a.role_required,'super_admin','org_admin'])); end if;
 if not role_ok then raise exception 'approval_role_authority_required'; end if;
 if a.criticality in ('C3','C4') then
   if a.role_required not in ('lead_architect','architect','structural_engineer','mep_engineer','quantity_surveyor','regulatory_reviewer') then raise exception 'professional_role_required_for_c3_c4'; end if;
   if not core.has_verified_professional_eligibility(auth.uid(),a.role_required) then raise exception 'verified_professional_eligibility_required'; end if;
 end if;
 select organisation_id into org_id from project.projects where id=a.project_id;before_state:=to_jsonb(a);
 update coordination.approval_requests set decision=decision_value,comments=decision_comments,decided_at=now(),decided_by=auth.uid(),decision_evidence_hash=a.requested_resource_hash where id=a.id returning * into a;
 perform audit.append_event(org_id,a.project_id,'approval.'||decision_value,'approval_request',a.id,before_state,to_jsonb(a),decision_comments,gen_random_uuid());
end;$$;
revoke all on function public.decide_governed_approval(uuid,text,text,text) from public,anon;
grant execute on function public.decide_governed_approval(uuid,text,text,text) to authenticated;

create or replace function public.list_project_approvals(target_project_id uuid)
returns table(id uuid,resource_type text,resource_id uuid,requested_resource_hash text,requested_from uuid,role_required text,criticality text,decision text,comments text,requested_by uuid,requested_at timestamptz,decided_at timestamptz,decision_evidence_hash text)
language sql stable security invoker set search_path='coordination','project','auth','pg_temp' as $$
 select a.id,a.resource_type,a.resource_id,a.requested_resource_hash,a.requested_from,a.role_required,a.criticality,a.decision,a.comments,a.requested_by,a.requested_at,a.decided_at,a.decision_evidence_hash from coordination.approval_requests a where a.project_id=target_project_id and auth.uid() is not null and project.can_access_project(target_project_id) order by case when a.decision='pending' then 0 else 1 end,a.requested_at desc;
$$;
revoke all on function public.list_project_approvals(uuid) from public,anon;
grant execute on function public.list_project_approvals(uuid) to authenticated;

commit;