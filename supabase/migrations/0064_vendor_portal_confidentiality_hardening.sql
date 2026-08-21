begin;

-- Correct row correlation for sealed-bid and invite policies. A vendor user may see only their own vendor rows.
drop policy if exists bids_sealed_read on procurement.bids;
create policy bids_sealed_read on procurement.bids for select to authenticated using (
  exists(select 1 from procurement.vendor_users vu where vu.vendor_id=bids.vendor_id and vu.user_id=auth.uid() and vu.status='active')
  or exists(select 1 from procurement.tender_packages p where p.id=bids.tender_package_id and p.opened_at is not null and project.can_access_project(p.project_id))
);

drop policy if exists bids_vendor_insert on procurement.bids;
create policy bids_vendor_insert on procurement.bids for insert to authenticated with check (
  current_setting('conceptspaces.procurement_phase',true)='bid_submit'
  and exists(select 1 from procurement.vendor_users vu where vu.vendor_id=bids.vendor_id and vu.user_id=auth.uid() and vu.status='active')
);

drop policy if exists invite_vendor_read on procurement.tender_invites;
create policy invite_vendor_read on procurement.tender_invites for select to authenticated using (
  exists(select 1 from procurement.vendor_users vu where vu.vendor_id=tender_invites.vendor_id and vu.user_id=auth.uid() and vu.status='active')
);

-- Vendor users can read only their own vendor master record.
drop policy if exists vendor_self_read on procurement.vendors;
create policy vendor_self_read on procurement.vendors for select to authenticated using (
  exists(select 1 from procurement.vendor_users vu where vu.vendor_id=vendors.id and vu.user_id=auth.uid() and vu.status='active')
);

-- Invited vendors can read only the tender package and BOQ scope to which they were invited.
drop policy if exists tender_packages_vendor_invited_read on procurement.tender_packages;
create policy tender_packages_vendor_invited_read on procurement.tender_packages for select to authenticated using (
  exists(
    select 1 from procurement.tender_invites ti
    join procurement.vendor_users vu on vu.vendor_id=ti.vendor_id
    where ti.tender_package_id=tender_packages.id and ti.declined_at is null and vu.user_id=auth.uid() and vu.status='active'
  )
);

drop policy if exists tender_boq_vendor_invited_read on procurement.tender_boq_lines;
create policy tender_boq_vendor_invited_read on procurement.tender_boq_lines for select to authenticated using (
  exists(
    select 1 from procurement.tender_invites ti
    join procurement.vendor_users vu on vu.vendor_id=ti.vendor_id
    where ti.tender_package_id=tender_boq_lines.tender_package_id and ti.declined_at is null and vu.user_id=auth.uid() and vu.status='active'
  )
);

drop policy if exists boq_lines_vendor_tender_read on cost.boq_lines;
create policy boq_lines_vendor_tender_read on cost.boq_lines for select to authenticated using (
  exists(
    select 1
    from procurement.tender_boq_lines tbl
    join procurement.tender_invites ti on ti.tender_package_id=tbl.tender_package_id
    join procurement.vendor_users vu on vu.vendor_id=ti.vendor_id
    where tbl.boq_line_id=boq_lines.id and ti.declined_at is null and vu.user_id=auth.uid() and vu.status='active'
  )
);

-- Invite acknowledgement / decline is self-service only for the mapped vendor identity.
drop policy if exists tender_invites_vendor_update on procurement.tender_invites;
create policy tender_invites_vendor_update on procurement.tender_invites for update to authenticated
using (
  exists(select 1 from procurement.vendor_users vu where vu.vendor_id=tender_invites.vendor_id and vu.user_id=auth.uid() and vu.status='active')
)
with check (
  current_setting('conceptspaces.procurement_phase',true)='vendor_invite_response'
  and exists(select 1 from procurement.vendor_users vu where vu.vendor_id=tender_invites.vendor_id and vu.user_id=auth.uid() and vu.status='active')
);
grant update on procurement.tender_invites to authenticated;

