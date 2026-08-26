begin;

alter table workflow.jobs
 add column if not exists idempotency_key text,
 add column if not exists trace_id uuid not null default gen_random_uuid(),
 add column if not exists engine_id text,
 add column if not exists engine_version text,
 add column if not exists input_hash text,
 add column if not exists output_hash text,
 add column if not exists retry_count integer not null default 0,
 add column if not exists max_retries integer not null default 3,
 add column if not exists quarantine_reason text,
 add column if not exists quarantined_at timestamptz,
 add column if not exists cancelled_by uuid references auth.users(id) on delete set null;

alter table workflow.jobs drop constraint if exists jobs_status_check;
alter table workflow.jobs add constraint jobs_status_check check(status in ('queued','running','awaiting_approval','succeeded','failed','cancelled','quarantined'));
alter table workflow.jobs drop constraint if exists jobs_retry_count_check;
alter table workflow.jobs add constraint jobs_retry_count_check check(retry_count>=0 and max_retries>=0 and retry_count<=max_retries);
create unique index if not exists workflow_jobs_idempotency_uidx on workflow.jobs(organisation_id,job_type,idempotency_key) where idempotency_key is not null;
create index if not exists workflow_jobs_trace_idx on workflow.jobs(trace_id);

create or replace function workflow.guard_job_immutable_input()
returns trigger language plpgsql security definer set search_path='workflow','pg_temp' as $$
begin
 if new.organisation_id is distinct from old.organisation_id or new.project_id is distinct from old.project_id or new.job_type is distinct from old.job_type or new.criticality is distinct from old.criticality or new.autonomy_level is distinct from old.autonomy_level or new.input is distinct from old.input or new.idempotency_key is distinct from old.idempotency_key or new.trace_id is distinct from old.trace_id or new.engine_id is distinct from old.engine_id or new.engine_version is distinct from old.engine_version or new.input_hash is distinct from old.input_hash or new.created_by is distinct from old.created_by then raise exception 'COMPUTE_JOB_IMMUTABLE_INPUT';end if;return new;end;$$;
revoke all on function workflow.guard_job_immutable_input() from public,anon,authenticated;
drop trigger if exists trg_guard_job_immutable_input on workflow.jobs;
create trigger trg_guard_job_immutable_input before update on workflow.jobs for each row execute function workflow.guard_job_immutable_input();

grant insert,update on workflow.jobs to authenticated;
drop policy if exists jobs_governed_insert on workflow.jobs;
create policy jobs_governed_insert on workflow.jobs for insert to authenticated with check(current_setting('conceptspaces.sre_phase',true)='job_create' and created_by=auth.uid() and core.is_org_member(organisation_id) and (project_id is null or project.can_access_project(project_id)));
drop policy if exists jobs_governed_update on workflow.jobs;
create policy jobs_governed_update on workflow.jobs for update to authenticated using(core.is_org_member(organisation_id) and (project_id is null or project.can_access_project(project_id))) with check(current_setting('conceptspaces.sre_phase',true) in ('job_transition','job_retry','job_quarantine','job_cancel') and core.is_org_member(organisation_id) and (project_id is null or project.can_access_project(project_id)));

alter table public.incidents add column if not exists trace_id uuid not null default gen_random_uuid(), add column if not exists resolution_evidence_refs jsonb not null default '[]'::jsonb, add column if not exists resolution_hash text;
alter table public.backup_restore_drills add column if not exists created_by uuid references auth.users(id) on delete set null, add column if not exists verified_by uuid references auth.users(id) on delete set null, add column if not exists correlation_id uuid not null default gen_random_uuid(), add column if not exists drill_hash text;

