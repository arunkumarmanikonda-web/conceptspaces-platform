begin;

-- F01: one deterministic access evaluator shared by RLS helpers and admin simulation.
create or replace function core.evaluate_access_for_user(
  target_user_id uuid,
  target_scope text,
  target_org uuid default null,
  target_project uuid default null,
  allowed_roles text[] default null,
  internal_only boolean default false
)
returns boolean
language plpgsql
stable
security definer
set search_path='core','project','pg_temp'
as $$
declare
  scope_value text:=lower(btrim(target_scope));
  p project.projects%rowtype;
begin
  if target_user_id is null then return false; end if;

  if scope_value='platform_admin' then
    return exists(
      select 1 from core.memberships m
      where m.user_id=target_user_id and m.status='active' and m.role_code='super_admin'
    );
  end if;

  if scope_value='org_member' then
    if target_org is null then return false; end if;
    return exists(
      select 1 from core.memberships m
      where m.organisation_id=target_org
        and m.user_id=target_user_id
        and m.status='active'
        and (not internal_only or m.role_code<>'client')
        and (coalesce(array_length(allowed_roles,1),0)=0 or m.role_code=any(allowed_roles))
    );
  end if;

  if scope_value='project' then
    if target_project is null then return false; end if;
    select * into p from project.projects where id=target_project;
    if not found then return false; end if;

    -- Project authority is never valid after the parent organisation membership is suspended.
    if not exists(
      select 1 from core.memberships m
      where m.organisation_id=p.organisation_id
        and m.user_id=target_user_id
        and m.status='active'
    ) then return false; end if;

    return exists(
      select 1 from core.memberships m
      where m.organisation_id=p.organisation_id
        and m.user_id=target_user_id
        and m.status='active'
        and m.role_code in ('super_admin','org_admin')
    )
    or p.lead_architect_user_id=target_user_id
    or p.created_by=target_user_id
    or exists(
      select 1 from project.project_members pm
      where pm.project_id=p.id
        and pm.user_id=target_user_id
        and pm.status='active'
    );
  end if;

  return false;
end;
$$;
revoke all on function core.evaluate_access_for_user(uuid,text,uuid,uuid,text[],boolean) from public,anon,authenticated;

create or replace function core.has_org_role(target_org uuid,allowed_roles text[])
returns boolean language sql stable security definer set search_path='core','project','pg_temp' as $$
  select core.evaluate_access_for_user((select auth.uid()),'org_member',target_org,null,allowed_roles,false);
$$;

create or replace function core.is_internal_org_member(target_org uuid)
returns boolean language sql stable security definer set search_path='core','project','pg_temp' as $$
  select core.evaluate_access_for_user((select auth.uid()),'org_member',target_org,null,null,true);
$$;

create or replace function core.is_org_member(target_org uuid)
returns boolean language sql stable security definer set search_path='core','project','pg_temp' as $$
  select core.evaluate_access_for_user((select auth.uid()),'org_member',target_org,null,null,false);
$$;

create or replace function core.is_platform_admin()
returns boolean language sql stable security definer set search_path='core','project','pg_temp' as $$
  select core.evaluate_access_for_user((select auth.uid()),'platform_admin',null,null,null,false);
$$;

create or replace function project.can_access_project(target_project uuid)
returns boolean language sql stable security definer set search_path='core','project','pg_temp' as $$
  select core.evaluate_access_for_user((select auth.uid()),'project',null,target_project,null,false);
$$;

create or replace function public.evaluate_current_access(
  target_scope text,
  target_org uuid default null,
  target_project uuid default null,
  allowed_roles text[] default null,
  internal_only boolean default false
)
returns jsonb
language plpgsql
stable
security invoker
set search_path='core','project','auth','pg_temp'
as $$
declare decision boolean;
begin
  if auth.uid() is null then raise exception 'authentication_required'; end if;
  decision:=core.evaluate_access_for_user(auth.uid(),target_scope,target_org,target_project,allowed_roles,internal_only);
  return jsonb_build_object('user_id',auth.uid(),'scope',lower(btrim(target_scope)),'organisation_id',target_org,'project_id',target_project,'allowed',decision);
end;
$$;
revoke all on function public.evaluate_current_access(text,uuid,uuid,text[],boolean) from public,anon;
grant execute on function public.evaluate_current_access(text,uuid,uuid,text[],boolean) to authenticated;

