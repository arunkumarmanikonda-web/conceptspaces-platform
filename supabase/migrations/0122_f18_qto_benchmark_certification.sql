begin;

alter table cost.qto_runs add column if not exists engine_ref text;
alter table cost.qto_runs add column if not exists engine_version text;
alter table cost.qto_runs add column if not exists benchmark_result_id uuid;

create table if not exists cost.qto_benchmark_cases(
  id uuid primary key default gen_random_uuid(),
  code text not null unique,
  name text not null,
  benchmark_model_ref text not null,
  benchmark_model_checksum text not null,
  measurement_rule_set_ref text not null,
  expected_quantities jsonb not null,
  default_tolerance jsonb not null default '{"absolute":0,"percent":0}'::jsonb,
  status text not null default 'draft' check(status in ('draft','approved','retired')),
  case_hash text not null,
  created_by uuid references auth.users(id) on delete set null,
  approved_by uuid references auth.users(id) on delete set null,
  approved_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists cost.qto_benchmark_results(
  id uuid primary key default gen_random_uuid(),
  case_id uuid not null references cost.qto_benchmark_cases(id) on delete restrict,
  engine_ref text not null,
  engine_version text not null,
  actual_quantities jsonb not null,
  findings jsonb not null default '[]'::jsonb,
  passed boolean not null,
  result_hash text not null,
  status text not null default 'recorded' check(status in ('recorded','approved','rejected','superseded')),
  created_by uuid references auth.users(id) on delete set null,
  reviewed_by uuid references auth.users(id) on delete set null,
  reviewed_at timestamptz,
  created_at timestamptz not null default now()
);

alter table cost.qto_benchmark_cases enable row level security;
alter table cost.qto_benchmark_results enable row level security;
grant select on cost.qto_benchmark_cases,cost.qto_benchmark_results to authenticated;
grant insert,update on cost.qto_benchmark_cases,cost.qto_benchmark_results to authenticated;

create policy qto_benchmark_case_read on cost.qto_benchmark_cases for select to authenticated using(true);
create policy qto_benchmark_case_insert on cost.qto_benchmark_cases for insert to authenticated with check(core.is_platform_admin() and created_by=auth.uid() and current_setting('conceptspaces.qto_benchmark_phase',true)='case_create');
create policy qto_benchmark_case_update on cost.qto_benchmark_cases for update to authenticated using(core.is_platform_admin()) with check(core.is_platform_admin() and current_setting('conceptspaces.qto_benchmark_phase',true)='case_review');
create policy qto_benchmark_result_read on cost.qto_benchmark_results for select to authenticated using(true);
create policy qto_benchmark_result_insert on cost.qto_benchmark_results for insert to authenticated with check(core.is_platform_admin() and created_by=auth.uid() and current_setting('conceptspaces.qto_benchmark_phase',true)='result_record');
create policy qto_benchmark_result_update on cost.qto_benchmark_results for update to authenticated using(core.is_platform_admin()) with check(core.is_platform_admin() and current_setting('conceptspaces.qto_benchmark_phase',true)='result_review');

create or replace function public.create_qto_benchmark_case(input_payload jsonb)
returns uuid language plpgsql security invoker set search_path='cost','core','audit','extensions','auth','pg_temp' as $$
declare c cost.qto_benchmark_cases%rowtype; expected jsonb:=coalesce(input_payload->'expected_quantities','[]'::jsonb); tol jsonb:=coalesce(input_payload->'default_tolerance','{"absolute":0,"percent":0}'::jsonb); h text; org_id uuid;
begin
 if auth.uid() is null or not core.is_platform_admin() then raise exception 'platform_admin_required';end if;
 if nullif(btrim(input_payload->>'code'),'') is null or nullif(btrim(input_payload->>'name'),'') is null or nullif(btrim(input_payload->>'benchmark_model_ref'),'') is null or lower(coalesce(input_payload->>'benchmark_model_checksum','')) !~ '^[0-9a-f]{64}$' or nullif(btrim(input_payload->>'measurement_rule_set_ref'),'') is null then raise exception 'qto_benchmark_identity_required';end if;
 if jsonb_typeof(expected)<>'array' or jsonb_array_length(expected)=0 then raise exception 'qto_benchmark_expected_quantities_required';end if;
 if jsonb_typeof(tol)<>'object' or coalesce((tol->>'absolute')::numeric,0)<0 or coalesce((tol->>'percent')::numeric,0)<0 then raise exception 'qto_benchmark_tolerance_invalid';end if;
 if exists(select 1 from jsonb_array_elements(expected) x where nullif(btrim(x->>'code'),'') is null or nullif(btrim(x->>'unit'),'') is null or nullif(x->>'quantity','')::numeric is null or (x->>'quantity')::numeric<0) then raise exception 'qto_benchmark_expected_quantity_invalid';end if;
 if (select count(*) from jsonb_array_elements(expected))<>(select count(distinct x->>'code') from jsonb_array_elements(expected) x) then raise exception 'qto_benchmark_duplicate_code';end if;
 h:=encode(extensions.digest(jsonb_build_object('code',upper(btrim(input_payload->>'code')),'name',btrim(input_payload->>'name'),'benchmark_model_ref',btrim(input_payload->>'benchmark_model_ref'),'benchmark_model_checksum',lower(input_payload->>'benchmark_model_checksum'),'measurement_rule_set_ref',btrim(input_payload->>'measurement_rule_set_ref'),'expected_quantities',expected,'default_tolerance',tol)::text,'sha256'),'hex');
 perform set_config('conceptspaces.qto_benchmark_phase','case_create',true);
 insert into cost.qto_benchmark_cases(code,name,benchmark_model_ref,benchmark_model_checksum,measurement_rule_set_ref,expected_quantities,default_tolerance,status,case_hash,created_by) values(upper(btrim(input_payload->>'code')),btrim(input_payload->>'name'),btrim(input_payload->>'benchmark_model_ref'),lower(input_payload->>'benchmark_model_checksum'),btrim(input_payload->>'measurement_rule_set_ref'),expected,tol,'draft',h,auth.uid()) returning * into c;
 select organisation_id into org_id from core.memberships where user_id=auth.uid() and status='active' limit 1;if org_id is not null then perform audit.append_event(org_id,null,'cost.qto_benchmark_case_created','qto_benchmark_case',c.id,null,to_jsonb(c),h,gen_random_uuid());end if;return c.id;
end;$$;
revoke all on function public.create_qto_benchmark_case(jsonb) from public,anon;grant execute on function public.create_qto_benchmark_case(jsonb) to authenticated;

create or replace function public.approve_qto_benchmark_case(target_case_id uuid,target_reason text)
returns text language plpgsql security invoker set search_path='cost','core','audit','auth','pg_temp' as $$
declare c cost.qto_benchmark_cases%rowtype; before_state jsonb; org_id uuid;
begin select * into c from cost.qto_benchmark_cases where id=target_case_id for update;if not found or auth.uid() is null or not core.is_platform_admin() then raise exception 'platform_admin_required';end if;if c.status<>'draft' or c.created_by=auth.uid() then raise exception 'independent_qto_benchmark_case_approval_required';end if;if nullif(btrim(target_reason),'') is null then raise exception 'benchmark_approval_reason_required';end if;before_state:=to_jsonb(c);perform set_config('conceptspaces.qto_benchmark_phase','case_review',true);update cost.qto_benchmark_cases set status='approved',approved_by=auth.uid(),approved_at=now(),updated_at=now() where id=c.id returning * into c;select organisation_id into org_id from core.memberships where user_id=auth.uid() and status='active' limit 1;if org_id is not null then perform audit.append_event(org_id,null,'cost.qto_benchmark_case_approved','qto_benchmark_case',c.id,before_state,to_jsonb(c),target_reason,gen_random_uuid());end if;return c.status;end;$$;
revoke all on function public.approve_qto_benchmark_case(uuid,text) from public,anon;grant execute on function public.approve_qto_benchmark_case(uuid,text) to authenticated;

create or replace function public.record_qto_benchmark_result(target_case_id uuid,target_engine_ref text,target_engine_version text,target_actual_quantities jsonb)
returns uuid language plpgsql security invoker set search_path='cost','core','audit','extensions','auth','pg_temp' as $$
declare c cost.qto_benchmark_cases%rowtype; r cost.qto_benchmark_results%rowtype; exp jsonb; act jsonb; findings jsonb:='[]'::jsonb; code_value text; exp_qty numeric; act_qty numeric; abs_tol numeric; pct_tol numeric; allowed_delta numeric; h text; org_id uuid;
begin
 select * into c from cost.qto_benchmark_cases where id=target_case_id and status='approved';if not found or auth.uid() is null or not core.is_platform_admin() then raise exception 'approved_qto_benchmark_case_required';end if;if nullif(btrim(target_engine_ref),'') is null or nullif(btrim(target_engine_version),'') is null then raise exception 'qto_engine_identity_required';end if;if jsonb_typeof(target_actual_quantities)<>'array' then raise exception 'qto_benchmark_actual_quantities_array_required';end if;
 for exp in select value from jsonb_array_elements(c.expected_quantities) loop code_value:=exp->>'code';exp_qty:=(exp->>'quantity')::numeric;select value into act from jsonb_array_elements(target_actual_quantities) where value->>'code'=code_value limit 1;if act is null then findings:=findings||jsonb_build_array(jsonb_build_object('code',code_value,'failure','MISSING_QUANTITY'));continue;end if;if lower(act->>'unit')<>lower(exp->>'unit') then findings:=findings||jsonb_build_array(jsonb_build_object('code',code_value,'failure','UNIT_MISMATCH','expected_unit',exp->>'unit','actual_unit',act->>'unit'));continue;end if;act_qty:=nullif(act->>'quantity','')::numeric;if act_qty is null then findings:=findings||jsonb_build_array(jsonb_build_object('code',code_value,'failure','ACTUAL_QUANTITY_INVALID'));continue;end if;abs_tol:=coalesce(nullif(exp->>'tolerance_absolute','')::numeric,(c.default_tolerance->>'absolute')::numeric,0);pct_tol:=coalesce(nullif(exp->>'tolerance_percent','')::numeric,(c.default_tolerance->>'percent')::numeric,0);allowed_delta:=greatest(abs_tol,abs(exp_qty)*(pct_tol/100.0));if abs(act_qty-exp_qty)>allowed_delta then findings:=findings||jsonb_build_array(jsonb_build_object('code',code_value,'failure','QUANTITY_OUTSIDE_TOLERANCE','expected',exp_qty,'actual',act_qty,'allowed_delta',allowed_delta));end if;end loop;
 if exists(select 1 from jsonb_array_elements(target_actual_quantities) a where not exists(select 1 from jsonb_array_elements(c.expected_quantities) e where e->>'code'=a->>'code')) then findings:=findings||jsonb_build_array(jsonb_build_object('failure','UNEXPECTED_QUANTITY_CODES'));end if;
 h:=encode(extensions.digest(jsonb_build_object('case_id',c.id,'case_hash',c.case_hash,'engine_ref',btrim(target_engine_ref),'engine_version',btrim(target_engine_version),'actual_quantities',target_actual_quantities,'findings',findings)::text,'sha256'),'hex');perform set_config('conceptspaces.qto_benchmark_phase','result_record',true);insert into cost.qto_benchmark_results(case_id,engine_ref,engine_version,actual_quantities,findings,passed,result_hash,status,created_by) values(c.id,btrim(target_engine_ref),btrim(target_engine_version),target_actual_quantities,findings,jsonb_array_length(findings)=0,h,'recorded',auth.uid()) returning * into r;select organisation_id into org_id from core.memberships where user_id=auth.uid() and status='active' limit 1;if org_id is not null then perform audit.append_event(org_id,null,'cost.qto_benchmark_result_recorded','qto_benchmark_result',r.id,null,to_jsonb(r),h,gen_random_uuid());end if;return r.id;
end;$$;
revoke all on function public.record_qto_benchmark_result(uuid,text,text,jsonb) from public,anon;grant execute on function public.record_qto_benchmark_result(uuid,text,text,jsonb) to authenticated;

create or replace function public.review_qto_benchmark_result(target_result_id uuid,target_decision text,target_reason text)
returns text language plpgsql security invoker set search_path='cost','core','audit','auth','pg_temp' as $$
declare r cost.qto_benchmark_results%rowtype; before_state jsonb; decision_value text:=lower(btrim(target_decision)); org_id uuid;
begin select * into r from cost.qto_benchmark_results where id=target_result_id for update;if not found or auth.uid() is null or not core.is_platform_admin() then raise exception 'platform_admin_required';end if;if r.status<>'recorded' or r.created_by=auth.uid() then raise exception 'independent_qto_benchmark_result_review_required';end if;if decision_value not in ('approved','rejected') or nullif(btrim(target_reason),'') is null then raise exception 'benchmark_review_decision_reason_required';end if;if decision_value='approved' and not r.passed then raise exception 'failed_qto_benchmark_cannot_be_approved';end if;before_state:=to_jsonb(r);perform set_config('conceptspaces.qto_benchmark_phase','result_review',true);if decision_value='approved' then update cost.qto_benchmark_results set status='superseded' where case_id=r.case_id and engine_ref=r.engine_ref and engine_version=r.engine_version and status='approved' and id<>r.id;end if;update cost.qto_benchmark_results set status=decision_value,reviewed_by=auth.uid(),reviewed_at=now() where id=r.id returning * into r;select organisation_id into org_id from core.memberships where user_id=auth.uid() and status='active' limit 1;if org_id is not null then perform audit.append_event(org_id,null,'cost.qto_benchmark_result_'||decision_value,'qto_benchmark_result',r.id,before_state,to_jsonb(r),target_reason,gen_random_uuid());end if;return r.status;end;$$;
revoke all on function public.review_qto_benchmark_result(uuid,text,text) from public,anon;grant execute on function public.review_qto_benchmark_result(uuid,text,text) to authenticated;

create or replace function public.start_qto_run(target_project_id uuid,input_payload jsonb)
returns uuid language plpgsql security invoker set search_path='public','cost','cde','project','audit','extensions','auth','pg_temp' as $$
declare m cde.models%rowtype;q cost.qto_runs%rowtype;b cost.qto_benchmark_results%rowtype;c cost.qto_benchmark_cases%rowtype;org_id uuid;model_id_value uuid:=nullif(input_payload->>'model_id','')::uuid;rule_ref text:=btrim(input_payload->>'measurement_rule_set_ref');engine_ref_value text:=btrim(input_payload->>'engine_ref');engine_version_value text:=btrim(input_payload->>'engine_version');input_hash_value text;
begin
 if auth.uid() is null or not project.can_manage_project(target_project_id) then raise exception 'project_manage_authority_required';end if;select * into m from cde.models where id=model_id_value and project_id=target_project_id;if not found then raise exception 'model_not_found';end if;if m.status not in ('approved','issued') then raise exception 'approved_model_required';end if;if nullif(rule_ref,'') is null or nullif(engine_ref_value,'') is null or nullif(engine_version_value,'') is null then raise exception 'measurement_rule_set_and_engine_required';end if;
 select r.*,bc.* into b,c from cost.qto_benchmark_results r join cost.qto_benchmark_cases bc on bc.id=r.case_id where r.status='approved' and r.passed and bc.status='approved' and bc.measurement_rule_set_ref=rule_ref and r.engine_ref=engine_ref_value and r.engine_version=engine_version_value order by r.reviewed_at desc limit 1;if b.id is null then raise exception 'QTO_BENCHMARK_CERTIFICATION_REQUIRED';end if;
 input_hash_value:=encode(extensions.digest(jsonb_build_object('project_id',target_project_id,'model_id',m.id,'model_checksum',m.checksum,'measurement_rule_set_ref',rule_ref,'engine_ref',engine_ref_value,'engine_version',engine_version_value,'benchmark_result_id',b.id,'benchmark_result_hash',b.result_hash,'classification_ref',nullif(btrim(input_payload->>'classification_ref'),''),'exclusions',coalesce(input_payload->'exclusions','[]'::jsonb),'tolerance',coalesce(input_payload->'tolerance','{}'::jsonb))::text,'sha256'),'hex');perform set_config('conceptspaces.cost_phase','qto_create',true);insert into cost.qto_runs(project_id,model_id,model_checksum,measurement_rule_set_ref,classification_ref,exclusions,tolerance,input_hash,status,created_by,engine_ref,engine_version,benchmark_result_id) values(target_project_id,m.id,m.checksum,rule_ref,nullif(btrim(input_payload->>'classification_ref'),''),coalesce(input_payload->'exclusions','[]'::jsonb),coalesce(input_payload->'tolerance','{}'::jsonb),input_hash_value,'queued',auth.uid(),engine_ref_value,engine_version_value,b.id) returning * into q;select organisation_id into org_id from project.projects where id=target_project_id;perform audit.append_event(org_id,target_project_id,'cost.qto.started','qto_run',q.id,null,to_jsonb(q),input_hash_value,gen_random_uuid());return q.id;
end;$$;
revoke all on function public.start_qto_run(uuid,jsonb) from public,anon;grant execute on function public.start_qto_run(uuid,jsonb) to authenticated;

alter table cost.qto_runs drop constraint if exists qto_runs_benchmark_result_id_fkey;
alter table cost.qto_runs add constraint qto_runs_benchmark_result_id_fkey foreign key(benchmark_result_id) references cost.qto_benchmark_results(id) on delete restrict;

create or replace function public.list_qto_benchmark_workspace()
returns jsonb language plpgsql stable security invoker set search_path='cost','core','auth','pg_temp' as $$
begin if auth.uid() is null or not core.is_platform_admin() then raise exception 'platform_admin_required';end if;return jsonb_build_object('cases',coalesce((select jsonb_agg(to_jsonb(c) order by c.created_at desc) from cost.qto_benchmark_cases c),'[]'::jsonb),'results',coalesce((select jsonb_agg(to_jsonb(r) order by r.created_at desc) from cost.qto_benchmark_results r),'[]'::jsonb));end;$$;
revoke all on function public.list_qto_benchmark_workspace() from public,anon;grant execute on function public.list_qto_benchmark_workspace() to authenticated;

commit;