grant insert,update on public.incidents,public.backup_restore_drills to authenticated;
drop policy if exists incidents_governed_insert on public.incidents;
create policy incidents_governed_insert on public.incidents for insert to authenticated with check(core.is_platform_admin() and current_setting('conceptspaces.sre_phase',true)='incident_create');
drop policy if exists incidents_governed_update on public.incidents;
create policy incidents_governed_update on public.incidents for update to authenticated using(core.is_platform_admin()) with check(core.is_platform_admin() and current_setting('conceptspaces.sre_phase',true)='incident_transition');
drop policy if exists drills_governed_insert on public.backup_restore_drills;
create policy drills_governed_insert on public.backup_restore_drills for insert to authenticated with check(core.is_platform_admin() and created_by=auth.uid() and current_setting('conceptspaces.sre_phase',true)='dr_create');
drop policy if exists drills_governed_update on public.backup_restore_drills;
create policy drills_governed_update on public.backup_restore_drills for update to authenticated using(core.is_platform_admin()) with check(core.is_platform_admin() and current_setting('conceptspaces.sre_phase',true)='dr_complete');

create table if not exists operations.service_slos(
 id uuid primary key default gen_random_uuid(),
 service text not null,
 metric_key text not null,
 target_operator text not null check(target_operator in ('gte','lte')),
 target_value numeric not null,
 unit text not null,
 window_minutes integer not null check(window_minutes>0),
 status text not null default 'active' check(status in ('draft','active','superseded')),
 version integer not null default 1,
 supersedes_id uuid references operations.service_slos(id) on delete set null,
 created_by uuid not null references auth.users(id),
 approved_by uuid references auth.users(id),
 approved_at timestamptz,
 created_at timestamptz not null default now(),
 slo_hash text not null,
 unique(service,metric_key,version)
);
create table if not exists operations.service_telemetry(
 id uuid primary key default gen_random_uuid(),
 service text not null,
 metric_key text not null,
 metric_value numeric not null,
 unit text not null,
 source text not null,
 trace_id uuid,
 observed_at timestamptz not null default now(),
 evidence_hash text not null,
 created_by uuid references auth.users(id)
);
alter table operations.service_slos enable row level security;alter table operations.service_telemetry enable row level security;
grant select,insert,update on operations.service_slos to authenticated;grant select,insert on operations.service_telemetry to authenticated;
drop policy if exists sre_slo_read on operations.service_slos;create policy sre_slo_read on operations.service_slos for select to authenticated using(core.is_platform_admin());
drop policy if exists sre_slo_write on operations.service_slos;create policy sre_slo_write on operations.service_slos for insert to authenticated with check(core.is_platform_admin() and created_by=auth.uid() and current_setting('conceptspaces.sre_phase',true)='slo_create');
drop policy if exists sre_slo_update on operations.service_slos;create policy sre_slo_update on operations.service_slos for update to authenticated using(core.is_platform_admin()) with check(core.is_platform_admin() and current_setting('conceptspaces.sre_phase',true)='slo_approve');
drop policy if exists sre_telemetry_read on operations.service_telemetry;create policy sre_telemetry_read on operations.service_telemetry for select to authenticated using(core.is_platform_admin());
drop policy if exists sre_telemetry_write on operations.service_telemetry;create policy sre_telemetry_write on operations.service_telemetry for insert to authenticated with check(core.is_platform_admin() and current_setting('conceptspaces.sre_phase',true)='telemetry');