create or replace function public.simulate_access_decision(
  target_user_id uuid,
  target_scope text,
  target_org uuid default null,
  target_project uuid default null,
  allowed_roles text[] default null,
  internal_only boolean default false
)
returns jsonb
language plpgsql
stable
security definer
set search_path='core','project','auth','pg_temp'
as $$
declare decision boolean; authority_org uuid:=target_org;
begin
  if auth.uid() is null then raise exception 'authentication_required'; end if;
  if target_project is not null then
    select organisation_id into authority_org from project.projects where id=target_project;
  end if;
  if authority_org is null then
    if not core.evaluate_access_for_user(auth.uid(),'platform_admin',null,null,null,false) then raise exception 'platform_admin_required'; end if;
  elsif not (
    core.evaluate_access_for_user(auth.uid(),'platform_admin',null,null,null,false)
    or core.evaluate_access_for_user(auth.uid(),'org_member',authority_org,null,array['org_admin'],false)
  ) then raise exception 'organisation_admin_required'; end if;
  decision:=core.evaluate_access_for_user(target_user_id,target_scope,target_org,target_project,allowed_roles,internal_only);
  return jsonb_build_object('user_id',target_user_id,'scope',lower(btrim(target_scope)),'organisation_id',target_org,'project_id',target_project,'allowed',decision,'evaluator','core.evaluate_access_for_user');
end;
$$;
revoke all on function public.simulate_access_decision(uuid,text,uuid,uuid,text[],boolean) from public,anon;
grant execute on function public.simulate_access_decision(uuid,text,uuid,uuid,text[],boolean) to authenticated;

-- Session revocation uses the Auth session source of truth; refresh tokens cascade when sessions are deleted.
create or replace function core.revoke_auth_sessions_for_suspension(target_user_id uuid,target_org uuid,target_reason text)
returns integer
language plpgsql
security definer
set search_path='core','audit','auth','pg_temp'
as $$
declare revoked_count int:=0; actor_org uuid;
begin
  if auth.uid() is null then raise exception 'authentication_required'; end if;
  if nullif(btrim(target_reason),'') is null then raise exception 'suspension_reason_required'; end if;
  if not exists(select 1 from core.memberships m where m.organisation_id=target_org and m.user_id=target_user_id) then raise exception 'target_membership_not_found'; end if;
  if not (core.is_platform_admin() or core.has_org_role(target_org,array['org_admin'])) then raise exception 'organisation_admin_required'; end if;
  if exists(select 1 from core.memberships m where m.organisation_id=target_org and m.user_id=target_user_id and m.role_code='super_admin') and not core.is_platform_admin() then raise exception 'platform_admin_required'; end if;

  update auth.refresh_tokens set revoked=true,updated_at=now()
  where user_id=target_user_id::text and coalesce(revoked,false)=false;
  delete from auth.sessions where user_id=target_user_id;
  get diagnostics revoked_count=row_count;

  actor_org:=target_org;
  perform audit.append_event(actor_org,null,'identity.sessions_revoked','identity',target_user_id,null,jsonb_build_object('reason',target_reason,'session_count',revoked_count),target_reason,gen_random_uuid());
  return revoked_count;
end;
$$;
revoke all on function core.revoke_auth_sessions_for_suspension(uuid,uuid,text) from public,anon;
grant execute on function core.revoke_auth_sessions_for_suspension(uuid,uuid,text) to authenticated;

