begin;

alter table project.projects add column if not exists opportunity_id uuid references public.opportunities(id) on delete set null;
alter table project.projects add column if not exists contract_id uuid references public.contracts(id) on delete set null;
alter table project.projects add column if not exists lifecycle_state text not null default 'pre_contract' check(lifecycle_state in ('pre_contract','activation_pending','active','on_hold','handover','operations','closed'));
alter table project.projects add column if not exists data_classification text not null default 'internal' check(data_classification in ('public','internal','confidential','restricted'));

alter table engagement.activations add column if not exists mobilisation_payment_evidence_ref text;
alter table engagement.activations add column if not exists kyc_evidence_ref text;
alter table engagement.activations add column if not exists project_team_ready boolean not null default false;
alter table engagement.activations add column if not exists client_users_ready boolean not null default false;
alter table engagement.activations add column if not exists site_info_ready boolean not null default false;
alter table engagement.activations add column if not exists data_classification_ready boolean not null default false;
alter table engagement.activations add column if not exists activation_hash text;
alter table engagement.activations add column if not exists checked_by uuid references auth.users(id);
alter table engagement.activations add column if not exists checked_at timestamptz;

create table if not exists project.project_stages(
 id uuid primary key default gen_random_uuid(),
 project_id uuid not null references project.projects(id) on delete cascade,
 stage_code text not null,
 title text not null,
 sequence integer not null,
 baseline_version integer not null default 1,
 state text not null default 'not_started' check(state in ('not_started','ready','in_progress','internal_review','client_review','approved','frozen','superseded')),
 contracted_modules jsonb not null default '[]'::jsonb,
 dependencies jsonb not null default '[]'::jsonb,
 deliverables jsonb not null default '[]'::jsonb,
 approval_chain jsonb not null default '[]'::jsonb,
 planned_start date,
 planned_finish date,
 actual_start date,
 actual_finish date,
 source_contract_id uuid not null references public.contracts(id) on delete restrict,
 source_scope_hash text not null,
 created_by uuid references auth.users(id),
 created_at timestamptz not null default now(),
 updated_at timestamptz not null default now(),
 unique(project_id,stage_code,baseline_version)
);
create table if not exists project.stage_events(
 id uuid primary key default gen_random_uuid(),
 project_stage_id uuid not null references project.project_stages(id) on delete cascade,
 project_id uuid not null references project.projects(id) on delete cascade,
 from_state text,
 to_state text not null,
 reason text,
 evidence_refs jsonb not null default '[]'::jsonb,
 actor_id uuid references auth.users(id),
 created_at timestamptz not null default now()
);

alter table project.project_stages enable row level security;
alter table project.stage_events enable row level security;
create policy project_stages_read on project.project_stages for select to authenticated using(project.can_access_project(project_id));
create policy project_stages_insert on project.project_stages for insert to authenticated with check(project.can_manage_project(project_id) and current_setting('conceptspaces.activation_phase',true) in ('stage_init','stage_replan'));
create policy project_stages_update on project.project_stages for update to authenticated using(project.can_manage_project(project_id)) with check(project.can_manage_project(project_id) and current_setting('conceptspaces.activation_phase',true) in ('stage_transition','stage_replan'));
create policy stage_events_read on project.stage_events for select to authenticated using(project.can_access_project(project_id));
create policy stage_events_insert on project.stage_events for insert to authenticated with check(project.can_manage_project(project_id) and current_setting('conceptspaces.activation_phase',true) in ('stage_transition','stage_replan'));
grant select,insert,update on project.project_stages to authenticated;
grant select,insert on project.stage_events to authenticated;

create policy activations_write on engagement.activations for insert to authenticated with check(current_setting('conceptspaces.activation_phase',true)='activation_prepare' and exists(select 1 from public.opportunities o where o.id=opportunity_id and core.has_org_role(o.organisation_id,array['super_admin','org_admin','finance','project_manager','lead_architect'])));
create policy activations_update on engagement.activations for update to authenticated using(exists(select 1 from public.opportunities o where o.id=opportunity_id and core.has_org_role(o.organisation_id,array['super_admin','org_admin','finance','project_manager','lead_architect']))) with check(current_setting('conceptspaces.activation_phase',true) in ('activation_prepare','activation_execute'));
grant insert,update on engagement.activations to authenticated;

