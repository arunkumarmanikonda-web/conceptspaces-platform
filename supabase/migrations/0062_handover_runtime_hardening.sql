begin;

-- Permit project participants to submit evidence, but reserve acceptance/administrative changes for project managers.
drop policy if exists handover_items_update on public.handover_items;
create policy handover_items_update
on public.handover_items
for update to authenticated
using (
  (current_setting('conceptspaces.handover_phase',true)='item_submit' and project.can_access_project(project_id))
  or
  (current_setting('conceptspaces.handover_phase',true)='item' and project.can_manage_project(project_id))
)
with check (
  (current_setting('conceptspaces.handover_phase',true)='item_submit' and project.can_access_project(project_id) and submitted_by=auth.uid() and status='submitted')
  or
  (current_setting('conceptspaces.handover_phase',true)='item' and project.can_manage_project(project_id))
);

create or replace function public.submit_handover_item(target_item_id uuid,target_evidence_refs jsonb)
returns text
language plpgsql
security invoker
set search_path = public, project, audit, auth, pg_temp
as $$
declare
  item public.handover_items%rowtype;
  before_state jsonb;
  org_id uuid;
begin
  select * into item from public.handover_items where id=target_item_id for update;
  if not found or auth.uid() is null or not project.can_access_project(item.project_id) then raise exception 'handover_item_access_required'; end if;
  if item.status not in ('open','submitted') then raise exception 'handover_item_not_submittable'; end if;
  if jsonb_typeof(coalesce(target_evidence_refs,'[]'::jsonb)) <> 'array' or jsonb_array_length(coalesce(target_evidence_refs,'[]'::jsonb)) = 0 then raise exception 'handover_evidence_required'; end if;

  before_state := to_jsonb(item);
  perform set_config('conceptspaces.handover_phase','item_submit',true);
  update public.handover_items
  set evidence_refs=target_evidence_refs,status='submitted',submitted_by=auth.uid(),accepted_by=null,accepted_at=null,updated_at=now()
  where id=item.id returning * into item;

  select organisation_id into org_id from project.projects where id=item.project_id;
  perform audit.append_event(org_id,item.project_id,'handover.item.submitted','handover_item',item.id,before_state,to_jsonb(item),null,gen_random_uuid());
  return item.status;
end;
$$;
revoke all on function public.submit_handover_item(uuid,jsonb) from public, anon;
grant execute on function public.submit_handover_item(uuid,jsonb) to authenticated;

create or replace function public.decide_handover_item(target_item_id uuid,target_decision text,target_reason text default null)
returns text
language plpgsql
security invoker
set search_path = public, project, audit, auth, pg_temp
as $$
declare
  item public.handover_items%rowtype;
  before_state jsonb;
  decision_value text := lower(btrim(target_decision));
  org_id uuid;
begin
  select * into item from public.handover_items where id=target_item_id for update;
  if not found or auth.uid() is null or not project.can_manage_project(item.project_id) then raise exception 'handover_accept_authority_required'; end if;
  if decision_value not in ('accepted','open','not_applicable') then raise exception 'handover_decision_invalid'; end if;
  if decision_value='accepted' and (item.status<>'submitted' or jsonb_array_length(item.evidence_refs)=0) then raise exception 'submitted_handover_evidence_required'; end if;
  if decision_value='not_applicable' and item.mandatory and not exists(
    select 1 from public.handover_exceptions e where e.project_id=item.project_id and e.handover_item_id=item.id and e.status='approved'
  ) then raise exception 'mandatory_item_requires_approved_exception'; end if;
  if decision_value='not_applicable' and nullif(btrim(target_reason),'') is null then raise exception 'not_applicable_reason_required'; end if;

  before_state := to_jsonb(item);
  perform set_config('conceptspaces.handover_phase','item',true);
  update public.handover_items
  set status=decision_value,
      accepted_by=case when decision_value in ('accepted','not_applicable') then auth.uid() else null end,
      accepted_at=case when decision_value in ('accepted','not_applicable') then now() else null end,
      updated_at=now()
  where id=item.id returning * into item;

  select organisation_id into org_id from project.projects where id=item.project_id;
  perform audit.append_event(org_id,item.project_id,'handover.item.'||decision_value,'handover_item',item.id,before_state,to_jsonb(item),target_reason,gen_random_uuid());
  return item.status;
end;
$$;
revoke all on function public.decide_handover_item(uuid,text,text) from public, anon;
grant execute on function public.decide_handover_item(uuid,text,text) to authenticated;

-- Mandatory items are complete only when accepted, or when an approved exception exists.
create or replace function public.compile_building_passport(target_project_id uuid)
returns uuid
language plpgsql
security invoker
set search_path = public, project, audit, extensions, auth, pg_temp
as $$
declare
  snapshot jsonb;
  snapshot_hash_value text;
  gap_refs jsonb;
  exception_refs jsonb;
  passport public.building_passports%rowtype;
  version_value integer;
  org_id uuid;