create or replace function public.set_workspace_membership_status(target_membership_id uuid,new_status text)
returns void
language plpgsql
security invoker
set search_path='core','audit','auth','pg_temp'
as $$
declare m core.memberships%rowtype; active_super_admins integer; before_state jsonb; remaining_active int;
begin
  if new_status not in ('active','suspended') then raise exception 'unsupported_membership_status'; end if;
  select * into m from core.memberships where id=target_membership_id for update;
  if not found then raise exception 'membership_not_found'; end if;
  if m.role_code='super_admin' and not core.is_platform_admin() then raise exception 'platform_admin_required'; end if;
  if m.role_code<>'super_admin' and not (core.is_platform_admin() or core.has_org_role(m.organisation_id,array['org_admin'])) then raise exception 'organisation_admin_required'; end if;
  if m.role_code='super_admin' and m.status='active' and new_status='suspended' then
    perform pg_advisory_xact_lock(hashtext('concept_spaces_super_admin_floor'));
    select count(*) into active_super_admins from core.memberships where role_code='super_admin' and status='active';
    if active_super_admins<=1 then raise exception 'cannot_suspend_last_super_admin'; end if;
  end if;
  before_state:=to_jsonb(m);
  update core.memberships set status=new_status where id=m.id returning * into m;
  perform audit.append_event(m.organisation_id,null,'identity.membership_'||new_status,'membership',m.id,before_state,to_jsonb(m),null,gen_random_uuid());

  if new_status='suspended' then
    select count(*) into remaining_active from core.memberships x where x.organisation_id=m.organisation_id and x.user_id=m.user_id and x.status='active';
    if remaining_active=0 then
      perform core.revoke_auth_sessions_for_suspension(m.user_id,m.organisation_id,'All workspace authority suspended');
    end if;
  end if;
end;
$$;
revoke all on function public.set_workspace_membership_status(uuid,text) from public,anon;
grant execute on function public.set_workspace_membership_status(uuid,text) to authenticated;

-- F03: governed CRM history, duplicate merge and structured lost/remarketing workflow.
alter table public.leads add column if not exists merged_into_lead_id uuid references public.leads(id) on delete restrict;
alter table public.leads add column if not exists merged_at timestamptz;
alter table public.leads add column if not exists merged_by uuid references auth.users(id) on delete set null;
alter table public.leads drop constraint if exists leads_status_check;
alter table public.leads add constraint leads_status_check check(status in ('new','qualified','nurture','won','lost','merged'));

alter table public.opportunities add column if not exists lost_reason_code text;
alter table public.opportunities add column if not exists lost_reason_detail text;
alter table public.opportunities add column if not exists lost_at timestamptz;
alter table public.opportunities add column if not exists lost_by uuid references auth.users(id) on delete set null;
alter table public.opportunities add column if not exists remarketing_eligible boolean not null default false;
alter table public.opportunities add column if not exists remarketing_segment text;

create table if not exists public.crm_activities(
  id uuid primary key default gen_random_uuid(),
  organisation_id uuid not null references core.organisations(id) on delete cascade,
  lead_id uuid references public.leads(id) on delete set null,
  origin_lead_id uuid references public.leads(id) on delete set null,
  opportunity_id uuid references public.opportunities(id) on delete set null,
  activity_type text not null,
  summary text not null,
  occurred_at timestamptz not null default now(),
  actor_user_id uuid references auth.users(id) on delete set null,
  metadata jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  constraint crm_activity_target_check check(lead_id is not null or opportunity_id is not null)
);

create table if not exists public.crm_lead_merges(
  id uuid primary key default gen_random_uuid(),
  organisation_id uuid not null references core.organisations(id) on delete cascade,
  survivor_lead_id uuid not null references public.leads(id) on delete restrict,
  merged_lead_id uuid not null references public.leads(id) on delete restrict,
  reason text not null,
  snapshot jsonb not null,
  merged_by uuid references auth.users(id) on delete set null,
  merged_at timestamptz not null default now(),
  constraint crm_lead_merge_distinct check(survivor_lead_id<>merged_lead_id),
  unique(merged_lead_id)
);

create table if not exists public.crm_remarketing_entries(
  id uuid primary key default gen_random_uuid(),
  organisation_id uuid not null references core.organisations(id) on delete cascade,
  opportunity_id uuid not null references public.opportunities(id) on delete cascade,
  contact_id uuid references public.contacts(id) on delete set null,
  segment text not null,
  reason_code text not null,
  status text not null check(status in ('eligible','suppressed','active','completed')),
  legal_basis text,
  suppression_reason text,
  created_by uuid references auth.users(id) on delete set null,
  created_at timestamptz not null default now(),
  unique(opportunity_id,segment)
);

alter table public.crm_activities enable row level security;
alter table public.crm_lead_merges enable row level security;
alter table public.crm_remarketing_entries enable row level security;

grant select,insert on public.crm_activities,public.crm_lead_merges,public.crm_remarketing_entries to authenticated;
grant update on public.crm_remarketing_entries to authenticated;

