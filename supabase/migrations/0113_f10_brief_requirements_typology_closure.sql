begin;

alter table feasibility.typology_packs add column if not exists questionnaire jsonb not null default '[]'::jsonb;
alter table feasibility.typology_packs add column if not exists pack_hash text;
alter table feasibility.typology_packs add column if not exists created_by uuid references auth.users(id) on delete set null;

-- Canonical product configuration, never tenant/demo project data.
insert into feasibility.typology_packs(code,name,typology,version,programme_categories,planning_principles,operational_principles,engineering_considerations,sustainability_considerations,commercial_drivers,benchmark_sources,questionnaire,state,approved_at)
values
 ('HOTEL','Hotel Intelligence Pack','hotel',1,'["keys","F&B","banquet","BOH","wellness","parking"]'::jsonb,'["arrival sequence","guest/service separation","key efficiency"]'::jsonb,'["housekeeping flow","service elevators","banquet operations"]'::jsonb,'["kitchen exhaust","hot water demand","laundry loads"]'::jsonb,'["water intensity","guestroom energy","daylight"]'::jsonb,'["ADR","occupancy","RevPAR","F&B capture"]'::jsonb,'[]'::jsonb,'[{"code":"HOT-KEYS","question":"Target room/key count and room mix?"},{"code":"HOT-FNB","question":"Required restaurant, bar and banquet capacities?"},{"code":"HOT-BOH","question":"Back-of-house, laundry and service-flow requirements?"},{"code":"HOT-OPS","question":"Operator brand standards or operating model constraints?"}]'::jsonb,'published',now()),
 ('HOSPITAL','Hospital Intelligence Pack','hospital',1,'["beds","OPD","diagnostics","OT","ICU","emergency","support"]'::jsonb,'["clean/dirty separation","department adjacency","ambulance access"]'::jsonb,'["patient flow","clinical logistics","infection control"]'::jsonb,'["medical gases","critical power","air changes","isolation"]'::jsonb,'["clinical energy intensity","water resilience","daylight"]'::jsonb,'["bed mix","department throughput","equipment intensity"]'::jsonb,'[]'::jsonb,'[{"code":"HSP-BEDS","question":"Target bed count, specialties and acuity mix?"},{"code":"HSP-CLIN","question":"Required OPD, diagnostics, OT, ICU and emergency capacities?"},{"code":"HSP-FLOW","question":"Patient, staff, sterile, dirty and material flow separation requirements?"},{"code":"HSP-RES","question":"Critical power, medical gas and resilience requirements?"}]'::jsonb,'published',now()),
 ('RESIDENTIAL','Residential Intelligence Pack','residential',1,'["units","unit_mix","amenities","parking","services"]'::jsonb,'["privacy gradient","core efficiency","open-space quality"]'::jsonb,'["resident circulation","service access","security"]'::jsonb,'["domestic water","electrical diversity","ventilation"]'::jsonb,'["daylight","thermal comfort","water reuse"]'::jsonb,'["saleable efficiency","unit mix","amenity burden"]'::jsonb,'[]'::jsonb,'[{"code":"RES-UNITS","question":"Target unit count and bedroom mix?"},{"code":"RES-BUYER","question":"Target resident/buyer segments and unit-area bands?"},{"code":"RES-AMEN","question":"Required indoor/outdoor amenities and clubhouse programme?"},{"code":"RES-PARK","question":"Parking, drop-off and service-access expectations?"}]'::jsonb,'published',now())
on conflict(code) do update set questionnaire=excluded.questionnaire,programme_categories=excluded.programme_categories,planning_principles=excluded.planning_principles,operational_principles=excluded.operational_principles,engineering_considerations=excluded.engineering_considerations,sustainability_considerations=excluded.sustainability_considerations,commercial_drivers=excluded.commercial_drivers;

update feasibility.typology_packs
set pack_hash=encode(extensions.digest(jsonb_build_object('code',code::text,'version',version,'typology',typology,'questionnaire',questionnaire,'programme_categories',programme_categories,'planning_principles',planning_principles,'operational_principles',operational_principles,'engineering_considerations',engineering_considerations,'sustainability_considerations',sustainability_considerations,'commercial_drivers',commercial_drivers)::text,'sha256'),'hex')
where code::text in ('HOTEL','HOSPITAL','RESIDENTIAL') or pack_hash is null;