create or replace function public.create_compute_job(target_organisation_id uuid,target_project_id uuid,target_job_type text,input_payload jsonb,target_idempotency_key text,target_engine_id text,target_engine_version text,target_criticality text default 'C1',target_autonomy_level text default 'ai_draft')
returns uuid language plpgsql security invoker set search_path='workflow','project','core','audit','extensions','auth','pg_temp' as $$
declare j workflow.jobs%rowtype;h text;existing workflow.jobs%rowtype;
begin
 if auth.uid() is null or not core.is_org_member(target_organisation_id) or (target_project_id is not null and not project.can_access_project(target_project_id)) then raise exception 'job_authority_required';end if;
 if nullif(btrim(target_job_type),'') is null or nullif(btrim(target_idempotency_key),'') is null or nullif(btrim(target_engine_id),'') is null or nullif(btrim(target_engine_version),'') is null then raise exception 'job_contract_fields_required';end if;
 h:=encode(extensions.digest(jsonb_build_object('organisation_id',target_organisation_id,'project_id',target_project_id,'job_type',btrim(target_job_type),'input',coalesce(input_payload,'{}'::jsonb),'engine_id',btrim(target_engine_id),'engine_version',btrim(target_engine_version),'criticality',target_criticality,'autonomy',target_autonomy_level)::text,'sha256'),'hex');
 select * into existing from workflow.jobs where organisation_id=target_organisation_id and job_type=btrim(target_job_type) and idempotency_key=btrim(target_idempotency_key) limit 1;
 if found then if existing.input_hash<>h then raise exception 'IDEMPOTENCY_CONFLICT';end if;return existing.id;end if;
 perform set_config('conceptspaces.sre_phase','job_create',true);
 insert into workflow.jobs(organisation_id,project_id,job_type,status,criticality,autonomy_level,input,correlation_id,created_by,idempotency_key,trace_id,engine_id,engine_version,input_hash)
 values(target_organisation_id,target_project_id,btrim(target_job_type),'queued',target_criticality,target_autonomy_level,coalesce(input_payload,'{}'::jsonb),gen_random_uuid(),auth.uid(),btrim(target_idempotency_key),gen_random_uuid(),btrim(target_engine_id),btrim(target_engine_version),h) returning * into j;
 perform audit.append_event(target_organisation_id,target_project_id,'job.created','compute_job',j.id,null,jsonb_build_object('job_type',j.job_type,'status',j.status,'input_hash',h,'trace_id',j.trace_id,'engine_id',j.engine_id,'engine_version',j.engine_version),h,j.correlation_id);return j.id;
end;$$;
revoke all on function public.create_compute_job(uuid,uuid,text,jsonb,text,text,text,text,text) from public,anon;grant execute on function public.create_compute_job(uuid,uuid,text,jsonb,text,text,text,text,text) to authenticated;

create or replace function public.complete_compute_job(target_job_id uuid,target_status text,target_output jsonb,target_error jsonb default null)
returns text language plpgsql security invoker set search_path='workflow','core','audit','extensions','auth','pg_temp' as $$
declare j workflow.jobs%rowtype;s text:=lower(btrim(target_status));before_state jsonb;oh text;
begin select * into j from workflow.jobs where id=target_job_id for update;if not found then raise exception 'job_not_found';end if;if auth.uid() is null or not core.is_org_member(j.organisation_id) then raise exception 'job_authority_required';end if;if j.status not in ('queued','running','awaiting_approval') or s not in ('succeeded','failed') then raise exception 'job_transition_invalid';end if;if s='succeeded' and target_output is null then raise exception 'job_output_required';end if;oh:=case when target_output is null then null else encode(extensions.digest(target_output::text,'sha256'),'hex') end;before_state:=to_jsonb(j);perform set_config('conceptspaces.sre_phase','job_transition',true);update workflow.jobs set status=s,output=target_output,error=target_error,output_hash=oh,started_at=coalesce(started_at,now()),finished_at=now() where id=j.id returning * into j;perform audit.append_event(j.organisation_id,j.project_id,'job.'||s,'compute_job',j.id,before_state,jsonb_build_object('status',j.status,'output_hash',j.output_hash,'trace_id',j.trace_id,'error',j.error),coalesce(oh,j.input_hash),j.correlation_id);return j.status;end;$$;
revoke all on function public.complete_compute_job(uuid,text,jsonb,jsonb) from public,anon;grant execute on function public.complete_compute_job(uuid,text,jsonb,jsonb) to authenticated;

create or replace function public.retry_compute_job(target_job_id uuid,target_reason text)
returns text language plpgsql security invoker set search_path='workflow','core','audit','auth','pg_temp' as $$
declare j workflow.jobs%rowtype;before_state jsonb;
begin select * into j from workflow.jobs where id=target_job_id for update;if not found then raise exception 'job_not_found';end if;if auth.uid() is null or not core.is_org_member(j.organisation_id) then raise exception 'job_authority_required';end if;if j.status<>'failed' or j.retry_count>=j.max_retries then raise exception 'JOB_RETRY_EXHAUSTED';end if;if nullif(btrim(target_reason),'') is null then raise exception 'job_retry_reason_required';end if;before_state:=to_jsonb(j);perform set_config('conceptspaces.sre_phase','job_retry',true);update workflow.jobs set status='queued',retry_count=retry_count+1,error=null,started_at=null,finished_at=null where id=j.id returning * into j;perform audit.append_event(j.organisation_id,j.project_id,'job.retried','compute_job',j.id,before_state,jsonb_build_object('status',j.status,'retry_count',j.retry_count,'input_hash',j.input_hash,'trace_id',j.trace_id),target_reason,j.correlation_id);return j.status;end;$$;
revoke all on function public.retry_compute_job(uuid,text) from public,anon;grant execute on function public.retry_compute_job(uuid,text) to authenticated;

