begin;

grant usage on schema engagement to authenticated;

create or replace function engagement.list_my_client_portal_invitations_impl()
returns jsonb
language plpgsql
stable
security definer
set search_path='engagement','project','auth','pg_temp'
as $$
declare client_email text:=lower(coalesce(auth.jwt()->>'email',''));
begin
  if auth.uid() is null or client_email='' then raise exception 'authenticated_email_required'; end if;
  return coalesce((select jsonb_agg(jsonb_build_object('access_id',a.id,'project_id',p.id,'project_code',p.code::text,'project_name',p.name,'role',a.role,'status',a.status,'invited_at',a.invited_at,'access_hash',a.access_hash) order by a.invited_at desc) from engagement.client_portal_access a join project.projects p on p.id=a.project_id where a.status='invited' and a.user_id is null and lower(a.invited_email)=client_email),'[]'::jsonb);
end;
$$;
revoke all on function engagement.list_my_client_portal_invitations_impl() from public,anon;
grant execute on function engagement.list_my_client_portal_invitations_impl() to authenticated;

create or replace function engagement.activate_client_portal_access_impl(target_access_id uuid)
returns uuid
language plpgsql
security definer
set search_path='public','engagement','project','audit','auth','pg_temp'
as $$
declare access_row engagement.client_portal_access%rowtype; p project.projects%rowtype; client_email text:=lower(coalesce(auth.jwt()->>'email',''));
begin
  if auth.uid() is null or client_email='' then raise exception 'authenticated_email_required'; end if;
  select * into access_row from engagement.client_portal_access where id=target_access_id and status='invited' and user_id is null and invited_email is not null and lower(invited_email)=client_email for update;
  if not found then raise exception 'client_invitation_not_available_for_current_identity'; end if;
  if access_row.project_id is null then raise exception 'client_project_required'; end if;
  select * into p from project.projects where id=access_row.project_id;
  perform set_config('conceptspaces.client_portal_phase','activate',true);
  update engagement.client_portal_access set user_id=auth.uid(),status='active',activated_at=now() where id=access_row.id returning * into access_row;
  perform audit.append_event(p.organisation_id,p.id,'client.portal.activated','client_portal_access',access_row.id,null,to_jsonb(access_row),access_row.access_hash,gen_random_uuid());
  return access_row.id;
end;
$$;
revoke all on function engagement.activate_client_portal_access_impl(uuid) from public,anon;
grant execute on function engagement.activate_client_portal_access_impl(uuid) to authenticated;

create or replace function engagement.list_client_portal_projects_impl()
returns jsonb
language plpgsql
stable
security definer
set search_path='engagement','project','auth','pg_temp'
as $$
begin
  if auth.uid() is null then raise exception 'authentication_required'; end if;
  return coalesce((
    with client_projects as (
      select p.id,p.code::text code,p.name,p.typology,p.stage,p.status,p.jurisdiction_city,p.jurisdiction_state,p.jurisdiction_country,a.id access_id,a.role access_role,a.permissions,'client'::text access_mode
      from engagement.client_portal_access a join project.projects p on p.id=a.project_id
      where a.user_id=auth.uid() and a.status='active'
    ), internal_projects as (
      select p.id,p.code::text code,p.name,p.typology,p.stage,p.status,p.jurisdiction_city,p.jurisdiction_state,p.jurisdiction_country,null::uuid access_id,'internal'::text access_role,jsonb_build_object('view_documents',true,'download_documents',true,'approve',true,'view_commercial',true,'pay',true,'message',true,'ask_project',true) permissions,'internal'::text access_mode
      from project.projects p where project.can_access_project(p.id) and not exists(select 1 from client_projects cp where cp.id=p.id)
    )
    select jsonb_agg(to_jsonb(x) order by x.name) from (select * from client_projects union all select * from internal_projects) x
  ),'[]'::jsonb);
end;
$$;
revoke all on function engagement.list_client_portal_projects_impl() from public,anon;
grant execute on function engagement.list_client_portal_projects_impl() to authenticated;