create table if not exists feasibility.brief_interpretations(
 id uuid primary key default gen_random_uuid(),
 project_id uuid not null references project.projects(id) on delete cascade,
 typology_pack_id uuid references feasibility.typology_packs(id) on delete restrict,
 version int not null,
 source_type text not null check(source_type in ('text','voice','document','meeting')),
 raw_input text not null,
 structured_draft jsonb not null,
 status text not null check(status in ('draft','confirmed','superseded')) default 'draft',
 input_hash text not null,
 confirmed_hash text,
 created_by uuid references auth.users(id) on delete set null,
 confirmed_by uuid references auth.users(id) on delete set null,
 confirmed_at timestamptz,
 created_at timestamptz not null default now(),
 updated_at timestamptz not null default now(),
 unique(project_id,version)
);
alter table feasibility.brief_interpretations enable row level security;
grant select,insert,update on feasibility.brief_interpretations to authenticated;
drop policy if exists brief_interpretations_read on feasibility.brief_interpretations;
create policy brief_interpretations_read on feasibility.brief_interpretations for select to authenticated using(project.can_access_project(project_id));
drop policy if exists brief_interpretations_insert on feasibility.brief_interpretations;
create policy brief_interpretations_insert on feasibility.brief_interpretations for insert to authenticated with check(project.can_access_project(project_id) and created_by=auth.uid() and status='draft' and current_setting('conceptspaces.brief_phase',true)='draft');
drop policy if exists brief_interpretations_update on feasibility.brief_interpretations;
create policy brief_interpretations_update on feasibility.brief_interpretations for update to authenticated using(project.can_access_project(project_id)) with check(project.can_access_project(project_id) and current_setting('conceptspaces.brief_phase',true) in ('confirm','supersede'));

grant insert,update on feasibility.programme_briefs to authenticated;
drop policy if exists programme_briefs_governed_insert on feasibility.programme_briefs;
create policy programme_briefs_governed_insert on feasibility.programme_briefs for insert to authenticated with check(project.can_manage_project(project_id) and current_setting('conceptspaces.brief_phase',true)='confirm');
drop policy if exists programme_briefs_governed_update on feasibility.programme_briefs;
create policy programme_briefs_governed_update on feasibility.programme_briefs for update to authenticated using(project.can_manage_project(project_id)) with check(project.can_manage_project(project_id) and current_setting('conceptspaces.brief_phase',true)='supersede');

alter table project.requirements add column if not exists version int not null default 1;
alter table project.requirements add column if not exists approval_state text not null default 'draft' check(approval_state in ('draft','approved','superseded'));
alter table project.requirements add column if not exists requirement_hash text;
alter table project.requirements add column if not exists approved_by uuid references auth.users(id) on delete set null;
alter table project.requirements add column if not exists approved_at timestamptz;

create table if not exists project.requirement_revisions(
 id uuid primary key default gen_random_uuid(),
 requirement_id uuid not null references project.requirements(id) on delete cascade,
 project_id uuid not null references project.projects(id) on delete cascade,
 version int not null,
 statement text not null,
 category text not null,
 acceptance_criteria jsonb not null,
 criticality text not null,
 source_truth_record_id uuid references project.truth_records(id),
 approval_state text not null check(approval_state in ('draft','approved','superseded')),
 requirement_hash text,
 created_by uuid references auth.users(id) on delete set null,
 approved_by uuid references auth.users(id) on delete set null,
 approved_at timestamptz,
 created_at timestamptz not null default now(),
 unique(requirement_id,version)
);
create table if not exists project.requirement_trace_links(
 id uuid primary key default gen_random_uuid(),
 requirement_id uuid not null references project.requirements(id) on delete cascade,
 project_id uuid not null references project.projects(id) on delete cascade,
 resource_type text not null check(resource_type in ('model_object','drawing','test','document','model','calculation','boq','task','release')),
 resource_ref text not null,
 evidence_hash text,
 created_by uuid references auth.users(id) on delete set null,
 created_at timestamptz not null default now(),
 unique(requirement_id,resource_type,resource_ref)
);
alter table project.requirement_revisions enable row level security;
alter table project.requirement_trace_links enable row level security;
grant select,insert,update on project.requirements to authenticated;
grant select,insert,update on project.requirement_revisions to authenticated;
grant select,insert on project.requirement_trace_links to authenticated;
drop policy if exists requirement_governed_insert on project.requirements;
create policy requirement_governed_insert on project.requirements for insert to authenticated with check(project.can_access_project(project_id) and current_setting('conceptspaces.requirement_phase',true)='draft');
drop policy if exists requirement_governed_update on project.requirements;
create policy requirement_governed_update on project.requirements for update to authenticated using(project.can_manage_project(project_id)) with check(project.can_manage_project(project_id) and current_setting('conceptspaces.requirement_phase',true) in ('approve','revise'));
drop policy if exists requirement_revisions_read on project.requirement_revisions;
create policy requirement_revisions_read on project.requirement_revisions for select to authenticated using(project.can_access_project(project_id));
drop policy if exists requirement_revisions_insert on project.requirement_revisions;
create policy requirement_revisions_insert on project.requirement_revisions for insert to authenticated with check(project.can_access_project(project_id) and current_setting('conceptspaces.requirement_phase',true) in ('draft','revise'));
drop policy if exists requirement_revisions_update on project.requirement_revisions;
create policy requirement_revisions_update on project.requirement_revisions for update to authenticated using(project.can_manage_project(project_id)) with check(project.can_manage_project(project_id) and current_setting('conceptspaces.requirement_phase',true) in ('approve','revise'));
drop policy if exists requirement_trace_read on project.requirement_trace_links;
create policy requirement_trace_read on project.requirement_trace_links for select to authenticated using(project.can_access_project(project_id));
drop policy if exists requirement_trace_insert on project.requirement_trace_links;
create policy requirement_trace_insert on project.requirement_trace_links for insert to authenticated with check(project.can_access_project(project_id) and current_setting('conceptspaces.requirement_phase',true)='trace');