create or replace function public.quarantine_compute_job(target_job_id uuid,target_reason text)
returns text language plpgsql security invoker set search_path='workflow','core','audit','auth','pg_temp' as $$
declare j workflow.jobs%rowtype;before_state jsonb;
begin select * into j from workflow.jobs where id=target_job_id for update;if not found then raise exception 'job_not_found';end if;if auth.uid() is null or not core.is_org_member(j.organisation_id) then raise exception 'job_authority_required';end if;if j.status in ('succeeded','cancelled','quarantined') or nullif(btrim(target_reason),'') is null then raise exception 'job_not_quarantinable';end if;before_state:=to_jsonb(j);perform set_config('conceptspaces.sre_phase','job_quarantine',true);update workflow.jobs set status='quarantined',quarantine_reason=btrim(target_reason),quarantined_at=now(),finished_at=coalesce(finished_at,now()) where id=j.id returning * into j;perform audit.append_event(j.organisation_id,j.project_id,'job.quarantined','compute_job',j.id,before_state,jsonb_build_object('status',j.status,'trace_id',j.trace_id,'input_hash',j.input_hash),target_reason,j.correlation_id);return j.status;end;$$;
revoke all on function public.quarantine_compute_job(uuid,text) from public,anon;grant execute on function public.quarantine_compute_job(uuid,text) to authenticated;

create or replace function public.declare_platform_incident(input_payload jsonb)
returns uuid language plpgsql security invoker set search_path='public','core','audit','extensions','auth','pg_temp' as $$
declare r public.incidents%rowtype;num text;sev text:=upper(btrim(input_payload->>'severity'));
begin if auth.uid() is null or not core.is_platform_admin() then raise exception 'platform_admin_required';end if;if sev not in ('SEV0','SEV1','SEV2','SEV3') or nullif(btrim(input_payload->>'title'),'') is null or nullif(btrim(input_payload->>'customer_impact'),'') is null then raise exception 'incident_fields_invalid';end if;num:='INC-'||upper(substr(replace(gen_random_uuid()::text,'-',''),1,10));perform set_config('conceptspaces.sre_phase','incident_create',true);insert into public.incidents(number,title,severity,status,service_refs,started_at,detected_at,commander_user_id,customer_impact,regulatory_impact,timeline_refs,trace_id) values(num,btrim(input_payload->>'title'),sev,'declared',coalesce(input_payload->'service_refs','[]'::jsonb),coalesce(nullif(input_payload->>'started_at','')::timestamptz,now()),now(),auth.uid(),btrim(input_payload->>'customer_impact'),nullif(btrim(input_payload->>'regulatory_impact'),''),'[]'::jsonb,gen_random_uuid()) returning * into r;perform audit.append_event((select organisation_id from core.memberships where user_id=auth.uid() and status='active' limit 1),null,'incident.declared','incident',r.id,null,jsonb_build_object('number',r.number,'severity',r.severity,'status',r.status,'trace_id',r.trace_id),null,r.trace_id);return r.id;end;$$;
revoke all on function public.declare_platform_incident(jsonb) from public,anon;grant execute on function public.declare_platform_incident(jsonb) to authenticated;

