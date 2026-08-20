begin;

create schema if not exists configuration;

create table if not exists public.project_change_requests (
  id uuid primary key default gen_random_uuid(),
  project_id uuid not null references project.projects(id) on delete cascade,
  branch_id uuid not null references public.project_branches(id) on delete restrict,
  change_ref text not null,
  title text not null,
  description text not null,
  source_object_refs jsonb not null default '[]'::jsonb,
  proposed_disciplines jsonb not null default '[]'::jsonb,
  status text not null default 'draft' check (status in ('draft','analyzed','approval_pending','approved','rejected','applied','cancelled')),
  latest_impact_id uuid,
  approval_request_id uuid references coordination.approval_requests(id) on delete set null,
  requested_by uuid not null references auth.users(id),
  approved_by uuid references auth.users(id),
  approved_at timestamptz,
  applied_by uuid references auth.users(id),
  applied_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique(project_id,change_ref)
);

alter table public.change_impacts add column if not exists change_request_id uuid references public.project_change_requests(id) on delete cascade;
alter table public.change_impacts add column if not exists analysis_version integer not null default 1;
alter table public.change_impacts add column if not exists analysis_hash text;
alter table public.change_impacts add column if not exists baseline_hash text;
alter table public.change_impacts add column if not exists affected_coordination jsonb not null default '[]'::jsonb;
alter table public.change_impacts add column if not exists affected_releases jsonb not null default '[]'::jsonb;
alter table public.change_impacts add column if not exists affected_engineering_runs jsonb not null default '[]'::jsonb;
alter table public.change_impacts add column if not exists affected_programme_tasks jsonb not null default '[]'::jsonb;
alter table public.change_impacts add column if not exists analyzed_by uuid references auth.users(id);
alter table public.change_impacts add column if not exists analysis_state text not null default 'final' check (analysis_state in ('final','superseded'));

alter table public.project_change_requests drop constraint if exists project_change_requests_latest_impact_fk;
alter table public.project_change_requests add constraint project_change_requests_latest_impact_fk
  foreign key (latest_impact_id) references public.change_impacts(id) on delete set null deferrable initially deferred;

create unique index if not exists project_change_requests_latest_impact_uidx on public.project_change_requests(latest_impact_id) where latest_impact_id is not null;
create index if not exists project_change_requests_project_status_idx on public.project_change_requests(project_id,status,updated_at desc);
create index if not exists project_change_requests_branch_idx on public.project_change_requests(branch_id,updated_at desc);
create index if not exists change_impacts_request_idx on public.change_impacts(change_request_id,analysis_version desc);
create index if not exists project_commits_branch_time_idx on public.project_commits(branch_id,created_at desc);

alter table public.project_change_requests enable row level security;

drop policy if exists project_change_requests_read on public.project_change_requests;
create policy project_change_requests_read on public.project_change_requests for select to authenticated using (project.can_access_project(project_id));
drop policy if exists project_change_requests_governed_insert on public.project_change_requests;
create policy project_change_requests_governed_insert on public.project_change_requests for insert to authenticated with check (
  project.can_access_project(project_id) and requested_by=(select auth.uid())
  and (select current_setting('conceptspaces.configuration_phase',true))='propose'
);
drop policy if exists project_change_requests_governed_update on public.project_change_requests;
create policy project_change_requests_governed_update on public.project_change_requests for update to authenticated using (project.can_access_project(project_id)) with check (
  project.can_access_project(project_id)
  and (select current_setting('conceptspaces.configuration_phase',true)) in ('analyze','request_approval','sync_approval','apply','cancel')
);