create or replace function engagement.list_client_portal_workspace_impl(target_project_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path='engagement','project','coordination','cde','governance','operations','integration','public','auth','pg_temp'
as $$
declare p project.projects%rowtype; access_row engagement.client_portal_access%rowtype; internal_mode boolean:=false; perms jsonb;
begin
  if auth.uid() is null then raise exception 'authentication_required'; end if;
  select * into p from project.projects where id=target_project_id;
  if not found then raise exception 'project_not_found'; end if;
  internal_mode:=project.can_access_project(target_project_id);
  select * into access_row from engagement.client_portal_access where project_id=target_project_id and user_id=auth.uid() and status='active' order by activated_at desc limit 1;
  if not internal_mode and not found then raise exception 'CLIENT_PERMISSION_DENIED'; end if;
  perms:=case when internal_mode then jsonb_build_object('view_documents',true,'download_documents',true,'approve',true,'view_commercial',true,'pay',true,'message',true,'ask_project',true) else access_row.permissions end;
  return jsonb_build_object(
    'project',jsonb_build_object('id',p.id,'code',p.code::text,'name',p.name,'typology',p.typology,'stage',p.stage,'status',p.status,'city',p.jurisdiction_city,'state',p.jurisdiction_state,'country',p.jurisdiction_country),
    'access',jsonb_build_object('mode',case when internal_mode then 'internal' else 'client' end,'access_id',access_row.id,'role',case when internal_mode then 'internal' else access_row.role end,'permissions',perms),
    'stages',coalesce((select jsonb_agg(jsonb_build_object('id',s.id,'stage_code',s.stage_code,'title',s.title,'sequence',s.sequence,'state',s.state,'planned_start',s.planned_start,'planned_finish',s.planned_finish,'actual_start',s.actual_start,'actual_finish',s.actual_finish) order by s.sequence) from project.project_stages s where s.project_id=target_project_id),'[]'::jsonb),
    'approvals',coalesce((select jsonb_agg(jsonb_build_object('id',a.id,'resource_type',a.resource_type,'resource_id',a.resource_id,'requested_resource_hash',a.requested_resource_hash,'role_required',a.role_required,'criticality',a.criticality,'decision',a.decision,'comments',case when a.decision='pending' then null else a.comments end,'requested_at',a.requested_at,'decided_at',a.decided_at,'decision_evidence_hash',a.decision_evidence_hash) order by case when a.decision='pending' then 0 else 1 end,a.requested_at desc) from coordination.approval_requests a where a.project_id=target_project_id and (a.requested_from=auth.uid() or coalesce(a.role_required,'') like 'client%')),'[]'::jsonb),
    'documents',case when coalesce((perms->>'view_documents')::boolean,false) then coalesce((select jsonb_agg(jsonb_build_object('id',d.id,'document_number',d.document_number::text,'title',d.title,'discipline',d.discipline,'document_type',d.document_type,'status',d.status,'revision',d.revision,'checksum',fv.checksum,'share_rights',coalesce(d.metadata->'share_rights','{}'::jsonb)) order by d.updated_at desc) from cde.documents d join cde.file_versions fv on fv.id=d.current_version_id where d.project_id=target_project_id and d.cde_state='published' and d.status in ('approved','issued')),'[]'::jsonb) else '[]'::jsonb end,
    'contract',case when coalesce((perms->>'view_commercial')::boolean,false) then coalesce((select jsonb_build_object('id',c.id,'version',c.version,'status',c.status,'contract_type',c.contract_type,'jurisdiction',c.jurisdiction,'effective_at',c.effective_at,'expires_at',c.expires_at,'execution_hash',c.execution_hash) from public.contracts c where c.id=p.contract_id and c.status not in ('draft','superseded') limit 1),'{}'::jsonb) else '{}'::jsonb end,
    'invoices',case when coalesce((perms->>'view_commercial')::boolean,false) then coalesce((select jsonb_agg(jsonb_build_object('id',i.id,'invoice_number',i.invoice_number,'status',i.status,'currency',i.currency,'issue_date',i.issue_date,'due_date',i.due_date,'subtotal',i.subtotal,'tax',i.tax,'total',i.total,'amount_paid',i.amount_paid,'outstanding',greatest(i.total-i.amount_paid,0)) order by i.issue_date desc) from public.invoices i where i.project_id=target_project_id and i.status in ('issued','part_paid','paid','overdue')),'[]'::jsonb) else '[]'::jsonb end,
    'payments',case when coalesce((perms->>'view_commercial')::boolean,false) then coalesce((select jsonb_agg(jsonb_build_object('id',t.id,'reference',t.reference,'amount_minor',t.amount_minor,'currency',t.currency,'status',t.status,'created_at',t.created_at) order by t.created_at desc) from integration.payment_transactions t where t.project_id=target_project_id and t.status in ('captured','refunded','partially_refunded')),'[]'::jsonb) else '[]'::jsonb end,
    'risks',coalesce((select jsonb_agg(jsonb_build_object('id',r.id,'code',r.code::text,'title',r.title,'category',r.category,'description',r.description,'inherent_level',r.inherent_level,'residual_level',r.residual_level,'status',r.status,'review_due_at',r.review_due_at) order by case r.inherent_level when 'critical' then 0 when 'high' then 1 when 'medium' then 2 else 3 end,r.updated_at desc) from operations.risks r where r.project_id=target_project_id and r.client_visible=true),'[]'::jsonb),
    'releases',coalesce((select jsonb_agg(jsonb_build_object('id',r.id,'package_type',r.package_type,'package_reference',r.package_reference,'content_hash',r.content_hash,'state',r.state,'issued_at',r.issued_at) order by r.issued_at desc nulls last) from governance.release_safety_cases r where r.project_id=target_project_id and r.state='issued'),'[]'::jsonb)
  );
end;
$$;
revoke all on function engagement.list_client_portal_workspace_impl(uuid) from public,anon;
grant execute on function engagement.list_client_portal_workspace_impl(uuid) to authenticated;

create or replace function engagement.decide_client_project_approval_impl(target_approval_id uuid,target_decision text,target_comments text)
returns text
language plpgsql
security definer
set search_path='engagement','coordination','project','audit','public','auth','pg_temp'
as $$
declare a coordination.approval_requests%rowtype; access_row engagement.client_portal_access%rowtype; p project.projects%rowtype; before_state jsonb; current_hash text; decision_value text:=lower(btrim(target_decision));
begin
  if auth.uid() is null then raise exception 'authentication_required'; end if;
  if decision_value not in ('approved','approved_with_comments','rejected') then raise exception 'client_approval_decision_invalid'; end if;
  select * into a from coordination.approval_requests where id=target_approval_id for update;
  if not found or a.decision<>'pending' then raise exception 'client_approval_not_pending'; end if;
  select * into access_row from engagement.client_portal_access where project_id=a.project_id and user_id=auth.uid() and status='active' order by activated_at desc limit 1;
  if not found or not coalesce((access_row.permissions->>'approve')::boolean,false) then raise exception 'CLIENT_PERMISSION_DENIED'; end if;
  if a.requested_from is not null and a.requested_from<>auth.uid() then raise exception 'client_approval_not_assigned'; end if;
  if a.requested_from is null and coalesce(a.role_required,'') not like 'client%' then raise exception 'client_approval_not_client_targeted'; end if;
  if a.role_required='client_finance' and access_row.role not in ('client_finance','client_owner') then raise exception 'client_finance_authority_required'; end if;
  if a.role_required in ('client_owner','client_approver') and access_row.role<>'client_owner' then raise exception 'client_owner_authority_required'; end if;
  if a.requested_resource_hash is null then raise exception 'APPROVAL_UNPINNED_LEGACY_REREQUEST_REQUIRED'; end if;
  current_hash:=coordination.current_approval_resource_hash(a.project_id,a.resource_type,a.resource_id);
  if current_hash is null or current_hash<>a.requested_resource_hash then raise exception 'APPROVAL_VERSION_STALE'; end if;
  select * into p from project.projects where id=a.project_id;before_state:=to_jsonb(a);
  update coordination.approval_requests set decision=decision_value,comments=nullif(btrim(target_comments),''),decided_at=now(),decided_by=auth.uid(),decision_evidence_hash=a.requested_resource_hash where id=a.id returning * into a;
  perform audit.append_event(p.organisation_id,p.id,case when decision_value='rejected' then 'client.rejected' else 'client.approved' end,'approval_request',a.id,before_state,to_jsonb(a),target_comments,gen_random_uuid());
  return a.decision;
end;
$$;
revoke all on function engagement.decide_client_project_approval_impl(uuid,text,text) from public,anon;
grant execute on function engagement.decide_client_project_approval_impl(uuid,text,text) to authenticated;

create or replace function engagement.prepare_client_invoice_payment_impl(target_invoice_id uuid)
returns jsonb
language plpgsql
security definer
set search_path='engagement','project','public','audit','auth','pg_temp'
as $$
declare i public.invoices%rowtype; access_row engagement.client_portal_access%rowtype; p project.projects%rowtype; remaining numeric; payload jsonb;
begin
  if auth.uid() is null then raise exception 'authentication_required'; end if;
  select * into i from public.invoices where id=target_invoice_id;
  if not found or i.project_id is null then raise exception 'invoice_not_found'; end if;
  select * into access_row from engagement.client_portal_access where project_id=i.project_id and user_id=auth.uid() and status='active' order by activated_at desc limit 1;
  if not found or not coalesce((access_row.permissions->>'pay')::boolean,false) then raise exception 'CLIENT_PERMISSION_DENIED'; end if;
  if i.status not in ('issued','part_paid','overdue') then raise exception 'invoice_not_payment_eligible'; end if;
  remaining:=i.total-i.amount_paid;if remaining<=0 then raise exception 'invoice_has_no_balance'; end if;
  payload:=jsonb_build_object('invoice_id',i.id,'project_id',i.project_id,'invoice_number',i.invoice_number,'currency',upper(i.currency),'amount_minor',round(remaining*100)::bigint,'receipt','INV-'||i.invoice_number,'idempotency_key','invoice:'||i.id::text||':'||round(remaining*100)::bigint::text);
  select * into p from project.projects where id=i.project_id;
  perform audit.append_event(p.organisation_id,p.id,'client.payment.prepared','invoice',i.id,null,payload,payload->>'idempotency_key',gen_random_uuid());
  return payload;
end;
$$;
revoke all on function engagement.prepare_client_invoice_payment_impl(uuid) from public,anon;
grant execute on function engagement.prepare_client_invoice_payment_impl(uuid) to authenticated;

create or replace function public.list_my_client_portal_invitations()
returns jsonb language sql stable security invoker set search_path='public','engagement','pg_temp' as $$ select engagement.list_my_client_portal_invitations_impl(); $$;

create or replace function public.activate_client_portal_access(target_access_id uuid)
returns uuid language sql security invoker set search_path='public','engagement','pg_temp' as $$ select engagement.activate_client_portal_access_impl(target_access_id); $$;

create or replace function public.list_client_portal_projects()
returns jsonb language sql stable security invoker set search_path='public','engagement','pg_temp' as $$ select engagement.list_client_portal_projects_impl(); $$;

create or replace function public.list_client_portal_workspace(target_project_id uuid)
returns jsonb language sql stable security invoker set search_path='public','engagement','pg_temp' as $$ select engagement.list_client_portal_workspace_impl(target_project_id); $$;

create or replace function public.decide_client_project_approval(target_approval_id uuid,target_decision text,target_comments text)
returns text language sql security invoker set search_path='public','engagement','pg_temp' as $$ select engagement.decide_client_project_approval_impl(target_approval_id,target_decision,target_comments); $$;

create or replace function public.prepare_client_invoice_payment(target_invoice_id uuid)
returns jsonb language sql security invoker set search_path='public','engagement','pg_temp' as $$ select engagement.prepare_client_invoice_payment_impl(target_invoice_id); $$;

revoke all on function public.list_my_client_portal_invitations() from public,anon;
grant execute on function public.list_my_client_portal_invitations() to authenticated;
revoke all on function public.activate_client_portal_access(uuid) from public,anon;
grant execute on function public.activate_client_portal_access(uuid) to authenticated;
revoke all on function public.list_client_portal_projects() from public,anon;
grant execute on function public.list_client_portal_projects() to authenticated;
revoke all on function public.list_client_portal_workspace(uuid) from public,anon;
grant execute on function public.list_client_portal_workspace(uuid) to authenticated;
revoke all on function public.decide_client_project_approval(uuid,text,text) from public,anon;
grant execute on function public.decide_client_project_approval(uuid,text,text) to authenticated;
revoke all on function public.prepare_client_invoice_payment(uuid) from public,anon;
grant execute on function public.prepare_client_invoice_payment(uuid) to authenticated;

commit;