create or replace function public.interpret_project_brief(target_project_id uuid,input_payload jsonb)
returns uuid language plpgsql security invoker set search_path='feasibility','project','audit','extensions','auth','pg_temp' as $$
declare p project.projects%rowtype;tp feasibility.typology_packs%rowtype;b feasibility.brief_interpretations%rowtype;v int;h text;
begin
 select * into p from project.projects where id=target_project_id;
 if not found or auth.uid() is null or not project.can_access_project(p.id) then raise exception 'project_access_required';end if;
 if lower(coalesce(input_payload->>'source_type','text')) not in ('text','voice','document','meeting') or nullif(btrim(input_payload->>'raw_input'),'') is null or jsonb_typeof(coalesce(input_payload->'structured_draft','{}'::jsonb))<>'object' then raise exception 'brief_source_raw_structured_draft_required';end if;
 select * into tp from feasibility.typology_packs where id=nullif(input_payload->>'typology_pack_id','')::uuid and state='published';
 if not found then raise exception 'published_typology_pack_required';end if;
 select coalesce(max(version),0)+1 into v from feasibility.brief_interpretations where project_id=p.id;
 h:=encode(extensions.digest(jsonb_build_object('project_id',p.id,'version',v,'source_type',lower(coalesce(input_payload->>'source_type','text')),'raw_input',input_payload->>'raw_input','structured_draft',input_payload->'structured_draft','typology_pack_id',tp.id,'typology_pack_hash',tp.pack_hash)::text,'sha256'),'hex');
 perform set_config('conceptspaces.brief_phase','draft',true);
 insert into feasibility.brief_interpretations(project_id,typology_pack_id,version,source_type,raw_input,structured_draft,status,input_hash,created_by)
 values(p.id,tp.id,v,lower(coalesce(input_payload->>'source_type','text')),input_payload->>'raw_input',input_payload->'structured_draft','draft',h,auth.uid()) returning * into b;
 perform audit.append_event(p.organisation_id,p.id,'brief.interpreted','brief_interpretation',b.id,null,to_jsonb(b),h,gen_random_uuid());
 return b.id;
end;$$;
revoke all on function public.interpret_project_brief(uuid,jsonb) from public,anon;
grant execute on function public.interpret_project_brief(uuid,jsonb) to authenticated;