drop policy if exists crm_activities_read on public.crm_activities;
create policy crm_activities_read on public.crm_activities for select to authenticated using(core.is_internal_org_member(organisation_id));
drop policy if exists crm_activities_insert on public.crm_activities;
create policy crm_activities_insert on public.crm_activities for insert to authenticated with check(core.has_org_role(organisation_id,array['super_admin','org_admin','sales','project_manager']) and current_setting('conceptspaces.crm_phase',true) in ('activity','merge','lost'));

drop policy if exists crm_lead_merges_read on public.crm_lead_merges;
create policy crm_lead_merges_read on public.crm_lead_merges for select to authenticated using(core.is_internal_org_member(organisation_id));
drop policy if exists crm_lead_merges_insert on public.crm_lead_merges;
create policy crm_lead_merges_insert on public.crm_lead_merges for insert to authenticated with check(core.has_org_role(organisation_id,array['super_admin','org_admin','sales','project_manager']) and current_setting('conceptspaces.crm_phase',true)='merge');

drop policy if exists crm_remarketing_read on public.crm_remarketing_entries;
create policy crm_remarketing_read on public.crm_remarketing_entries for select to authenticated using(core.is_internal_org_member(organisation_id));
drop policy if exists crm_remarketing_insert on public.crm_remarketing_entries;
create policy crm_remarketing_insert on public.crm_remarketing_entries for insert to authenticated with check(core.has_org_role(organisation_id,array['super_admin','org_admin','sales','project_manager']) and current_setting('conceptspaces.crm_phase',true)='lost');
drop policy if exists crm_remarketing_update on public.crm_remarketing_entries;
create policy crm_remarketing_update on public.crm_remarketing_entries for update to authenticated using(core.has_org_role(organisation_id,array['super_admin','org_admin','sales','project_manager'])) with check(core.has_org_role(organisation_id,array['super_admin','org_admin','sales','project_manager']) and current_setting('conceptspaces.crm_phase',true)='remarketing');

create or replace function public.record_crm_activity(target_lead_id uuid,target_opportunity_id uuid,input_payload jsonb)
returns uuid
language plpgsql security invoker set search_path='public','core','audit','auth','pg_temp' as $$
declare org_id uuid; r public.crm_activities%rowtype;
begin
  if auth.uid() is null then raise exception 'authentication_required'; end if;
  select organisation_id into org_id from public.leads where id=target_lead_id;
  if org_id is null then select organisation_id into org_id from public.opportunities where id=target_opportunity_id; end if;
  if org_id is null then raise exception 'crm_activity_target_required'; end if;
  if target_lead_id is not null and exists(select 1 from public.leads l where l.id=target_lead_id and l.organisation_id<>org_id) then raise exception 'crm_cross_org_target'; end if;
  if target_opportunity_id is not null and exists(select 1 from public.opportunities o where o.id=target_opportunity_id and o.organisation_id<>org_id) then raise exception 'crm_cross_org_target'; end if;
  if not core.has_org_role(org_id,array['super_admin','org_admin','sales','project_manager']) then raise exception 'crm_write_authority_required'; end if;
  if nullif(btrim(input_payload->>'activity_type'),'') is null or nullif(btrim(input_payload->>'summary'),'') is null then raise exception 'crm_activity_fields_required'; end if;
  perform set_config('conceptspaces.crm_phase','activity',true);
  insert into public.crm_activities(organisation_id,lead_id,origin_lead_id,opportunity_id,activity_type,summary,occurred_at,actor_user_id,metadata)
  values(org_id,target_lead_id,target_lead_id,target_opportunity_id,btrim(input_payload->>'activity_type'),btrim(input_payload->>'summary'),coalesce(nullif(input_payload->>'occurred_at','')::timestamptz,now()),auth.uid(),coalesce(input_payload->'metadata','{}'::jsonb)) returning * into r;
  perform audit.append_event(org_id,null,'crm.activity_recorded','crm_activity',r.id,null,to_jsonb(r),null,gen_random_uuid());
  return r.id;
end;
$$;
revoke all on function public.record_crm_activity(uuid,uuid,jsonb) from public,anon;
grant execute on function public.record_crm_activity(uuid,uuid,jsonb) to authenticated;