create or replace function project.contract_scope_modules(target_contract_id uuid)
returns text[] language sql stable security invoker set search_path=public,pg_temp as $$
 select coalesce(array_agg(upper(x->>'module_code') order by upper(x->>'module_code')) filter(where x->>'state'='included'),array[]::text[])
 from public.contracts c cross join lateral jsonb_array_elements(coalesce(c.contract_snapshot#>'{scope_snapshot,selections}','[]'::jsonb)) x
 where c.id=target_contract_id;
$$;
revoke all on function project.contract_scope_modules(uuid) from public,anon; grant execute on function project.contract_scope_modules(uuid) to authenticated;

create or replace function public.initialise_project_stage_plan(target_project_id uuid,target_contract_id uuid,input_payload jsonb default '{}'::jsonb)
returns integer language plpgsql security invoker set search_path=public,project,core,audit,auth,pg_temp as $$
declare p project.projects%rowtype; c public.contracts%rowtype; modules text[]; count_value int:=0; stage_record record; deps jsonb; baseline_value int; dates jsonb:=coalesce(input_payload->'stage_dates','{}'::jsonb); begin
 select * into p from project.projects where id=target_project_id for update; select * into c from public.contracts where id=target_contract_id;
 if not found or c.project_id is distinct from p.id or c.status<>'active' or c.execution_hash is null or auth.uid() is null or not project.can_manage_project(p.id) then raise exception 'executed_project_contract_required'; end if;
 modules:=project.contract_scope_modules(c.id); if cardinality(modules)=0 then raise exception 'contracted_scope_required'; end if;
 select coalesce(max(baseline_version),0)+1 into baseline_value from project.project_stages where project_id=p.id;
 perform set_config('conceptspaces.activation_phase','stage_init',true);
 for stage_record in select * from (values
   ('S02','Site / Project Truth',2,array[]::text[],true),
   ('S03','Feasibility / Concept',3,array['FEAS','ARCH']::text[],false),
   ('S04','Design Development',4,array['ARCH','INT']::text[],false),
   ('S05','Engineering / BIM Coordination',5,array['STR','MEPF','BIM']::text[],false),
   ('S06','Tender / Cost',6,array['BOQ','PROC']::text[],false),
   ('S07','IFC / Construction Release',7,array['ARCH','STR','MEPF','BIM']::text[],false),
   ('S08','Construction / PMC',8,array['PMC']::text[],false),
   ('S09','Handover',9,array['PMC','TWIN']::text[],false),
   ('S10','Operations / Learning',10,array['TWIN']::text[],false)
 ) as x(stage_code,title,seq,module_gate,always_on)
 loop
   if stage_record.always_on or modules && stage_record.module_gate then
     deps:=case stage_record.stage_code when 'S02' then '[]'::jsonb when 'S03' then '["S02"]'::jsonb when 'S04' then '["S03"]'::jsonb when 'S05' then '["S04"]'::jsonb when 'S06' then '["S05"]'::jsonb when 'S07' then '["S05","S06"]'::jsonb when 'S08' then '["S07"]'::jsonb when 'S09' then '["S08"]'::jsonb else '["S09"]'::jsonb end;
     insert into project.project_stages(project_id,stage_code,title,sequence,baseline_version,state,contracted_modules,dependencies,deliverables,approval_chain,planned_start,planned_finish,source_contract_id,source_scope_hash,created_by)
     values(p.id,stage_record.stage_code,stage_record.title,stage_record.seq,baseline_value,case when stage_record.stage_code='S02' then 'ready' else 'not_started' end,to_jsonb(modules),deps,coalesce(input_payload#>('{'||stage_record.stage_code||',deliverables}'),'[]'::jsonb),coalesce(input_payload#>('{'||stage_record.stage_code||',approval_chain}'),'[]'::jsonb),nullif(dates#>>array[stage_record.stage_code,'planned_start'],'')::date,nullif(dates#>>array[stage_record.stage_code,'planned_finish'],'')::date,c.id,c.contract_snapshot->>'scope_hash',auth.uid());
     count_value:=count_value+1;
   end if;
 end loop;
 perform audit.append_event(p.organisation_id,p.id,'project.stage_plan.initialised','project',p.id,null,jsonb_build_object('contract_id',c.id,'baseline_version',baseline_value,'stage_count',count_value,'modules',modules),c.execution_hash,gen_random_uuid()); return count_value;
end;$$;
revoke all on function public.initialise_project_stage_plan(uuid,uuid,jsonb) from public,anon; grant execute on function public.initialise_project_stage_plan(uuid,uuid,jsonb) to authenticated;

create or replace function public.prepare_project_activation(target_contract_id uuid,target_project_id uuid,input_payload jsonb default '{}'::jsonb)
returns uuid language plpgsql security invoker set search_path=public,engagement,project,core,audit,extensions,auth,pg_temp as $$
declare c public.contracts%rowtype; p project.projects%rowtype; proposal public.proposals%rowtype; a engagement.activations%rowtype; modules text[]; design_scope boolean; payment_ok boolean:=coalesce((input_payload->>'initial_payment_satisfied')::boolean,false); kyc_ok boolean:=coalesce((input_payload->>'required_kyc_satisfied')::boolean,false); client_ok boolean; team_ok boolean; site_ok boolean; data_ok boolean; hash_value text; begin
 select * into c from public.contracts where id=target_contract_id; select * into p from project.projects where id=target_project_id for update; if c.id is null or p.id is null or c.organisation_id<>p.organisation_id or c.status<>'active' or c.execution_hash is null or auth.uid() is null or not project.can_manage_project(p.id) then raise exception 'executed_contract_project_authority_required'; end if;
 select * into proposal from public.proposals where id=c.proposal_id; if proposal.status<>'accepted' or proposal.accepted_scope_hash is distinct from proposal.scope_hash then raise exception 'accepted_proposal_required'; end if;
 modules:=project.contract_scope_modules(c.id); design_scope:=modules && array['ARCH','INT','STR','MEPF','BIM']::text[];
 team_ok:=exists(select 1 from project.project_members pm where pm.project_id=p.id and pm.status='active') and (not design_scope or p.lead_architect_user_id is not null);
 client_ok:=exists(select 1 from project.project_members pm where pm.project_id=p.id and pm.status='active' and lower(pm.role_code) in ('client','client_user','client_reviewer','client_approver','client_admin'));
 site_ok:=exists(select 1 from project.truth_records t where t.project_id=p.id and t.record_key in ('site.address','site.coordinates','site.plot_area') and t.status in ('draft','verified','approved')) or exists(select 1 from engagement.intake_sessions s where s.project_id=p.id and s.site_payload<>'{}'::jsonb);
 data_ok:=p.data_classification in ('internal','confidential','restricted','public');
 if payment_ok and nullif(btrim(input_payload->>'mobilisation_payment_evidence_ref'),'') is null then raise exception 'activation_payment_evidence_required'; end if; if kyc_ok and nullif(btrim(input_payload->>'kyc_evidence_ref'),'') is null then raise exception 'activation_kyc_evidence_required'; end if;
 hash_value:=encode(extensions.digest(jsonb_build_object('project_id',p.id,'contract_id',c.id,'execution_hash',c.execution_hash,'proposal_id',proposal.id,'scope_hash',proposal.scope_hash,'payment',payment_ok,'payment_evidence',input_payload->>'mobilisation_payment_evidence_ref','kyc',kyc_ok,'kyc_evidence',input_payload->>'kyc_evidence_ref','team',team_ok,'client_users',client_ok,'site_info',site_ok,'data_classification',p.data_classification)::text,'sha256'),'hex');
 perform set_config('conceptspaces.activation_phase','activation_prepare',true);
 insert into engagement.activations(opportunity_id,proposal_id,contract_id,project_id,proposal_accepted,contract_executed,initial_payment_satisfied,required_kyc_satisfied,state,blocked_reason,mobilisation_payment_evidence_ref,kyc_evidence_ref,project_team_ready,client_users_ready,site_info_ready,data_classification_ready,activation_hash,checked_by,checked_at)
 values(proposal.opportunity_id,proposal.id,c.id,p.id,true,true,payment_ok,kyc_ok,'pending',null,nullif(btrim(input_payload->>'mobilisation_payment_evidence_ref'),''),nullif(btrim(input_payload->>'kyc_evidence_ref'),''),team_ok,client_ok,site_ok,data_ok,hash_value,auth.uid(),now())
 on conflict(opportunity_id) do update set proposal_id=excluded.proposal_id,contract_id=excluded.contract_id,project_id=excluded.project_id,proposal_accepted=excluded.proposal_accepted,contract_executed=excluded.contract_executed,initial_payment_satisfied=excluded.initial_payment_satisfied,required_kyc_satisfied=excluded.required_kyc_satisfied,mobilisation_payment_evidence_ref=excluded.mobilisation_payment_evidence_ref,kyc_evidence_ref=excluded.kyc_evidence_ref,project_team_ready=excluded.project_team_ready,client_users_ready=excluded.client_users_ready,site_info_ready=excluded.site_info_ready,data_classification_ready=excluded.data_classification_ready,activation_hash=excluded.activation_hash,checked_by=excluded.checked_by,checked_at=excluded.checked_at,updated_at=now(),state='pending'
 returning * into a;
 update project.projects set opportunity_id=proposal.opportunity_id,contract_id=c.id,lifecycle_state='activation_pending',updated_at=now() where id=p.id;
 perform audit.append_event(p.organisation_id,p.id,'project.activation.prepared','activation',a.id,null,to_jsonb(a),hash_value,gen_random_uuid()); return a.id;
end;$$;
revoke all on function public.prepare_project_activation(uuid,uuid,jsonb) from public,anon; grant execute on function public.prepare_project_activation(uuid,uuid,jsonb) to authenticated;

create or replace function public.activate_project(target_activation_id uuid,target_reason text)
returns text language plpgsql security invoker set search_path=public,engagement,project,core,audit,auth,pg_temp as $$
declare a engagement.activations%rowtype; p project.projects%rowtype; c public.contracts%rowtype; before_state jsonb; missing text[]:=array[]::text[]; begin
 select * into a from engagement.activations where id=target_activation_id for update; if not found then raise exception 'activation_not_found'; end if; select * into p from project.projects where id=a.project_id for update; select * into c from public.contracts where id=a.contract_id; if auth.uid() is null or not project.can_manage_project(p.id) then raise exception 'project_activation_authority_required'; end if; if nullif(btrim(target_reason),'') is null then raise exception 'activation_reason_required'; end if;
 if not a.proposal_accepted then missing:=array_append(missing,'proposal_accepted'); end if; if not a.contract_executed or c.status<>'active' or c.execution_hash is null then missing:=array_append(missing,'contract_executed'); end if; if not a.initial_payment_satisfied then missing:=array_append(missing,'initial_payment'); end if; if not a.required_kyc_satisfied then missing:=array_append(missing,'required_kyc'); end if; if not a.project_team_ready then missing:=array_append(missing,'project_team'); end if; if not a.client_users_ready then missing:=array_append(missing,'client_users'); end if; if not a.site_info_ready then missing:=array_append(missing,'site_info'); end if; if not a.data_classification_ready then missing:=array_append(missing,'data_classification'); end if;
 if cardinality(missing)>0 then perform set_config('conceptspaces.activation_phase','activation_execute',true); update engagement.activations set state='blocked',blocked_reason='ACTIVATION_PREREQUISITE_MISSING:'||array_to_string(missing,','),updated_at=now() where id=a.id; raise exception 'ACTIVATION_PREREQUISITE_MISSING:%',array_to_string(missing,','); end if;
 before_state:=to_jsonb(a); perform set_config('conceptspaces.activation_phase','activation_execute',true); update engagement.activations set state='activated',blocked_reason=null,activated_by=auth.uid(),activated_at=now(),updated_at=now() where id=a.id returning * into a; update project.projects set lifecycle_state='active',status='active',updated_at=now() where id=p.id;
 if not exists(select 1 from project.project_stages s where s.project_id=p.id and s.source_contract_id=c.id and s.state<>'superseded') then perform public.initialise_project_stage_plan(p.id,c.id,'{}'::jsonb); end if;
 perform audit.append_event(p.organisation_id,p.id,'project.activated','activation',a.id,before_state,to_jsonb(a),target_reason,gen_random_uuid()); return 'active';
end;$$;
revoke all on function public.activate_project(uuid,text) from public,anon; grant execute on function public.activate_project(uuid,text) to authenticated;

create or replace function public.transition_project_stage(target_project_stage_id uuid,target_state text,input_payload jsonb default '{}'::jsonb)
returns text language plpgsql security invoker set search_path=public,project,audit,auth,pg_temp as $$
declare s project.project_stages%rowtype; p project.projects%rowtype; state_value text:=lower(btrim(target_state)); dep text; before_state jsonb; begin
 select * into s from project.project_stages where id=target_project_stage_id for update; if not found then raise exception 'project_stage_not_found'; end if; select * into p from project.projects where id=s.project_id; if auth.uid() is null or not project.can_manage_project(p.id) then raise exception 'stage_transition_authority_required'; end if; if p.lifecycle_state<>'active' then raise exception 'project_not_active'; end if; if state_value not in ('ready','in_progress','internal_review','client_review','approved','frozen') then raise exception 'stage_state_invalid'; end if; if s.state='superseded' or s.state='frozen' then raise exception 'terminal_stage_state'; end if;
 if state_value='ready' then for dep in select jsonb_array_elements_text(s.dependencies) loop if not exists(select 1 from project.project_stages d where d.project_id=s.project_id and d.stage_code=dep and d.baseline_version=s.baseline_version and d.state='frozen') then raise exception 'STAGE_DEPENDENCY_BLOCKED:%',dep; end if; end loop; end if;
 if state_value='in_progress' and s.state not in ('ready','not_started') then raise exception 'invalid_stage_transition'; end if; if state_value='internal_review' and s.state<>'in_progress' then raise exception 'invalid_stage_transition'; end if; if state_value='client_review' and s.state<>'internal_review' then raise exception 'invalid_stage_transition'; end if; if state_value='approved' and s.state not in ('internal_review','client_review') then raise exception 'invalid_stage_transition'; end if; if state_value='frozen' and s.state<>'approved' then raise exception 'invalid_stage_transition'; end if;
 if state_value in ('internal_review','client_review','approved','frozen') and (jsonb_typeof(coalesce(input_payload->'evidence_refs','[]'::jsonb))<>'array' or jsonb_array_length(coalesce(input_payload->'evidence_refs','[]'::jsonb))=0) then raise exception 'stage_transition_evidence_required'; end if;
 before_state:=to_jsonb(s); perform set_config('conceptspaces.activation_phase','stage_transition',true); update project.project_stages set state=state_value,actual_start=case when state_value='in_progress' and actual_start is null then current_date else actual_start end,actual_finish=case when state_value='frozen' then current_date else actual_finish end,updated_at=now() where id=s.id returning * into s; insert into project.stage_events(project_stage_id,project_id,from_state,to_state,reason,evidence_refs,actor_id) values(s.id,s.project_id,before_state->>'state',state_value,nullif(btrim(input_payload->>'reason'),''),coalesce(input_payload->'evidence_refs','[]'::jsonb),auth.uid()); perform audit.append_event(p.organisation_id,p.id,'project.stage.'||state_value,'project_stage',s.id,before_state,to_jsonb(s),input_payload->>'reason',gen_random_uuid()); return s.state;
end;$$;
revoke all on function public.transition_project_stage(uuid,text,jsonb) from public,anon; grant execute on function public.transition_project_stage(uuid,text,jsonb) to authenticated;

create or replace function public.replan_future_project_stages(target_project_id uuid,target_contract_id uuid,input_payload jsonb)
returns integer language plpgsql security invoker set search_path=public,project,audit,auth,pg_temp as $$
declare p project.projects%rowtype; current_baseline int; new_baseline int; old_stage project.project_stages%rowtype; count_value int:=0; dates jsonb:=coalesce(input_payload->'stage_dates','{}'::jsonb); begin
 select * into p from project.projects where id=target_project_id for update; if not found or auth.uid() is null or not project.can_manage_project(p.id) then raise exception 'stage_replan_authority_required'; end if; if nullif(btrim(input_payload->>'reason'),'') is null then raise exception 'stage_replan_reason_required'; end if; if not exists(select 1 from public.contracts c where c.id=target_contract_id and c.project_id=p.id and c.status='active' and c.execution_hash is not null) then raise exception 'active_change_order_contract_required'; end if;
 select max(baseline_version) into current_baseline from project.project_stages where project_id=p.id; if current_baseline is null then return public.initialise_project_stage_plan(p.id,target_contract_id,input_payload); end if; new_baseline:=current_baseline+1; perform set_config('conceptspaces.activation_phase','stage_replan',true);
 for old_stage in select * from project.project_stages where project_id=p.id and baseline_version=current_baseline order by sequence loop
   if old_stage.state in ('frozen','approved','client_review','internal_review','in_progress') then continue; end if;
   update project.project_stages set state='superseded',updated_at=now() where id=old_stage.id;
   insert into project.project_stages(project_id,stage_code,title,sequence,baseline_version,state,contracted_modules,dependencies,deliverables,approval_chain,planned_start,planned_finish,source_contract_id,source_scope_hash,created_by)
   values(p.id,old_stage.stage_code,old_stage.title,old_stage.sequence,new_baseline,'not_started',to_jsonb(project.contract_scope_modules(target_contract_id)),old_stage.dependencies,coalesce(input_payload#>('{'||old_stage.stage_code||',deliverables}'),old_stage.deliverables),coalesce(input_payload#>('{'||old_stage.stage_code||',approval_chain}'),old_stage.approval_chain),coalesce(nullif(dates#>>array[old_stage.stage_code,'planned_start'],'')::date,old_stage.planned_start),coalesce(nullif(dates#>>array[old_stage.stage_code,'planned_finish'],'')::date,old_stage.planned_finish),target_contract_id,(select contract_snapshot->>'scope_hash' from public.contracts where id=target_contract_id),auth.uid()); count_value:=count_value+1;
 end loop;
 perform audit.append_event(p.organisation_id,p.id,'project.stage_plan.replanned','project',p.id,jsonb_build_object('baseline_version',current_baseline),jsonb_build_object('baseline_version',new_baseline,'future_stage_count',count_value),input_payload->>'reason',gen_random_uuid()); return count_value;
end;$$;
revoke all on function public.replan_future_project_stages(uuid,uuid,jsonb) from public,anon; grant execute on function public.replan_future_project_stages(uuid,uuid,jsonb) to authenticated;

create or replace function public.list_project_activation_workspace(target_organisation_id uuid)
returns jsonb language plpgsql stable security invoker set search_path=public,project,engagement,core,auth,pg_temp as $$
begin if auth.uid() is null or not core.is_internal_org_member(target_organisation_id) then raise exception 'organisation_access_required'; end if; return jsonb_build_object('projects',coalesce((select jsonb_agg(to_jsonb(p) order by p.created_at desc) from project.projects p where p.organisation_id=target_organisation_id),'[]'::jsonb),'activations',coalesce((select jsonb_agg(to_jsonb(a) order by a.created_at desc) from engagement.activations a join public.opportunities o on o.id=a.opportunity_id where o.organisation_id=target_organisation_id),'[]'::jsonb),'stages',coalesce((select jsonb_agg(to_jsonb(s) order by s.project_id,s.baseline_version desc,s.sequence) from project.project_stages s join project.projects p on p.id=s.project_id where p.organisation_id=target_organisation_id),'[]'::jsonb),'stage_events',coalesce((select jsonb_agg(to_jsonb(e) order by e.created_at desc) from project.stage_events e join project.projects p on p.id=e.project_id where p.organisation_id=target_organisation_id),'[]'::jsonb),'contracts',coalesce((select jsonb_agg(to_jsonb(c) order by c.created_at desc) from public.contracts c where c.organisation_id=target_organisation_id and c.status in ('active','suspended')),'[]'::jsonb)); end;$$;
revoke all on function public.list_project_activation_workspace(uuid) from public,anon; grant execute on function public.list_project_activation_workspace(uuid) to authenticated;

commit;