drop policy if exists project_branches_governed_insert on public.project_branches;
create policy project_branches_governed_insert on public.project_branches for insert to authenticated with check (
  project.can_access_project(project_id) and created_by=(select auth.uid())
  and (select current_setting('conceptspaces.configuration_phase',true)) in ('bootstrap','branch')
);
drop policy if exists project_branches_governed_update on public.project_branches;
create policy project_branches_governed_update on public.project_branches for update to authenticated using (project.can_access_project(project_id)) with check (
  project.can_access_project(project_id)
  and (select current_setting('conceptspaces.configuration_phase',true)) in ('commit','merge','branch_state')
);
drop policy if exists project_commits_governed_insert on public.project_commits;
create policy project_commits_governed_insert on public.project_commits for insert to authenticated with check (
  project.can_access_project(project_id)
  and (select current_setting('conceptspaces.configuration_phase',true)) in ('bootstrap','commit','merge')
);
drop policy if exists change_impacts_governed_insert on public.change_impacts;
create policy change_impacts_governed_insert on public.change_impacts for insert to authenticated with check (
  project.can_access_project(project_id) and analyzed_by=(select auth.uid())
  and (select current_setting('conceptspaces.configuration_phase',true))='analyze'
);
drop policy if exists change_impacts_governed_update on public.change_impacts;
create policy change_impacts_governed_update on public.change_impacts for update to authenticated using (project.can_access_project(project_id)) with check (
  project.can_access_project(project_id)
  and (select current_setting('conceptspaces.configuration_phase',true))='analyze'
);

create or replace function configuration.project_configuration_hash(target_project_id uuid)
returns text
language plpgsql stable security invoker
set search_path=configuration,project,cde,engineering,regula,cost,governance,extensions,public,pg_temp
as $$
declare payload jsonb;
begin
  if not project.can_access_project(target_project_id) then raise exception 'project_access_required'; end if;
  select jsonb_build_object(
    'truth',coalesce((select jsonb_agg(jsonb_build_array(t.id,t.record_key,t.status,t.updated_at) order by t.record_key,t.id) from project.truth_records t where t.project_id=target_project_id and t.status<>'superseded'),'[]'::jsonb),
    'requirements',coalesce((select jsonb_agg(jsonb_build_array(r.id,r.code::text,r.status,r.updated_at) order by r.code,r.id) from project.requirements r where r.project_id=target_project_id),'[]'::jsonb),
    'documents',coalesce((select jsonb_agg(jsonb_build_array(d.id,d.document_number::text,d.revision,v.checksum) order by d.document_number,d.id) from cde.documents d left join cde.file_versions v on v.id=d.current_version_id where d.project_id=target_project_id),'[]'::jsonb),
    'models',coalesce((select jsonb_agg(jsonb_build_array(m.id,m.model_name,m.checksum,m.status) order by m.model_name,m.id) from cde.models m where m.project_id=target_project_id),'[]'::jsonb),
    'coordination',coalesce((select jsonb_agg(jsonb_build_array(cm.id,cm.coordination_hash,cm.state,cm.updated_at) order by cm.id) from engineering.coordination_matrix cm where cm.project_id=target_project_id),'[]'::jsonb),
    'regula',coalesce((select jsonb_build_array(er.id,er.result_hash,er.status,er.completed_at) from regula.evaluation_runs er where er.project_id=target_project_id order by er.created_at desc limit 1),'[]'::jsonb),
    'cost',coalesce((select jsonb_agg(jsonb_build_array(cp.id,cp.version,cp.total,cp.status) order by cp.version,cp.id) from cost.cost_plans cp where cp.project_id=target_project_id),'[]'::jsonb),
    'releases',coalesce((select jsonb_agg(jsonb_build_array(rs.id,rs.content_hash,rs.state,rs.updated_at) order by rs.id) from governance.release_safety_cases rs where rs.project_id=target_project_id),'[]'::jsonb)
  ) into payload;
  return encode(extensions.digest(payload::text,'sha256'),'hex');
end;$$;
revoke all on function configuration.project_configuration_hash(uuid) from public,anon;
grant execute on function configuration.project_configuration_hash(uuid) to authenticated;

create or replace function public.bootstrap_project_main_branch(target_project_id uuid)
returns uuid
language plpgsql security invoker
set search_path=public,configuration,project,audit,auth,pg_temp
as $$
declare b public.project_branches%rowtype; snapshot_hash text; org_id uuid;
begin
  if auth.uid() is null or not project.can_access_project(target_project_id) then raise exception 'project_access_required'; end if;
  select * into b from public.project_branches where project_id=target_project_id and name='main';
  if found then return b.id; end if;
  snapshot_hash:=configuration.project_configuration_hash(target_project_id);
  perform set_config('conceptspaces.configuration_phase','bootstrap',true);
  insert into public.project_branches(project_id,name,parent_branch_id,parent_commit_hash,head_commit_hash,purpose,status,created_by)
    values(target_project_id,'main',null,null,snapshot_hash,'Approved project configuration','active',auth.uid()) returning * into b;
  insert into public.project_commits(project_id,branch_id,parent_commit_hashes,content_hash,message,changed_object_refs,author_type,author_ref)
    values(target_project_id,b.id,'[]'::jsonb,snapshot_hash,'Genesis project configuration','[]'::jsonb,'human',auth.uid()::text);
  select organisation_id into org_id from project.projects where id=target_project_id;
  perform audit.append_event(org_id,target_project_id,'configuration.branch.bootstrapped','project_branch',b.id,null,to_jsonb(b),snapshot_hash,gen_random_uuid());
  return b.id;
