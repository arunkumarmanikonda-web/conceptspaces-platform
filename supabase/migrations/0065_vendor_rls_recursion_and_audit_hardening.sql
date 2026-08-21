begin;

create or replace function procurement.current_user_owns_vendor(target_vendor_id uuid)
returns boolean
language sql stable security definer
set search_path=procurement,auth,pg_temp
as $$
  select auth.uid() is not null and exists(
    select 1 from procurement.vendor_users vu
    where vu.vendor_id=target_vendor_id and vu.user_id=auth.uid() and vu.status='active'
  );
$$;
revoke all on function procurement.current_user_owns_vendor(uuid) from public,anon;
grant execute on function procurement.current_user_owns_vendor(uuid) to authenticated;

create or replace function procurement.current_user_invited_to_package(target_package_id uuid,target_vendor_id uuid default null)
returns boolean
language sql stable security definer
set search_path=procurement,auth,pg_temp
as $$
  select auth.uid() is not null and exists(
    select 1 from procurement.tender_invites ti
    join procurement.vendor_users vu on vu.vendor_id=ti.vendor_id
    where ti.tender_package_id=target_package_id
      and ti.declined_at is null
      and vu.user_id=auth.uid()
      and vu.status='active'
      and (target_vendor_id is null or ti.vendor_id=target_vendor_id)
  );
$$;
revoke all on function procurement.current_user_invited_to_package(uuid,uuid) from public,anon;
grant execute on function procurement.current_user_invited_to_package(uuid,uuid) to authenticated;

create or replace function procurement.current_user_can_read_tender_boq(target_boq_line_id uuid)
returns boolean
language sql stable security definer
set search_path=procurement,auth,pg_temp
as $$
  select auth.uid() is not null and exists(
    select 1 from procurement.tender_boq_lines tbl
    join procurement.tender_invites ti on ti.tender_package_id=tbl.tender_package_id
    join procurement.vendor_users vu on vu.vendor_id=ti.vendor_id
    where tbl.boq_line_id=target_boq_line_id
      and ti.declined_at is null
      and vu.user_id=auth.uid()
      and vu.status='active'
  );
$$;
revoke all on function procurement.current_user_can_read_tender_boq(uuid) from public,anon;
grant execute on function procurement.current_user_can_read_tender_boq(uuid) to authenticated;

-- Replace cross-table policy subqueries with narrow helpers to avoid recursive RLS evaluation.
drop policy if exists bids_sealed_read on procurement.bids;
create policy bids_sealed_read on procurement.bids for select to authenticated using (
  procurement.current_user_owns_vendor(vendor_id)
  or exists(select 1 from procurement.tender_packages p where p.id=bids.tender_package_id and p.opened_at is not null and project.can_access_project(p.project_id))
);
drop policy if exists bids_vendor_insert on procurement.bids;
create policy bids_vendor_insert on procurement.bids for insert to authenticated with check (
  current_setting('conceptspaces.procurement_phase',true)='bid_submit' and procurement.current_user_owns_vendor(vendor_id)
);
drop policy if exists invite_vendor_read on procurement.tender_invites;
create policy invite_vendor_read on procurement.tender_invites for select to authenticated using (procurement.current_user_owns_vendor(vendor_id));
drop policy if exists vendor_self_read on procurement.vendors;
create policy vendor_self_read on procurement.vendors for select to authenticated using (procurement.current_user_owns_vendor(id));
drop policy if exists tender_packages_vendor_invited_read on procurement.tender_packages;
create policy tender_packages_vendor_invited_read on procurement.tender_packages for select to authenticated using (procurement.current_user_invited_to_package(id,null));
drop policy if exists tender_boq_vendor_invited_read on procurement.tender_boq_lines;
create policy tender_boq_vendor_invited_read on procurement.tender_boq_lines for select to authenticated using (procurement.current_user_invited_to_package(tender_package_id,null));
drop policy if exists boq_lines_vendor_tender_read on cost.boq_lines;
create policy boq_lines_vendor_tender_read on cost.boq_lines for select to authenticated using (procurement.current_user_can_read_tender_boq(id));
drop policy if exists tender_invites_vendor_update on procurement.tender_invites;
create policy tender_invites_vendor_update on procurement.tender_invites for update to authenticated
using (procurement.current_user_owns_vendor(vendor_id))
with check (current_setting('conceptspaces.procurement_phase',true)='vendor_invite_response' and procurement.current_user_owns_vendor(vendor_id));
drop policy if exists clarifications_vendor_insert on procurement.clarifications;
create policy clarifications_vendor_insert on procurement.clarifications for insert to authenticated with check (
  current_setting('conceptspaces.procurement_phase',true)='clarification_vendor'
  and raised_by=auth.uid()
  and vendor_id is not null
  and procurement.current_user_owns_vendor(vendor_id)
  and procurement.current_user_invited_to_package(tender_package_id,vendor_id)
);

create or replace function public.respond_tender_invite(target_invite_id uuid,target_response text)
returns text
language plpgsql security invoker
set search_path=public,procurement,audit,project,auth,pg_temp
as $$
declare ti procurement.tender_invites%rowtype; p procurement.tender_packages%rowtype; response_value text:=lower(btrim(target_response)); org_id uuid;
begin
  select * into ti from procurement.tender_invites where id=target_invite_id for update;
  if not found or auth.uid() is null or not procurement.current_user_owns_vendor(ti.vendor_id) then raise exception 'vendor_invite_access_denied'; end if;
  if response_value not in ('acknowledge','decline') then raise exception 'vendor_invite_response_invalid'; end if;
  if ti.declined_at is not null then raise exception 'vendor_invite_already_declined'; end if;
  perform set_config('conceptspaces.procurement_phase','vendor_invite_response',true);
  update procurement.tender_invites set viewed_at=coalesce(viewed_at,now()),declined_at=case when response_value='decline' then now() else declined_at end where id=ti.id returning * into ti;
  select * into p from procurement.tender_packages where id=ti.tender_package_id;
  select organisation_id into org_id from procurement.vendors where id=ti.vendor_id;
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
  if not procurement.current_user_owns_vendor(target_vendor_id) then raise exception 'vendor_identity_required'; end if;
  if not procurement.current_user_invited_to_package(target_package_id,target_vendor_id) then raise exception 'tender_invitation_required'; end if;
  select * into p from procurement.tender_packages where id=target_package_id;
  if not found or p.status<>'rfq' or now()>p.bid_due_at then raise exception 'clarification_window_closed'; end if;
  perform set_config('conceptspaces.procurement_phase','clarification_vendor',true);
  insert into procurement.clarifications(tender_package_id,vendor_id,question,status,raised_by,due_at)
  values(target_package_id,target_vendor_id,btrim(target_question),'open',auth.uid(),p.bid_due_at) returning * into c;
  select organisation_id into org_id from procurement.vendors where id=target_vendor_id;
  perform audit.append_event(org_id,p.project_id,'procurement.clarification.raised','clarification',c.id,null,to_jsonb(c),null,gen_random_uuid());
  return c.id;
end;$$;
revoke all on function public.raise_tender_clarification(uuid,uuid,text) from public,anon;
grant execute on function public.raise_tender_clarification(uuid,uuid,text) to authenticated;

commit;