-- Replace broad clarification mutation policy with explicit vendor and internal paths.
drop policy if exists clarifications_write on procurement.clarifications;
drop policy if exists clarifications_vendor_insert on procurement.clarifications;
create policy clarifications_vendor_insert on procurement.clarifications for insert to authenticated with check (
  current_setting('conceptspaces.procurement_phase',true)='clarification_vendor'
  and raised_by=auth.uid()
  and vendor_id is not null
  and exists(select 1 from procurement.vendor_users vu where vu.vendor_id=clarifications.vendor_id and vu.user_id=auth.uid() and vu.status='active')
  and exists(select 1 from procurement.tender_invites ti where ti.tender_package_id=clarifications.tender_package_id and ti.vendor_id=clarifications.vendor_id and ti.declined_at is null)
);

drop policy if exists clarifications_internal_update on procurement.clarifications;
create policy clarifications_internal_update on procurement.clarifications for update to authenticated
using (exists(select 1 from procurement.tender_packages p where p.id=clarifications.tender_package_id and project.can_manage_project(p.project_id)))
with check (
  current_setting('conceptspaces.procurement_phase',true)='clarification_response'
  and exists(select 1 from procurement.tender_packages p where p.id=clarifications.tender_package_id and project.can_manage_project(p.project_id))
);
grant insert,update on procurement.clarifications to authenticated;

create or replace function public.respond_tender_invite(target_invite_id uuid,target_response text)
returns text
language plpgsql security invoker
set search_path=public,procurement,audit,project,auth,pg_temp
as $$
declare ti procurement.tender_invites%rowtype; p procurement.tender_packages%rowtype; response_value text:=lower(btrim(target_response)); org_id uuid;
begin
  select * into ti from procurement.tender_invites where id=target_invite_id for update;
  if not found or auth.uid() is null or not exists(select 1 from procurement.vendor_users vu where vu.vendor_id=ti.vendor_id and vu.user_id=auth.uid() and vu.status='active') then raise exception 'vendor_invite_access_denied'; end if;
  if response_value not in ('acknowledge','decline') then raise exception 'vendor_invite_response_invalid'; end if;
  if ti.declined_at is not null then raise exception 'vendor_invite_already_declined'; end if;
  perform set_config('conceptspaces.procurement_phase','vendor_invite_response',true);
  update procurement.tender_invites set viewed_at=coalesce(viewed_at,now()),declined_at=case when response_value='decline' then now() else declined_at end where id=ti.id returning * into ti;
  select * into p from procurement.tender_packages where id=ti.tender_package_id;
  select organisation_id into org_id from project.projects where id=p.project_id;
  perform audit.append_event(org_id,p.project_id,'procurement.invite.'||response_value,'tender_invite',ti.id,null,to_jsonb(ti),null,gen_random_uuid());
  return response_value;
end;$$;
revoke all on function public.respond_tender_invite(uuid,text) from public,anon;
grant execute on function public.respond_tender_invite(uuid,text) to authenticated;

create or replace function public.raise_tender_clarification(target_package_id uuid,target_vendor_id uuid,target_question text)
returns uuid
language plpgsql security invoker
set search_path=public,procurement,project,audit,auth,pg_temp
as $$
declare c procurement.clarifications%rowtype; p procurement.tender_packages%rowtype; org_id uuid;
begin
  if auth.uid() is null or nullif(btrim(target_question),'') is null then raise exception 'clarification_question_required'; end if;
  if not exists(select 1 from procurement.vendor_users vu where vu.vendor_id=target_vendor_id and vu.user_id=auth.uid() and vu.status='active') then raise exception 'vendor_identity_required'; end if;
  if not exists(select 1 from procurement.tender_invites ti where ti.tender_package_id=target_package_id and ti.vendor_id=target_vendor_id and ti.declined_at is null) then raise exception 'tender_invitation_required'; end if;
  select * into p from procurement.tender_packages where id=target_package_id;
  if not found or p.status<>'rfq' or now()>p.bid_due_at then raise exception 'clarification_window_closed'; end if;
  perform set_config('conceptspaces.procurement_phase','clarification_vendor',true);
  insert into procurement.clarifications(tender_package_id,vendor_id,question,status,raised_by,due_at)
  values(target_package_id,target_vendor_id,btrim(target_question),'open',auth.uid(),p.bid_due_at) returning * into c;
  select organisation_id into org_id from project.projects where id=p.project_id;
  perform audit.append_event(org_id,p.project_id,'procurement.clarification.raised','clarification',c.id,null,to_jsonb(c),null,gen_random_uuid());
  return c.id;