end;$$;
revoke all on function public.bootstrap_project_main_branch(uuid) from public,anon;
grant execute on function public.bootstrap_project_main_branch(uuid) to authenticated;

create or replace function public.create_project_configuration_branch(input_payload jsonb)
returns uuid
language plpgsql security invoker
set search_path=public,project,audit,auth,pg_temp
as $$
declare project_id_value uuid:=nullif(input_payload->>'project_id','')::uuid; parent_id uuid:=nullif(input_payload->>'parent_branch_id','')::uuid; parent_rec public.project_branches%rowtype; b public.project_branches%rowtype; org_id uuid; branch_name text:=lower(nullif(btrim(input_payload->>'name'),''));
begin
  if project_id_value is null or auth.uid() is null or not project.can_access_project(project_id_value) then raise exception 'project_access_required'; end if;
  if branch_name is null or branch_name='main' then raise exception 'branch_name_required_and_main_reserved'; end if;
  if branch_name !~ '^[a-z0-9][a-z0-9._-]{1,62}$' then raise exception 'invalid_branch_name'; end if;
  if nullif(btrim(input_payload->>'purpose'),'') is null then raise exception 'branch_purpose_required'; end if;
  if parent_id is null then parent_id:=public.bootstrap_project_main_branch(project_id_value); end if;
  select * into parent_rec from public.project_branches where id=parent_id and project_id=project_id_value;
  if not found or parent_rec.status not in ('active','frozen') then raise exception 'eligible_parent_branch_required'; end if;
  perform set_config('conceptspaces.configuration_phase','branch',true);
  insert into public.project_branches(project_id,name,parent_branch_id,parent_commit_hash,head_commit_hash,purpose,status,created_by)
    values(project_id_value,branch_name,parent_rec.id,parent_rec.head_commit_hash,parent_rec.head_commit_hash,btrim(input_payload->>'purpose'),'active',auth.uid()) returning * into b;
  select organisation_id into org_id from project.projects where id=project_id_value;
  perform audit.append_event(org_id,project_id_value,'configuration.branch.created','project_branch',b.id,to_jsonb(parent_rec),to_jsonb(b),b.purpose,gen_random_uuid());
  return b.id;
end;$$;
revoke all on function public.create_project_configuration_branch(jsonb) from public,anon;
grant execute on function public.create_project_configuration_branch(jsonb) to authenticated;

create or replace function public.propose_project_change(input_payload jsonb)
returns uuid
language plpgsql security invoker
set search_path=public,project,audit,auth,pg_temp
as $$
declare project_id_value uuid:=nullif(input_payload->>'project_id','')::uuid; branch_id_value uuid:=nullif(input_payload->>'branch_id','')::uuid; b public.project_branches%rowtype; req public.project_change_requests%rowtype; org_id uuid; change_ref_value text;
begin
  if project_id_value is null or auth.uid() is null or not project.can_access_project(project_id_value) then raise exception 'project_access_required'; end if;
  if branch_id_value is null then branch_id_value:=public.bootstrap_project_main_branch(project_id_value); end if;
  select * into b from public.project_branches where id=branch_id_value and project_id=project_id_value;
  if not found or b.status<>'active' then raise exception 'active_branch_required'; end if;
  if nullif(btrim(input_payload->>'title'),'') is null or nullif(btrim(input_payload->>'description'),'') is null then raise exception 'change_title_and_description_required'; end if;
  if jsonb_typeof(coalesce(input_payload->'source_object_refs','[]'::jsonb))<>'array' then raise exception 'source_object_refs_must_be_array'; end if;
  if jsonb_typeof(coalesce(input_payload->'proposed_disciplines','[]'::jsonb))<>'array' or jsonb_array_length(coalesce(input_payload->'proposed_disciplines','[]'::jsonb))=0 then raise exception 'at_least_one_affected_discipline_required'; end if;
  change_ref_value:=coalesce(nullif(btrim(input_payload->>'change_ref'),''),'CHG-'||upper(substr(replace(gen_random_uuid()::text,'-',''),1,8)));
  perform set_config('conceptspaces.configuration_phase','propose',true);
  insert into public.project_change_requests(project_id,branch_id,change_ref,title,description,source_object_refs,proposed_disciplines,status,requested_by)
    values(project_id_value,branch_id_value,change_ref_value,btrim(input_payload->>'title'),btrim(input_payload->>'description'),coalesce(input_payload->'source_object_refs','[]'::jsonb),coalesce(input_payload->'proposed_disciplines','[]'::jsonb),'draft',auth.uid()) returning * into req;
  select organisation_id into org_id from project.projects where id=project_id_value;
  perform audit.append_event(org_id,project_id_value,'configuration.change.proposed','project_change_request',req.id,null,to_jsonb(req),req.description,gen_random_uuid());
  return req.id;