create or replace function public.merge_crm_leads(survivor_lead_id uuid,duplicate_lead_id uuid,target_reason text)
returns uuid
language plpgsql security invoker set search_path='public','core','audit','auth','pg_temp' as $$
declare survivor public.leads%rowtype; duplicate public.leads%rowtype; merge_row public.crm_lead_merges%rowtype; snap jsonb;
begin
  if auth.uid() is null then raise exception 'authentication_required'; end if;
  if survivor_lead_id=duplicate_lead_id then raise exception 'lead_merge_requires_distinct_records'; end if;
  if nullif(btrim(target_reason),'') is null then raise exception 'lead_merge_reason_required'; end if;
  select * into survivor from public.leads where id=survivor_lead_id for update;
  select * into duplicate from public.leads where id=duplicate_lead_id for update;
  if survivor.id is null or duplicate.id is null then raise exception 'lead_not_found'; end if;
  if survivor.organisation_id<>duplicate.organisation_id then raise exception 'lead_merge_cross_org_forbidden'; end if;
  if duplicate.status='merged' or duplicate.merged_into_lead_id is not null then raise exception 'lead_already_merged'; end if;
  if not core.has_org_role(survivor.organisation_id,array['super_admin','org_admin','sales','project_manager']) then raise exception 'crm_write_authority_required'; end if;
  snap:=jsonb_build_object('survivor_before',to_jsonb(survivor),'duplicate_before',to_jsonb(duplicate),'duplicate_contact',(select to_jsonb(c) from public.contacts c where c.id=duplicate.contact_id),'activities',(select coalesce(jsonb_agg(to_jsonb(a) order by a.occurred_at),'[]'::jsonb) from public.crm_activities a where a.lead_id=duplicate.id),'opportunities',(select coalesce(jsonb_agg(to_jsonb(o) order by o.created_at),'[]'::jsonb) from public.opportunities o where o.lead_id=duplicate.id));
  perform set_config('conceptspaces.crm_phase','merge',true);
  update public.crm_activities set lead_id=survivor.id,metadata=metadata||jsonb_build_object('merged_from_lead_id',duplicate.id) where lead_id=duplicate.id;
  update public.opportunities set lead_id=survivor.id,updated_at=now() where lead_id=duplicate.id;
  update public.leads set status='merged',merged_into_lead_id=survivor.id,merged_at=now(),merged_by=auth.uid(),updated_at=now() where id=duplicate.id;
  insert into public.crm_lead_merges(organisation_id,survivor_lead_id,merged_lead_id,reason,snapshot,merged_by)
  values(survivor.organisation_id,survivor.id,duplicate.id,btrim(target_reason),snap,auth.uid()) returning * into merge_row;
  insert into public.crm_activities(organisation_id,lead_id,origin_lead_id,activity_type,summary,actor_user_id,metadata)
  values(survivor.organisation_id,survivor.id,duplicate.id,'lead_merge','Duplicate lead merged without deleting history',auth.uid(),jsonb_build_object('merge_id',merge_row.id,'reason',target_reason));
  perform audit.append_event(survivor.organisation_id,null,'crm.lead_merged','lead',survivor.id,snap,jsonb_build_object('survivor_lead_id',survivor.id,'merged_lead_id',duplicate.id,'merge_id',merge_row.id),target_reason,gen_random_uuid());
  return merge_row.id;
end;
$$;
revoke all on function public.merge_crm_leads(uuid,uuid,text) from public,anon;
grant execute on function public.merge_crm_leads(uuid,uuid,text) to authenticated;