create or replace function public.confirm_project_brief(target_brief_id uuid,input_payload jsonb,target_reason text)
returns uuid language plpgsql security invoker set search_path='feasibility','project','audit','extensions','auth','pg_temp' as $$
declare b feasibility.brief_interpretations%rowtype;p project.projects%rowtype;pb feasibility.programme_briefs%rowtype;v int;confirmed jsonb;h text;
begin
 select * into b from feasibility.brief_interpretations where id=target_brief_id for update;
 if not found or b.status<>'draft' then raise exception 'draft_brief_required';end if;
 select * into p from project.projects where id=b.project_id;
 if auth.uid() is null or not project.can_manage_project(p.id) then raise exception 'project_manage_authority_required';end if;
 if nullif(btrim(target_reason),'') is null then raise exception 'brief_confirmation_reason_required';end if;
 confirmed:=coalesce(input_payload->'structured_brief',b.structured_draft);
 if jsonb_typeof(confirmed)<>'object' or confirmed='{}'::jsonb then raise exception 'confirmed_structured_brief_required';end if;
 h:=encode(extensions.digest(jsonb_build_object('input_hash',b.input_hash,'structured_brief',confirmed,'typology_pack_id',b.typology_pack_id)::text,'sha256'),'hex');
 select coalesce(max(version),0)+1 into v from feasibility.programme_briefs where project_id=p.id;
 perform set_config('conceptspaces.brief_phase','supersede',true);
 update feasibility.brief_interpretations set status='superseded',updated_at=now() where project_id=p.id and status='confirmed' and id<>b.id;
 update feasibility.programme_briefs set status='superseded',updated_at=now() where project_id=p.id and status='approved';
 perform set_config('conceptspaces.brief_phase','confirm',true);
 update feasibility.brief_interpretations set structured_draft=confirmed,status='confirmed',confirmed_hash=h,confirmed_by=auth.uid(),confirmed_at=now(),updated_at=now() where id=b.id returning * into b;
 insert into feasibility.programme_briefs(project_id,typology_pack_id,version,client_priorities,exclusions,target_efficiency,target_built_up_area,budget_band,status,created_by,approved_by,approved_at)
 values(p.id,b.typology_pack_id,v,coalesce(confirmed->'priorities','[]'::jsonb),coalesce(confirmed->'exclusions','[]'::jsonb),nullif(confirmed->>'target_efficiency','')::numeric,nullif(confirmed->>'target_built_up_area','')::numeric,nullif(confirmed->>'budget_band',''),'approved',b.created_by,auth.uid(),now()) returning * into pb;
 perform project.invalidate_compiler_runs(p.id,'Confirmed project brief changed',h);
 perform audit.append_event(p.organisation_id,p.id,'brief.confirmed','programme_brief',pb.id,null,to_jsonb(pb),h,gen_random_uuid());
 return pb.id;
end;$$;
revoke all on function public.confirm_project_brief(uuid,jsonb,text) from public,anon;
grant execute on function public.confirm_project_brief(uuid,jsonb,text) to authenticated;

create or replace function public.create_project_requirement(target_project_id uuid,input_payload jsonb)
returns uuid language plpgsql security invoker set search_path='project','audit','auth','pg_temp' as $$
declare p project.projects%rowtype;r project.requirements%rowtype;
begin
 select * into p from project.projects where id=target_project_id;
 if not found or auth.uid() is null or not project.can_access_project(p.id) then raise exception 'project_access_required';end if;
 if nullif(btrim(input_payload->>'code'),'') is null or nullif(btrim(input_payload->>'statement'),'') is null or nullif(btrim(input_payload->>'category'),'') is null or jsonb_typeof(coalesce(input_payload->'acceptance_criteria','[]'::jsonb))<>'array' then raise exception 'requirement_core_fields_required';end if;
 perform set_config('conceptspaces.requirement_phase','draft',true);
 insert into project.requirements(project_id,code,statement,category,source_truth_record_id,acceptance_criteria,status,criticality,owner_user_id,version,approval_state)
 values(p.id,btrim(input_payload->>'code'),btrim(input_payload->>'statement'),btrim(input_payload->>'category'),nullif(input_payload->>'source_truth_record_id','')::uuid,coalesce(input_payload->'acceptance_criteria','[]'::jsonb),'open',upper(coalesce(nullif(input_payload->>'criticality',''),'C1')),nullif(input_payload->>'owner_user_id','')::uuid,1,'draft') returning * into r;
 insert into project.requirement_revisions(requirement_id,project_id,version,statement,category,acceptance_criteria,criticality,source_truth_record_id,approval_state,created_by)
 values(r.id,p.id,1,r.statement,r.category,r.acceptance_criteria,r.criticality,r.source_truth_record_id,'draft',auth.uid());
 perform audit.append_event(p.organisation_id,p.id,'requirement.created','requirement',r.id,null,to_jsonb(r),null,gen_random_uuid());
 return r.id;