end;$$;
revoke all on function public.raise_tender_clarification(uuid,uuid,text) from public,anon;
grant execute on function public.raise_tender_clarification(uuid,uuid,text) to authenticated;

create or replace function public.respond_tender_clarification(target_clarification_id uuid,target_response text)
returns text
language plpgsql security invoker
set search_path=public,procurement,project,audit,auth,pg_temp
as $$
declare c procurement.clarifications%rowtype; p procurement.tender_packages%rowtype; org_id uuid;
begin
  select * into c from procurement.clarifications where id=target_clarification_id for update;
  if not found or nullif(btrim(target_response),'') is null then raise exception 'clarification_response_required'; end if;
  select * into p from procurement.tender_packages where id=c.tender_package_id;
  if auth.uid() is null or not project.can_manage_project(p.project_id) then raise exception 'clarification_response_authority_required'; end if;
  if c.status<>'open' then raise exception 'clarification_not_open'; end if;
  perform set_config('conceptspaces.procurement_phase','clarification_response',true);
  update procurement.clarifications set response=btrim(target_response),status='answered',responded_by=auth.uid(),answered_at=now() where id=c.id returning * into c;
  select organisation_id into org_id from project.projects where id=p.project_id;
  perform audit.append_event(org_id,p.project_id,'procurement.clarification.answered','clarification',c.id,null,to_jsonb(c),null,gen_random_uuid());
  return c.status;
end;$$;
revoke all on function public.respond_tender_clarification(uuid,text) from public,anon;
grant execute on function public.respond_tender_clarification(uuid,text) to authenticated;

create or replace function public.list_vendor_procurement_workspace()
returns jsonb
language plpgsql stable security invoker
set search_path=public,procurement,cost,project,auth,pg_temp
as $$
begin
  if auth.uid() is null then raise exception 'authentication_required'; end if;
  return jsonb_build_object(
    'vendor_accounts',coalesce((select jsonb_agg(to_jsonb(v) order by v.legal_name) from procurement.vendors v join procurement.vendor_users vu on vu.vendor_id=v.id where vu.user_id=auth.uid() and vu.status='active'),'[]'::jsonb),
    'invites',coalesce((select jsonb_agg(jsonb_build_object('invite',to_jsonb(ti),'package',to_jsonb(p),'vendor_id',ti.vendor_id) order by ti.invited_at desc) from procurement.tender_invites ti join procurement.vendor_users vu on vu.vendor_id=ti.vendor_id join procurement.tender_packages p on p.id=ti.tender_package_id where vu.user_id=auth.uid() and vu.status='active'),'[]'::jsonb),
    'boq_lines',coalesce((select jsonb_agg(jsonb_build_object('tender_package_id',tbl.tender_package_id,'line',to_jsonb(b)) order by tbl.tender_package_id,b.code) from procurement.tender_boq_lines tbl join cost.boq_lines b on b.id=tbl.boq_line_id where exists(select 1 from procurement.tender_invites ti join procurement.vendor_users vu on vu.vendor_id=ti.vendor_id where ti.tender_package_id=tbl.tender_package_id and ti.declined_at is null and vu.user_id=auth.uid() and vu.status='active')),'[]'::jsonb),
    'own_bids',coalesce((select jsonb_agg(to_jsonb(b) order by b.created_at desc) from procurement.bids b join procurement.vendor_users vu on vu.vendor_id=b.vendor_id where vu.user_id=auth.uid() and vu.status='active'),'[]'::jsonb),
    'own_bid_lines',coalesce((select jsonb_agg(to_jsonb(bl) order by bl.bid_id,bl.id) from procurement.bid_lines bl join procurement.bids b on b.id=bl.bid_id join procurement.vendor_users vu on vu.vendor_id=b.vendor_id where vu.user_id=auth.uid() and vu.status='active'),'[]'::jsonb),
    'clarifications',coalesce((select jsonb_agg(to_jsonb(c) order by c.created_at desc) from procurement.clarifications c join procurement.vendor_users vu on vu.vendor_id=c.vendor_id where vu.user_id=auth.uid() and vu.status='active'),'[]'::jsonb)
  );