end;$$;
revoke all on function public.propose_project_change(jsonb) from public,anon;
grant execute on function public.propose_project_change(jsonb) to authenticated;

create or replace function public.transition_project_configuration_branch(target_branch_id uuid,target_status text,target_reason text)
returns void
language plpgsql security invoker
set search_path=public,project,audit,auth,pg_temp
as $$
declare b public.project_branches%rowtype; before_state jsonb; next_status text:=lower(btrim(target_status)); org_id uuid;
begin
  select * into b from public.project_branches where id=target_branch_id for update;
  if not found or auth.uid() is null or not project.can_access_project(b.project_id) then raise exception 'branch_access_required'; end if;
  if b.name='main' then raise exception 'main_branch_state_is_governed_by_merge_only'; end if;
  if next_status not in ('active','frozen','abandoned') then raise exception 'unsupported_branch_state'; end if;
  if b.status in ('merged','abandoned') then raise exception 'terminal_branch_state'; end if;
  if nullif(btrim(target_reason),'') is null then raise exception 'branch_state_reason_required'; end if;
  before_state:=to_jsonb(b);
  perform set_config('conceptspaces.configuration_phase','branch_state',true);
  update public.project_branches set status=next_status where id=b.id returning * into b;
  select organisation_id into org_id from project.projects where id=b.project_id;
  perform audit.append_event(org_id,b.project_id,'configuration.branch.'||next_status,'project_branch',b.id,before_state,to_jsonb(b),btrim(target_reason),gen_random_uuid());
end;$$;
revoke all on function public.transition_project_configuration_branch(uuid,text,text) from public,anon;
grant execute on function public.transition_project_configuration_branch(uuid,text,text) to authenticated;

create or replace function public.list_project_configuration_workspace(target_project_id uuid)
returns jsonb
language sql stable security invoker
set search_path=public,project,coordination
as $$
  select jsonb_build_object(
    'branches',coalesce((select jsonb_agg(to_jsonb(b) order by case when b.name='main' then 0 else 1 end,b.created_at) from public.project_branches b where b.project_id=target_project_id),'[]'::jsonb),
    'commits',coalesce((select jsonb_agg(to_jsonb(c) order by c.created_at desc) from public.project_commits c where c.project_id=target_project_id),'[]'::jsonb),
    'changes',coalesce((select jsonb_agg(to_jsonb(r) order by r.updated_at desc) from public.project_change_requests r where r.project_id=target_project_id),'[]'::jsonb),
    'impacts',coalesce((select jsonb_agg(to_jsonb(i) order by i.created_at desc) from public.change_impacts i where i.project_id=target_project_id),'[]'::jsonb),
    'approvals',coalesce((select jsonb_agg(to_jsonb(a) order by a.requested_at desc) from coordination.approval_requests a where a.project_id=target_project_id and a.resource_type='change'),'[]'::jsonb)
  );
$$;
revoke all on function public.list_project_configuration_workspace(uuid) from public,anon;
grant execute on function public.list_project_configuration_workspace(uuid) to authenticated;

commit;