create or replace function public.mark_opportunity_lost(target_opportunity_id uuid,target_reason_code text,target_reason_detail text,target_remarketing_segment text default null)
returns jsonb
language plpgsql security invoker set search_path='public','core','audit','auth','pg_temp' as $$
declare o public.opportunities%rowtype; c public.contacts%rowtype; consent_ok boolean:=false; entry public.crm_remarketing_entries%rowtype; before_state jsonb;
begin
  if auth.uid() is null then raise exception 'authentication_required'; end if;
  select * into o from public.opportunities where id=target_opportunity_id for update;
  if not found then raise exception 'opportunity_not_found'; end if;
  if not core.has_org_role(o.organisation_id,array['super_admin','org_admin','sales','project_manager']) then raise exception 'crm_write_authority_required'; end if;
  if o.stage in ('won','lost') then raise exception 'opportunity_terminal_state'; end if;
  if nullif(btrim(target_reason_code),'') is null then raise exception 'lost_reason_code_required'; end if;
  before_state:=to_jsonb(o);
  if o.contact_id is not null then select * into c from public.contacts where id=o.contact_id; end if;
  consent_ok:=coalesce(c.consent_email,false) or coalesce(c.consent_whatsapp,false) or coalesce(c.consent_sms,false);
  perform set_config('conceptspaces.crm_phase','lost',true);
  update public.opportunities set stage='lost',probability=0,lost_reason_code=btrim(target_reason_code),lost_reason_detail=nullif(btrim(target_reason_detail),''),lost_at=now(),lost_by=auth.uid(),remarketing_segment=nullif(btrim(target_remarketing_segment),''),remarketing_eligible=(nullif(btrim(target_remarketing_segment),'') is not null and consent_ok),updated_at=now() where id=o.id returning * into o;
  if o.lead_id is not null and not exists(select 1 from public.opportunities x where x.lead_id=o.lead_id and x.id<>o.id and x.stage not in ('won','lost')) then
    update public.leads set status='lost',updated_at=now() where id=o.lead_id and status<>'merged';
  end if;
  if nullif(btrim(target_remarketing_segment),'') is not null then
    insert into public.crm_remarketing_entries(organisation_id,opportunity_id,contact_id,segment,reason_code,status,legal_basis,suppression_reason,created_by)
    values(o.organisation_id,o.id,o.contact_id,btrim(target_remarketing_segment),btrim(target_reason_code),case when consent_ok then 'eligible' else 'suppressed' end,case when consent_ok then 'recorded_channel_consent' else null end,case when consent_ok then null else 'no_marketing_consent' end,auth.uid()) returning * into entry;
  end if;
  insert into public.crm_activities(organisation_id,lead_id,origin_lead_id,opportunity_id,activity_type,summary,actor_user_id,metadata)
  values(o.organisation_id,o.lead_id,o.lead_id,o.id,'opportunity_lost','Opportunity marked lost with structured reason',auth.uid(),jsonb_build_object('reason_code',target_reason_code,'remarketing_segment',target_remarketing_segment,'remarketing_eligible',o.remarketing_eligible));
  perform audit.append_event(o.organisation_id,null,'crm.opportunity_lost','opportunity',o.id,before_state,to_jsonb(o),target_reason_code,gen_random_uuid());
  return jsonb_build_object('opportunity_id',o.id,'stage',o.stage,'remarketing_eligible',o.remarketing_eligible,'remarketing_status',case when entry.id is null then null else entry.status end);
end;
$$;
revoke all on function public.mark_opportunity_lost(uuid,text,text,text) from public,anon;
grant execute on function public.mark_opportunity_lost(uuid,text,text,text) to authenticated;

create or replace function public.list_crm_workspace(target_organisation_id uuid)
returns jsonb
language plpgsql stable security invoker set search_path='public','core','auth','pg_temp' as $$
begin
  if auth.uid() is null or not core.is_internal_org_member(target_organisation_id) then raise exception 'organisation_access_required'; end if;
  return jsonb_build_object(
    'leads',coalesce((select jsonb_agg(to_jsonb(l) order by l.created_at desc) from public.leads l where l.organisation_id=target_organisation_id),'[]'::jsonb),
    'contacts',coalesce((select jsonb_agg(to_jsonb(c) order by c.created_at desc) from public.contacts c where c.organisation_id=target_organisation_id),'[]'::jsonb),
    'opportunities',coalesce((select jsonb_agg(to_jsonb(o) order by o.created_at desc) from public.opportunities o where o.organisation_id=target_organisation_id),'[]'::jsonb),
    'activities',coalesce((select jsonb_agg(to_jsonb(a) order by a.occurred_at desc) from public.crm_activities a where a.organisation_id=target_organisation_id limit 200),'[]'::jsonb),
    'merges',coalesce((select jsonb_agg(to_jsonb(m) order by m.merged_at desc) from public.crm_lead_merges m where m.organisation_id=target_organisation_id limit 100),'[]'::jsonb),
    'remarketing',coalesce((select jsonb_agg(to_jsonb(r) order by r.created_at desc) from public.crm_remarketing_entries r where r.organisation_id=target_organisation_id limit 200),'[]'::jsonb)
  );
end;
$$;
revoke all on function public.list_crm_workspace(uuid) from public,anon;
grant execute on function public.list_crm_workspace(uuid) to authenticated;

commit;