create or replace function public.transition_platform_incident(target_incident_id uuid,target_status text,input_payload jsonb default '{}'::jsonb)
returns text language plpgsql security invoker set search_path='public','core','audit','extensions','auth','pg_temp' as $$
declare r public.incidents%rowtype;s text:=lower(btrim(target_status));before_state jsonb;h text;org_id uuid;
begin select * into r from public.incidents where id=target_incident_id for update;if not found then raise exception 'incident_not_found';end if;if auth.uid() is null or not core.is_platform_admin() then raise exception 'platform_admin_required';end if;if s not in ('mitigating','monitoring','resolved','postmortem','closed') then raise exception 'incident_status_invalid';end if;if s='closed' and r.severity in ('SEV0','SEV1') and (nullif(btrim(input_payload->>'postmortem_ref'),'') is null or jsonb_array_length(coalesce(input_payload->'resolution_evidence_refs','[]'::jsonb))=0) then raise exception 'critical_incident_postmortem_and_evidence_required';end if;before_state:=to_jsonb(r);h:=encode(extensions.digest(jsonb_build_object('incident_id',r.id,'from',r.status,'to',s,'postmortem_ref',coalesce(input_payload->>'postmortem_ref',r.postmortem_ref),'evidence',coalesce(input_payload->'resolution_evidence_refs',r.resolution_evidence_refs))::text,'sha256'),'hex');perform set_config('conceptspaces.sre_phase','incident_transition',true);update public.incidents set status=s,mitigated_at=case when s='mitigating' then coalesce(mitigated_at,now()) else mitigated_at end,resolved_at=case when s in ('resolved','postmortem','closed') then coalesce(resolved_at,now()) else resolved_at end,postmortem_ref=coalesce(nullif(btrim(input_payload->>'postmortem_ref'),''),postmortem_ref),resolution_evidence_refs=case when input_payload ? 'resolution_evidence_refs' then input_payload->'resolution_evidence_refs' else resolution_evidence_refs end,resolution_hash=h,updated_at=now() where id=r.id returning * into r;select organisation_id into org_id from core.memberships where user_id=auth.uid() and status='active' limit 1;if org_id is not null then perform audit.append_event(org_id,null,'incident.'||s,'incident',r.id,before_state,jsonb_build_object('number',r.number,'status',r.status,'resolution_hash',r.resolution_hash,'trace_id',r.trace_id),h,r.trace_id);end if;return r.status;end;$$;
revoke all on function public.transition_platform_incident(uuid,text,jsonb) from public,anon;grant execute on function public.transition_platform_incident(uuid,text,jsonb) to authenticated;

create or replace function public.start_restore_drill(input_payload jsonb)
returns uuid language plpgsql security invoker set search_path='public','core','audit','extensions','auth','pg_temp' as $$
declare r public.backup_restore_drills%rowtype;org_id uuid;h text;
begin if auth.uid() is null or not core.is_platform_admin() then raise exception 'platform_admin_required';end if;if nullif(btrim(input_payload->>'service'),'') is null or nullif(btrim(input_payload->>'backup_ref'),'') is null or lower(btrim(input_payload->>'environment')) not in ('test','staging') or coalesce(nullif(input_payload->>'rpo_minutes_target','')::int,0)<=0 or coalesce(nullif(input_payload->>'rto_minutes_target','')::int,0)<=0 then raise exception 'restore_drill_fields_invalid';end if;h:=encode(extensions.digest(jsonb_build_object('service',btrim(input_payload->>'service'),'backup_ref',btrim(input_payload->>'backup_ref'),'environment',lower(btrim(input_payload->>'environment')),'rpo',(input_payload->>'rpo_minutes_target')::int,'rto',(input_payload->>'rto_minutes_target')::int,'started_by',auth.uid())::text,'sha256'),'hex');perform set_config('conceptspaces.sre_phase','dr_create',true);insert into public.backup_restore_drills(service,backup_ref,environment,started_at,rpo_minutes_target,rto_minutes_target,status,evidence_refs,created_by,correlation_id,drill_hash) values(btrim(input_payload->>'service'),btrim(input_payload->>'backup_ref'),lower(btrim(input_payload->>'environment')),now(),(input_payload->>'rpo_minutes_target')::int,(input_payload->>'rto_minutes_target')::int,'running','[]'::jsonb,auth.uid(),gen_random_uuid(),h) returning * into r;select organisation_id into org_id from core.memberships where user_id=auth.uid() and status='active' limit 1;if org_id is not null then perform audit.append_event(org_id,null,'dr.test_started','backup_restore_drill',r.id,null,to_jsonb(r),h,r.correlation_id);end if;return r.id;end;$$;
revoke all on function public.start_restore_drill(jsonb) from public,anon;grant execute on function public.start_restore_drill(jsonb) to authenticated;