begin
  if auth.uid() is null or not project.can_manage_project(target_project_id) then raise exception 'project_manage_authority_required'; end if;
  perform public.ensure_standard_handover_checklist(target_project_id);

  snapshot:=public.handover_snapshot(target_project_id);
  snapshot_hash_value:=encode(extensions.digest(snapshot::text,'sha256'),'hex');

  select coalesce(jsonb_agg(jsonb_build_object('item_id',h.id,'item_code',h.item_code,'title',h.title,'status',h.status) order by h.item_code),'[]'::jsonb)
  into gap_refs
  from public.handover_items h
  where h.project_id=target_project_id
    and h.mandatory
    and h.status<>'accepted'
    and not exists (
      select 1 from public.handover_exceptions e
      where e.handover_item_id=h.id and e.project_id=target_project_id and e.status='approved'
    );

  select coalesce(jsonb_agg(jsonb_build_object('id',e.id,'handover_item_id',e.handover_item_id,'reason',e.reason) order by e.created_at,e.id),'[]'::jsonb)
  into exception_refs
  from public.handover_exceptions e
  where e.project_id=target_project_id and e.status='approved';

  select coalesce(max(version),0)+1 into version_value from public.building_passports where project_id=target_project_id;
  perform set_config('conceptspaces.handover_phase','compile',true);
  insert into public.building_passports(project_id,version,handover_snapshot,snapshot_hash,mandatory_gap_refs,exception_refs,status,compiled_by)
  values(target_project_id,version_value,snapshot,snapshot_hash_value,gap_refs,exception_refs,'compiled',auth.uid()) returning * into passport;

  select organisation_id into org_id from project.projects where id=target_project_id;
  perform audit.append_event(org_id,target_project_id,'building_passport.compiled','building_passport',passport.id,null,to_jsonb(passport),snapshot_hash_value,gen_random_uuid());
  return passport.id;
end;
$$;
revoke all on function public.compile_building_passport(uuid) from public, anon;
grant execute on function public.compile_building_passport(uuid) to authenticated;

create or replace function public.issue_building_passport(target_passport_id uuid,target_reason text default null)
returns text
language plpgsql
security invoker
set search_path = public, project, audit, extensions, auth, pg_temp
as $$
declare
  passport public.building_passports%rowtype;
  current_snapshot jsonb;
  current_hash text;
  unresolved_gap_count integer;
  unverified_asset_count integer;
  unaccepted_commissioning_count integer;
  before_state jsonb;
  org_id uuid;
begin
  select * into passport from public.building_passports where id=target_passport_id for update;
  if not found or auth.uid() is null or not project.can_manage_project(passport.project_id) then raise exception 'building_passport_issue_authority_required'; end if;
  if passport.status<>'compiled' then raise exception 'building_passport_not_issuable'; end if;

  current_snapshot:=public.handover_snapshot(passport.project_id);
  current_hash:=encode(extensions.digest(current_snapshot::text,'sha256'),'hex');
  if current_hash<>passport.snapshot_hash then raise exception 'building_passport_snapshot_stale_recompile_required'; end if;

  select count(*) into unresolved_gap_count
  from public.handover_items h
  where h.project_id=passport.project_id and h.mandatory and h.status<>'accepted'
    and not exists(select 1 from public.handover_exceptions e where e.project_id=h.project_id and e.handover_item_id=h.id and e.status='approved');
  if unresolved_gap_count>0 then raise exception 'mandatory_handover_gaps_open'; end if;

  select count(*) into unverified_asset_count from public.asset_passports a where a.project_id=passport.project_id and a.verified_at is null;
  if unverified_asset_count>0 then raise exception 'unverified_assets_block_handover'; end if;

  select count(*) into unaccepted_commissioning_count from public.commissioning_records c where c.project_id=passport.project_id and (c.result='fail' or c.accepted_at is null);
  if unaccepted_commissioning_count>0 then raise exception 'commissioning_incomplete_blocks_handover'; end if;

  before_state:=to_jsonb(passport);
  perform set_config('conceptspaces.handover_phase','issue',true);
  update public.building_passports set status='issued',issued_by=auth.uid(),issued_at=now() where id=passport.id returning * into passport;

  perform set_config('conceptspaces.handover_phase','asset_verify',true);
  update public.asset_passports set source_building_passport_hash=passport.snapshot_hash,updated_at=now() where project_id=passport.project_id and verified_at is not null;

  select organisation_id into org_id from project.projects where id=passport.project_id;
  perform audit.append_event(org_id,passport.project_id,'building_passport.issued','building_passport',passport.id,before_state,to_jsonb(passport),target_reason,gen_random_uuid());
  return passport.status;
end;
$$;
revoke all on function public.issue_building_passport(uuid,text) from public, anon;
grant execute on function public.issue_building_passport(uuid,text) to authenticated;

commit;