end;$$;
revoke all on function public.create_project_requirement(uuid,jsonb) from public,anon;
grant execute on function public.create_project_requirement(uuid,jsonb) to authenticated;

create or replace function public.approve_project_requirement(target_requirement_id uuid,target_reason text)
returns text language plpgsql security invoker set search_path='project','audit','extensions','auth','pg_temp' as $$
declare r project.requirements%rowtype;p project.projects%rowtype;h text;before_state jsonb;
begin
 select * into r from project.requirements where id=target_requirement_id for update;
 if not found or r.approval_state<>'draft' then raise exception 'draft_requirement_required';end if;
 select * into p from project.projects where id=r.project_id;
 if auth.uid() is null or not project.can_manage_project(p.id) then raise exception 'project_manage_authority_required';end if;
 if nullif(btrim(target_reason),'') is null then raise exception 'requirement_approval_reason_required';end if;
 h:=encode(extensions.digest(jsonb_build_object('requirement_id',r.id,'version',r.version,'code',r.code::text,'statement',r.statement,'category',r.category,'acceptance_criteria',r.acceptance_criteria,'criticality',r.criticality,'source_truth_record_id',r.source_truth_record_id)::text,'sha256'),'hex');
 before_state:=to_jsonb(r);
 perform set_config('conceptspaces.requirement_phase','approve',true);
 update project.requirements set approval_state='approved',requirement_hash=h,approved_by=auth.uid(),approved_at=now(),updated_at=now() where id=r.id returning * into r;
 update project.requirement_revisions set approval_state='approved',requirement_hash=h,approved_by=auth.uid(),approved_at=now() where requirement_id=r.id and version=r.version;
 perform project.invalidate_compiler_runs(p.id,'Approved requirement changed baseline: '||r.code::text,h);
 perform audit.append_event(p.organisation_id,p.id,'requirement.approved','requirement',r.id,before_state,to_jsonb(r),h,gen_random_uuid());
 return r.approval_state;
end;$$;
revoke all on function public.approve_project_requirement(uuid,text) from public,anon;
grant execute on function public.approve_project_requirement(uuid,text) to authenticated;

create or replace function public.revise_project_requirement(target_requirement_id uuid,input_payload jsonb,target_reason text)
returns jsonb language plpgsql security invoker set search_path='public','project','audit','auth','pg_temp' as $$
declare r project.requirements%rowtype;p project.projects%rowtype;old_snapshot jsonb;new_version int;change_id uuid;impact_id uuid;disciplines jsonb:=coalesce(input_payload->'affected_disciplines','[]'::jsonb);
begin
 select * into r from project.requirements where id=target_requirement_id for update;
 if not found or r.approval_state<>'approved' then raise exception 'approved_requirement_required';end if;
 select * into p from project.projects where id=r.project_id;
 if auth.uid() is null or not project.can_manage_project(p.id) then raise exception 'project_manage_authority_required';end if;
 if nullif(btrim(target_reason),'') is null or jsonb_typeof(disciplines)<>'array' or jsonb_array_length(disciplines)=0 then raise exception 'requirement_revision_reason_disciplines_required';end if;
 old_snapshot:=to_jsonb(r);new_version:=r.version+1;
 perform set_config('conceptspaces.requirement_phase','revise',true);
 update project.requirement_revisions set approval_state='superseded' where requirement_id=r.id and version=r.version;
 update project.requirements set version=new_version,statement=coalesce(nullif(btrim(input_payload->>'statement'),''),statement),category=coalesce(nullif(btrim(input_payload->>'category'),''),category),acceptance_criteria=case when input_payload ? 'acceptance_criteria' then input_payload->'acceptance_criteria' else acceptance_criteria end,criticality=upper(coalesce(nullif(input_payload->>'criticality',''),criticality)),approval_state='draft',requirement_hash=null,approved_by=null,approved_at=null,updated_at=now() where id=r.id returning * into r;
 insert into project.requirement_revisions(requirement_id,project_id,version,statement,category,acceptance_criteria,criticality,source_truth_record_id,approval_state,created_by)
 values(r.id,p.id,r.version,r.statement,r.category,r.acceptance_criteria,r.criticality,r.source_truth_record_id,'draft',auth.uid());
 change_id:=public.propose_project_change(jsonb_build_object('project_id',p.id,'title','Requirement revision '||r.code::text,'description',target_reason,'source_object_refs',jsonb_build_array('requirement:'||r.id::text||':v'||new_version::text),'proposed_disciplines',disciplines));
 impact_id:=public.analyze_project_change(change_id,jsonb_build_object('criticality',r.criticality,'confidence','A'));
 perform audit.append_event(p.organisation_id,p.id,'requirement.changed','requirement',r.id,old_snapshot,to_jsonb(r),target_reason,gen_random_uuid());
 return jsonb_build_object('requirement_id',r.id,'version',r.version,'change_request_id',change_id,'change_impact_id',impact_id);