create or replace function public.complete_restore_drill(target_drill_id uuid,input_payload jsonb)
returns text language plpgsql security invoker set search_path='public','core','audit','extensions','auth','pg_temp' as $$
declare r public.backup_restore_drills%rowtype;before_state jsonb;evidence jsonb:=coalesce(input_payload->'evidence_refs','[]'::jsonb);checks jsonb:=coalesce(input_payload->'integrity_checks','[]'::jsonb);arpo int:=nullif(input_payload->>'achieved_rpo_minutes','')::int;arto int:=nullif(input_payload->>'achieved_rto_minutes','')::int;result text;h text;org_id uuid;
begin select * into r from public.backup_restore_drills where id=target_drill_id for update;if not found then raise exception 'restore_drill_not_found';end if;if auth.uid() is null or not core.is_platform_admin() then raise exception 'platform_admin_required';end if;if r.status<>'running' or arpo is null or arto is null or arpo<0 or arto<0 or jsonb_array_length(evidence)=0 or jsonb_array_length(checks)=0 then raise exception 'restore_drill_completion_evidence_required';end if;result:=case when arpo<=r.rpo_minutes_target and arto<=r.rto_minutes_target then 'pass' else 'fail' end;h:=encode(extensions.digest(jsonb_build_object('start_hash',r.drill_hash,'achieved_rpo',arpo,'achieved_rto',arto,'checks',checks,'evidence',evidence,'result',result)::text,'sha256'),'hex');before_state:=to_jsonb(r);perform set_config('conceptspaces.sre_phase','dr_complete',true);update public.backup_restore_drills set completed_at=now(),achieved_rpo_minutes=arpo,achieved_rto_minutes=arto,integrity_checks=checks,status=result,evidence_refs=evidence,verified_by=auth.uid(),drill_hash=h where id=r.id returning * into r;select organisation_id into org_id from core.memberships where user_id=auth.uid() and status='active' limit 1;if org_id is not null then perform audit.append_event(org_id,null,'dr.test_completed','backup_restore_drill',r.id,before_state,to_jsonb(r),h,r.correlation_id);end if;return r.status;end;$$;
revoke all on function public.complete_restore_drill(uuid,jsonb) from public,anon;grant execute on function public.complete_restore_drill(uuid,jsonb) to authenticated;

create or replace function public.list_sre_workspace(target_organisation_id uuid)
returns jsonb language plpgsql stable security invoker set search_path='workflow','operations','public','core','project','auth','pg_temp' as $$
begin if auth.uid() is null or not core.is_org_member(target_organisation_id) then raise exception 'organisation_access_required';end if;return jsonb_build_object('jobs',coalesce((select jsonb_agg(to_jsonb(j) order by j.created_at desc) from workflow.jobs j where j.organisation_id=target_organisation_id and (j.project_id is null or project.can_access_project(j.project_id)) limit 100),'[]'::jsonb),'providers',coalesce((select jsonb_agg(to_jsonb(h) order by h.provider_key) from (select distinct on (provider_key,environment) * from public.provider_health_checks where organisation_id=target_organisation_id or organisation_id is null order by provider_key,environment,checked_at desc) h),'[]'::jsonb),'slos',case when core.is_platform_admin() then coalesce((select jsonb_agg(to_jsonb(s) order by s.service,s.metric_key,s.version desc) from operations.service_slos s),'[]'::jsonb) else '[]'::jsonb end,'incidents',case when core.is_platform_admin() then coalesce((select jsonb_agg(to_jsonb(i) order by i.detected_at desc) from public.incidents i limit 100),'[]'::jsonb) else '[]'::jsonb end,'drills',case when core.is_platform_admin() then coalesce((select jsonb_agg(to_jsonb(d) order by d.started_at desc) from public.backup_restore_drills d limit 50),'[]'::jsonb) else '[]'::jsonb end);end;$$;
revoke all on function public.list_sre_workspace(uuid) from public,anon;grant execute on function public.list_sre_workspace(uuid) to authenticated;

commit;