end;$$;
revoke all on function public.list_vendor_procurement_workspace() from public,anon;
grant execute on function public.list_vendor_procurement_workspace() to authenticated;

-- Add clarification ledger to internal procurement workspace while preserving sealed bid RLS.
create or replace function public.list_procurement_workspace(target_project_id uuid)
returns jsonb
language plpgsql stable security invoker
set search_path=public,procurement,cost,project,pg_temp
as $$
declare org_id uuid;
begin
  if auth.uid() is null or not project.can_access_project(target_project_id) then raise exception 'project_access_required'; end if;
  select organisation_id into org_id from project.projects where id=target_project_id;
  return jsonb_build_object(
    'organisation_id',org_id,
    'vendors',coalesce((select jsonb_agg(to_jsonb(v) order by v.legal_name) from procurement.vendors v where v.organisation_id=org_id),'[]'::jsonb),
    'packages',coalesce((select jsonb_agg(to_jsonb(p) order by p.created_at desc) from procurement.tender_packages p where p.project_id=target_project_id),'[]'::jsonb),
    'invites',coalesce((select jsonb_agg(to_jsonb(i) order by i.invited_at desc) from procurement.tender_invites i join procurement.tender_packages p on p.id=i.tender_package_id where p.project_id=target_project_id),'[]'::jsonb),
    'clarifications',coalesce((select jsonb_agg(to_jsonb(c) order by c.created_at desc) from procurement.clarifications c join procurement.tender_packages p on p.id=c.tender_package_id where p.project_id=target_project_id),'[]'::jsonb),
    'bid_counts',coalesce((select jsonb_agg(jsonb_build_object('tender_package_id',p.id,'submitted_count',(select count(*) from procurement.bids b where b.tender_package_id=p.id)) order by p.created_at desc) from procurement.tender_packages p where p.project_id=target_project_id),'[]'::jsonb),
    'bids',coalesce((select jsonb_agg(to_jsonb(b) order by b.submitted_at desc nulls last,b.created_at desc) from procurement.bids b join procurement.tender_packages p on p.id=b.tender_package_id where p.project_id=target_project_id),'[]'::jsonb),
    'evaluations',coalesce((select jsonb_agg(to_jsonb(e) order by e.created_at desc) from procurement.bid_evaluations e join procurement.bids b on b.id=e.bid_id join procurement.tender_packages p on p.id=b.tender_package_id where p.project_id=target_project_id),'[]'::jsonb),
    'purchase_orders',coalesce((select jsonb_agg(to_jsonb(po) order by po.created_at desc) from procurement.purchase_orders po where po.project_id=target_project_id),'[]'::jsonb),
    'goods_receipts',coalesce((select jsonb_agg(to_jsonb(g) order by g.created_at desc) from procurement.goods_receipts g where g.project_id=target_project_id),'[]'::jsonb),
    'vendor_invoices',coalesce((select jsonb_agg(to_jsonb(i) order by i.created_at desc) from procurement.vendor_invoices i where i.project_id=target_project_id),'[]'::jsonb),
    'approved_boq_lines',coalesce((select jsonb_agg(to_jsonb(b) order by b.code) from cost.boq_lines b join cost.cost_plans cp on cp.id=b.cost_plan_id where cp.project_id=target_project_id and cp.status='approved'),'[]'::jsonb)
  );
end;$$;
revoke all on function public.list_procurement_workspace(uuid) from public,anon;
grant execute on function public.list_procurement_workspace(uuid) to authenticated;

commit;