end;$$;
revoke all on function public.revise_project_requirement(uuid,jsonb,text) from public,anon;
grant execute on function public.revise_project_requirement(uuid,jsonb,text) to authenticated;

create or replace function public.link_requirement_trace(target_requirement_id uuid,target_resource_type text,target_resource_ref text,target_evidence_hash text default null)
returns uuid language plpgsql security invoker set search_path='project','audit','auth','pg_temp' as $$
declare r project.requirements%rowtype;l project.requirement_trace_links%rowtype;t text:=lower(btrim(target_resource_type));
begin
 select * into r from project.requirements where id=target_requirement_id;
 if not found or auth.uid() is null or not project.can_access_project(r.project_id) then raise exception 'requirement_access_required';end if;
 if t not in ('model_object','drawing','test','document','model','calculation','boq','task','release') or nullif(btrim(target_resource_ref),'') is null then raise exception 'requirement_trace_target_required';end if;
 if target_evidence_hash is not null and lower(target_evidence_hash) !~ '^[0-9a-f]{64}$' then raise exception 'trace_evidence_hash_invalid';end if;
 perform set_config('conceptspaces.requirement_phase','trace',true);
 insert into project.requirement_trace_links(requirement_id,project_id,resource_type,resource_ref,evidence_hash,created_by)
 values(r.id,r.project_id,t,btrim(target_resource_ref),lower(target_evidence_hash),auth.uid()) on conflict(requirement_id,resource_type,resource_ref) do nothing;
 select * into l from project.requirement_trace_links where requirement_id=r.id and resource_type=t and resource_ref=btrim(target_resource_ref);
 perform audit.append_event((select organisation_id from project.projects where id=r.project_id),r.project_id,'requirement.trace_linked','requirement_trace',l.id,null,to_jsonb(l),coalesce(l.evidence_hash,l.resource_ref),gen_random_uuid());
 return l.id;
end;$$;
revoke all on function public.link_requirement_trace(uuid,text,text,text) from public,anon;
grant execute on function public.link_requirement_trace(uuid,text,text,text) to authenticated;

create or replace function public.list_brief_requirement_workspace(target_project_id uuid)
returns jsonb language plpgsql stable security invoker set search_path='feasibility','project','auth','pg_temp' as $$
begin
 if auth.uid() is null or not project.can_access_project(target_project_id) then raise exception 'project_access_required';end if;
 return jsonb_build_object(
  'typology_packs',coalesce((select jsonb_agg(jsonb_build_object('id',t.id,'code',t.code::text,'name',t.name,'typology',t.typology,'version',t.version,'questionnaire',t.questionnaire,'pack_hash',t.pack_hash) order by t.typology) from feasibility.typology_packs t where t.state='published'),'[]'::jsonb),
  'briefs',coalesce((select jsonb_agg(to_jsonb(b) order by b.version desc) from feasibility.brief_interpretations b where b.project_id=target_project_id),'[]'::jsonb),
  'programme_briefs',coalesce((select jsonb_agg(to_jsonb(p) order by p.version desc) from feasibility.programme_briefs p where p.project_id=target_project_id),'[]'::jsonb),
  'requirements',coalesce((select jsonb_agg(to_jsonb(r) order by r.code) from project.requirements r where r.project_id=target_project_id),'[]'::jsonb),
  'revisions',coalesce((select jsonb_agg(to_jsonb(v) order by v.requirement_id,v.version desc) from project.requirement_revisions v where v.project_id=target_project_id),'[]'::jsonb),
  'trace_links',coalesce((select jsonb_agg(to_jsonb(l) order by l.created_at desc) from project.requirement_trace_links l where l.project_id=target_project_id),'[]'::jsonb)
 );
end;$$;
revoke all on function public.list_brief_requirement_workspace(uuid) from public,anon;
grant execute on function public.list_brief_requirement_workspace(uuid) to authenticated;

commit;
