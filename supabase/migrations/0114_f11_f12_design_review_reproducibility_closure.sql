begin;

alter table aec.design_intents add column if not exists seed text not null default 'benchmark-v1';
alter table aec.design_intents add column if not exists metric_set_version text not null default 'feasibility-envelope-metrics@1.0.0';
alter table aec.design_intents add column if not exists status text not null default 'draft' check(status in ('draft','approved','superseded'));
alter table aec.design_intents add column if not exists content_hash text;
alter table aec.design_intents add column if not exists approved_by uuid references auth.users(id) on delete set null;
alter table aec.design_intents add column if not exists approved_at timestamptz;
alter table aec.design_intents enable row level security;
grant insert,update on aec.design_intents to authenticated;
drop policy if exists design_intent_governed_insert on aec.design_intents;
create policy design_intent_governed_insert on aec.design_intents for insert to authenticated with check(project.can_access_project(project_id) and created_by=auth.uid() and status='draft' and current_setting('conceptspaces.design_intent_phase',true)='draft');
drop policy if exists design_intent_governed_update on aec.design_intents;
create policy design_intent_governed_update on aec.design_intents for update to authenticated using(project.can_manage_project(project_id)) with check(project.can_manage_project(project_id) and current_setting('conceptspaces.design_intent_phase',true) in ('approve','supersede'));

create or replace function public.create_design_intent(target_project_id uuid,input_payload jsonb)
returns uuid language plpgsql security invoker set search_path='aec','project','audit','extensions','auth','pg_temp' as $$
declare p project.projects%rowtype;d aec.design_intents%rowtype;v int;h text;mode text:=lower(coalesce(nullif(btrim(input_payload->>'optimisation_mode'),''),'balanced'));seed_value text:=coalesce(nullif(btrim(input_payload->>'seed'),''),'benchmark-v1');metric_version text:=coalesce(nullif(btrim(input_payload->>'metric_set_version'),''),'feasibility-envelope-metrics@1.0.0');
begin
 select * into p from project.projects where id=target_project_id;if not found or auth.uid() is null or not project.can_access_project(p.id) then raise exception 'project_access_required';end if;
 if mode not in ('commercial_yield','environmental','architecture','capex','balanced') then raise exception 'design_optimisation_mode_invalid';end if;
 if jsonb_typeof(coalesce(input_payload->'mandatory_requirements','[]'::jsonb))<>'array' or jsonb_typeof(coalesce(input_payload->'preferences','{}'::jsonb)) not in ('object','array') or jsonb_typeof(coalesce(input_payload->'exclusions','[]'::jsonb))<>'array' then raise exception 'design_intent_payload_invalid';end if;
 select coalesce(max(version),0)+1 into v from aec.design_intents where project_id=p.id;
 h:=encode(extensions.digest(jsonb_build_object('project_id',p.id,'version',v,'typology',coalesce(nullif(btrim(input_payload->>'typology'),''),p.typology),'optimisation_mode',mode,'programme',coalesce(input_payload->'programme','{}'::jsonb),'mandatory_requirements',coalesce(input_payload->'mandatory_requirements','[]'::jsonb),'preferences',coalesce(input_payload->'preferences','{}'::jsonb),'exclusions',coalesce(input_payload->'exclusions','[]'::jsonb),'seed',seed_value,'metric_set_version',metric_version)::text,'sha256'),'hex');
 perform set_config('conceptspaces.design_intent_phase','draft',true);
 insert into aec.design_intents(project_id,version,typology,optimisation_mode,programme,mandatory_requirements,preferences,exclusions,created_by,seed,metric_set_version,status,content_hash)
 values(p.id,v,coalesce(nullif(btrim(input_payload->>'typology'),''),p.typology),mode,coalesce(input_payload->'programme','{}'::jsonb),coalesce(input_payload->'mandatory_requirements','[]'::jsonb),coalesce(input_payload->'preferences','{}'::jsonb),coalesce(input_payload->'exclusions','[]'::jsonb),auth.uid(),seed_value,metric_version,'draft',h) returning * into d;
 perform audit.append_event(p.organisation_id,p.id,'design.intent.drafted','design_intent',d.id,null,to_jsonb(d),h,gen_random_uuid());return d.id;
end;$$;
revoke all on function public.create_design_intent(uuid,jsonb) from public,anon;grant execute on function public.create_design_intent(uuid,jsonb) to authenticated;

create or replace function public.approve_design_intent(target_intent_id uuid,target_reason text)
returns text language plpgsql security invoker set search_path='aec','project','audit','auth','pg_temp' as $$
declare d aec.design_intents%rowtype;p project.projects%rowtype;before_state jsonb;
begin
 select * into d from aec.design_intents where id=target_intent_id for update;if not found or d.status<>'draft' then raise exception 'draft_design_intent_required';end if;select * into p from project.projects where id=d.project_id;
 if auth.uid() is null or not project.can_manage_project(p.id) then raise exception 'project_manage_authority_required';end if;if nullif(btrim(target_reason),'') is null then raise exception 'design_intent_approval_reason_required';end if;
 before_state:=to_jsonb(d);perform set_config('conceptspaces.design_intent_phase','supersede',true);update aec.design_intents set status='superseded' where project_id=p.id and status='approved';perform set_config('conceptspaces.design_intent_phase','approve',true);update aec.design_intents set status='approved',approved_by=auth.uid(),approved_at=now() where id=d.id returning * into d;
 perform project.invalidate_compiler_runs(p.id,'Approved design objective changed',d.content_hash);perform audit.append_event(p.organisation_id,p.id,'design.intent.approved','design_intent',d.id,before_state,to_jsonb(d),target_reason,gen_random_uuid());return d.status;
end;$$;
revoke all on function public.approve_design_intent(uuid,text) from public,anon;grant execute on function public.approve_design_intent(uuid,text) to authenticated;

create or replace function public.get_approved_design_intent(target_project_id uuid)
returns jsonb language sql stable security invoker set search_path='aec','project','auth','pg_temp' as $$
 select to_jsonb(d) from aec.design_intents d where d.project_id=target_project_id and d.status='approved' and project.can_access_project(target_project_id) order by d.version desc limit 1;
$$;
revoke all on function public.get_approved_design_intent(uuid) from public,anon;grant execute on function public.get_approved_design_intent(uuid) to authenticated;

-- Compiler experiments always use an isolated scenario branch. Main is never advanced by a compiler run.
create or replace function public.persist_compiler_run(target_project_id uuid,target_actor_id uuid,target_objective text,target_input_hash text,target_output_hash text,target_snapshot jsonb,target_stages jsonb,target_candidates jsonb,target_status text,target_blocked_reasons jsonb)
returns uuid language plpgsql security definer set search_path='public','project','core','configuration','audit','auth','pg_temp' as $$
declare p project.projects%rowtype;main_branch public.project_branches%rowtype;scenario public.project_branches%rowtype;snapshot_id uuid;run_id uuid;item jsonb;candidate jsonb;stage_name text;stage_input_hash text;stage_output_hash text;final_status text:=lower(target_status);criticality_value text;config_hash text;scenario_name text;
begin
 if current_user<>'service_role' then raise exception 'service_role_required';end if;
 if target_input_hash !~ '^[0-9a-f]{64}$' or target_output_hash !~ '^[0-9a-f]{64}$' then raise exception 'invalid_compiler_hash';end if;if final_status not in ('blocked','awaiting_review','completed','failed') then raise exception 'invalid_compiler_status';end if;
 select * into p from project.projects where id=target_project_id;if not found then raise exception 'project_not_found';end if;
 if not exists(select 1 from core.memberships m where m.organisation_id=p.organisation_id and m.user_id=target_actor_id and m.status='active') and not exists(select 1 from project.project_members pm where pm.project_id=p.id and pm.user_id=target_actor_id and pm.status='active') then raise exception 'actor_project_authority_required';end if;
 if jsonb_typeof(target_snapshot)<>'object' or jsonb_typeof(target_stages)<>'array' or jsonb_typeof(target_candidates)<>'array' then raise exception 'invalid_compiler_payload';end if;
 select * into main_branch from public.project_branches where project_id=p.id and name='main' limit 1;
 if not found then
   config_hash:=configuration.project_configuration_hash(p.id);
   insert into public.project_branches(project_id,name,parent_branch_id,parent_commit_hash,head_commit_hash,purpose,status,created_by) values(p.id,'main',null,null,config_hash,'Approved project configuration','active',target_actor_id) on conflict(project_id,name) do nothing;
   select * into main_branch from public.project_branches where project_id=p.id and name='main';
   insert into public.project_commits(project_id,branch_id,parent_commit_hashes,content_hash,message,changed_object_refs,author_type,author_ref) values(p.id,main_branch.id,'[]'::jsonb,config_hash,'Genesis project configuration','[]'::jsonb,'human',target_actor_id::text) on conflict(project_id,content_hash) do nothing;
 end if;
 scenario_name:='compiler-'||substr(target_input_hash,1,12);
 select * into scenario from public.project_branches where project_id=p.id and name=scenario_name;
 if not found then
   insert into public.project_branches(project_id,name,parent_branch_id,parent_commit_hash,head_commit_hash,purpose,status,created_by) values(p.id,scenario_name,main_branch.id,main_branch.head_commit_hash,main_branch.head_commit_hash,'Isolated Building Compiler experiment for input '||substr(target_input_hash,1,16),'active',target_actor_id) returning * into scenario;
 elsif scenario.status<>'active' then raise exception 'compiler_scenario_branch_not_active';end if;
 insert into public.compiler_input_snapshots(project_id,branch_id,project_truth_hash,regulation_hash,programme_hash,requirement_hash,design_state_hash,cost_state_hash,climate_state_hash,source_refs)
 values(p.id,scenario.id,coalesce(target_snapshot#>>'{hashes,project_truth}',target_input_hash),coalesce(target_snapshot#>>'{hashes,regulation}',target_input_hash),coalesce(target_snapshot#>>'{hashes,programme}',target_input_hash),coalesce(target_snapshot#>>'{hashes,requirements}',target_input_hash),target_snapshot#>>'{hashes,design}',target_snapshot#>>'{hashes,cost}',target_snapshot#>>'{hashes,climate}',coalesce(target_snapshot->'source_refs','[]'::jsonb)) returning id into snapshot_id;
 insert into public.compilation_runs(project_id,branch_id,input_snapshot_id,objective,status,requested_by,final_artifact_refs,input_hash,output_hash,execution_manifest,blocked_reasons,completed_at)
 values(p.id,scenario.id,snapshot_id,left(coalesce(target_objective,'balanced'),120),final_status,target_actor_id,'[]'::jsonb,target_input_hash,target_output_hash,coalesce(target_snapshot,'{}'::jsonb),coalesce(target_blocked_reasons,'[]'::jsonb),now())
 on conflict(project_id,input_hash) where input_hash is not null do update set branch_id=excluded.branch_id,input_snapshot_id=excluded.input_snapshot_id,output_hash=excluded.output_hash,status=excluded.status,execution_manifest=excluded.execution_manifest,blocked_reasons=excluded.blocked_reasons,completed_at=excluded.completed_at returning id into run_id;
 delete from public.compiler_stage_runs where compilation_run_id=run_id;delete from public.pareto_candidates where compilation_run_id=run_id;
 for item in select value from jsonb_array_elements(target_stages) loop
   stage_name:=item->>'stage';stage_input_hash:=coalesce(item->>'input_hash',target_input_hash);stage_output_hash:=nullif(item->>'output_hash','');criticality_value:=coalesce(item->>'criticality',p.criticality);
   if stage_name not in ('project_truth','regulatory_context','programme','feasibility','option_generation','architecture','structure','mepf','interiors','quantity_cost','coordination','assurance') then raise exception 'invalid_compiler_stage';end if;
   insert into public.compiler_stage_runs(compilation_run_id,stage,status,criticality,engine_refs,agent_run_refs,input_hash,output_hash,evidence_refs,assumptions,validation_finding_refs,started_at,completed_at)
   values(run_id,stage_name,coalesce(item->>'status','blocked'),criticality_value,coalesce(item->'engine_refs','[]'::jsonb),coalesce(item->'agent_run_refs','[]'::jsonb),stage_input_hash,stage_output_hash,coalesce(item->'evidence_refs','[]'::jsonb),coalesce(item->'assumptions','[]'::jsonb),coalesce(item->'validation_finding_refs','[]'::jsonb),now(),now());
 end loop;
 for candidate in select value from jsonb_array_elements(target_candidates) loop
   insert into public.pareto_candidates(compilation_run_id,option_id,objective_metrics,dominated,constraint_violations,compliance_state,human_shortlisted)
   values(run_id,(candidate->>'option_id')::uuid,coalesce(candidate->'objective_metrics','{}'::jsonb),coalesce((candidate->>'dominated')::boolean,false),coalesce(candidate->'constraint_violations','[]'::jsonb),coalesce(candidate->>'compliance_state','not_verified'),false);
 end loop;
 insert into public.project_commits(project_id,branch_id,parent_commit_hashes,content_hash,message,changed_object_refs,author_type,author_ref)
 values(p.id,scenario.id,jsonb_build_array(scenario.head_commit_hash),target_output_hash,'Building Compiler isolated run '||run_id::text,jsonb_build_array('compilation_run:'||run_id::text),'hybrid',target_actor_id::text) on conflict(project_id,content_hash) do nothing;
 update public.project_branches set head_commit_hash=target_output_hash where id=scenario.id;
 perform audit.append_event(p.organisation_id,p.id,'compiler.run.persisted','compilation_run',run_id,null,jsonb_build_object('branch_id',scenario.id,'input_hash',target_input_hash,'output_hash',target_output_hash,'status',final_status),target_output_hash,gen_random_uuid());
 return run_id;
end;$$;
revoke all on function public.persist_compiler_run(uuid,uuid,text,text,text,jsonb,jsonb,jsonb,text,jsonb) from public,anon,authenticated;
grant execute on function public.persist_compiler_run(uuid,uuid,text,text,text,jsonb,jsonb,jsonb,text,jsonb) to service_role;

create table if not exists aec.change_instructions(
 id uuid primary key default gen_random_uuid(),project_id uuid not null references project.projects(id) on delete cascade,branch_id uuid not null references public.project_branches(id) on delete cascade,source_type text not null check(source_type in ('voice','text')),raw_input text not null,transcript text,structured_changes jsonb not null,status text not null check(status in ('draft','approved','executed','cancelled')) default 'draft',input_hash text not null,interpretation_hash text not null,execution_hash text,created_by uuid references auth.users(id) on delete set null,approved_by uuid references auth.users(id) on delete set null,approved_at timestamptz,executed_by uuid references auth.users(id) on delete set null,executed_at timestamptz,created_at timestamptz not null default now()
);
create table if not exists aec.object_revisions(
 id uuid primary key default gen_random_uuid(),project_id uuid not null references project.projects(id) on delete cascade,branch_id uuid not null references public.project_branches(id) on delete cascade,object_key text not null,revision int not null,state text not null check(state in ('active','removed','published')) default 'active',geometry_hash text,properties jsonb not null default '{}'::jsonb,source_instruction_id uuid references aec.change_instructions(id) on delete restrict,parent_revision_id uuid references aec.object_revisions(id) on delete restrict,content_hash text not null,created_by uuid references auth.users(id) on delete set null,created_at timestamptz not null default now(),unique(project_id,branch_id,object_key,revision)
);
alter table aec.change_instructions enable row level security;alter table aec.object_revisions enable row level security;
grant select,insert,update on aec.change_instructions to authenticated;grant select,insert on aec.object_revisions to authenticated;
create policy change_instruction_read on aec.change_instructions for select to authenticated using(project.can_access_project(project_id));
create policy change_instruction_insert on aec.change_instructions for insert to authenticated with check(project.can_access_project(project_id) and created_by=auth.uid() and status='draft' and current_setting('conceptspaces.design_change_phase',true)='interpret');
create policy change_instruction_update on aec.change_instructions for update to authenticated using(project.can_manage_project(project_id)) with check(project.can_manage_project(project_id) and current_setting('conceptspaces.design_change_phase',true) in ('approve','execute','cancel'));
create policy object_revision_read on aec.object_revisions for select to authenticated using(project.can_access_project(project_id));
create policy object_revision_insert on aec.object_revisions for insert to authenticated with check(project.can_manage_project(project_id) and current_setting('conceptspaces.design_change_phase',true)='execute');

create or replace function public.interpret_design_change(target_project_id uuid,target_branch_id uuid,input_payload jsonb)
returns uuid language plpgsql security invoker set search_path='aec','public','project','audit','extensions','auth','pg_temp' as $$
declare p project.projects%rowtype;b public.project_branches%rowtype;i aec.change_instructions%rowtype;raw text:=coalesce(nullif(btrim(input_payload->>'raw_input'),''),nullif(btrim(input_payload->>'transcript'),''));changes jsonb:=coalesce(input_payload->'structured_changes','[]'::jsonb);input_h text;interp_h text;source_value text:=lower(coalesce(input_payload->>'source_type','text'));
begin
 select * into p from project.projects where id=target_project_id;if not found or auth.uid() is null or not project.can_access_project(p.id) then raise exception 'project_access_required';end if;select * into b from public.project_branches where id=target_branch_id and project_id=p.id and status='active';if not found then raise exception 'active_design_branch_required';end if;
 if source_value not in ('voice','text') or raw is null or jsonb_typeof(changes)<>'array' or jsonb_array_length(changes)=0 then raise exception 'structured_design_interpretation_required';end if;
 input_h:=encode(extensions.digest(jsonb_build_object('project_id',p.id,'branch_id',b.id,'source_type',source_value,'raw_input',raw,'transcript',input_payload->>'transcript')::text,'sha256'),'hex');interp_h:=encode(extensions.digest(jsonb_build_object('input_hash',input_h,'structured_changes',changes)::text,'sha256'),'hex');
 perform set_config('conceptspaces.design_change_phase','interpret',true);insert into aec.change_instructions(project_id,branch_id,source_type,raw_input,transcript,structured_changes,status,input_hash,interpretation_hash,created_by) values(p.id,b.id,source_value,raw,nullif(btrim(input_payload->>'transcript'),''),changes,'draft',input_h,interp_h,auth.uid()) returning * into i;
 perform audit.append_event(p.organisation_id,p.id,'design.change.interpreted','change_instruction',i.id,null,to_jsonb(i),interp_h,gen_random_uuid());return i.id;
end;$$;
revoke all on function public.interpret_design_change(uuid,uuid,jsonb) from public,anon;grant execute on function public.interpret_design_change(uuid,uuid,jsonb) to authenticated;

create or replace function public.approve_design_change_instruction(target_instruction_id uuid,target_reason text)
returns text language plpgsql security invoker set search_path='aec','project','audit','auth','pg_temp' as $$
declare i aec.change_instructions%rowtype;p project.projects%rowtype;before_state jsonb;
begin
 select * into i from aec.change_instructions where id=target_instruction_id for update;if not found or i.status<>'draft' then raise exception 'draft_change_instruction_required';end if;select * into p from project.projects where id=i.project_id;if auth.uid() is null or not project.can_manage_project(p.id) then raise exception 'project_manage_authority_required';end if;if nullif(btrim(target_reason),'') is null then raise exception 'change_instruction_approval_reason_required';end if;
 before_state:=to_jsonb(i);perform set_config('conceptspaces.design_change_phase','approve',true);update aec.change_instructions set status='approved',approved_by=auth.uid(),approved_at=now() where id=i.id returning * into i;perform audit.append_event(p.organisation_id,p.id,'design.change.approved','change_instruction',i.id,before_state,to_jsonb(i),target_reason,gen_random_uuid());return i.status;
end;$$;
revoke all on function public.approve_design_change_instruction(uuid,text) from public,anon;grant execute on function public.approve_design_change_instruction(uuid,text) to authenticated;

create or replace function public.execute_design_change_instruction(target_instruction_id uuid,target_reason text)
returns jsonb language plpgsql security invoker set search_path='aec','public','project','audit','extensions','auth','pg_temp' as $$
declare i aec.change_instructions%rowtype;p project.projects%rowtype;b public.project_branches%rowtype;ch jsonb;prev aec.object_revisions%rowtype;new_rev aec.object_revisions%rowtype;action_value text;key_value text;rev int;geometry_value text;properties_value jsonb;content_h text;changed_refs jsonb:='[]'::jsonb;execution_h text;
begin
 select * into i from aec.change_instructions where id=target_instruction_id for update;if not found or i.status<>'approved' then raise exception 'approved_change_instruction_required';end if;select * into p from project.projects where id=i.project_id;if auth.uid() is null or not project.can_manage_project(p.id) then raise exception 'project_manage_authority_required';end if;select * into b from public.project_branches where id=i.branch_id and project_id=p.id and status='active';if not found or b.name='main' then raise exception 'DESIGN_CHANGE_EXECUTION_REQUIRES_NON_MAIN_BRANCH';end if;if nullif(btrim(target_reason),'') is null then raise exception 'change_execution_reason_required';end if;
 perform set_config('conceptspaces.design_change_phase','execute',true);
 for ch in select value from jsonb_array_elements(i.structured_changes) loop
   action_value:=lower(coalesce(ch->>'action',''));key_value:=nullif(btrim(ch->>'object_key'),'');if action_value not in ('add','modify','remove') or key_value is null then raise exception 'design_change_action_object_key_required';end if;
   select * into prev from aec.object_revisions where project_id=p.id and branch_id=b.id and object_key=key_value order by revision desc limit 1;
   if action_value='add' and found and prev.state<>'removed' then raise exception 'OBJECT_ALREADY_EXISTS:%',key_value;end if;if action_value in ('modify','remove') and (not found or prev.state='removed') then raise exception 'OBJECT_NOT_AVAILABLE:%',key_value;end if;
   select coalesce(max(revision),0)+1 into rev from aec.object_revisions where project_id=p.id and branch_id=b.id and object_key=key_value;
   geometry_value:=case when ch ? 'geometry_hash' then nullif(lower(ch->>'geometry_hash'),'') else prev.geometry_hash end;if geometry_value is not null and geometry_value !~ '^[0-9a-f]{64}$' then raise exception 'OBJECT_GEOMETRY_HASH_INVALID:%',key_value;end if;
   properties_value:=case when action_value='add' then coalesce(ch->'properties','{}'::jsonb) when action_value='modify' then coalesce(prev.properties,'{}'::jsonb)||coalesce(ch->'properties','{}'::jsonb) else coalesce(prev.properties,'{}'::jsonb) end;
   content_h:=encode(extensions.digest(jsonb_build_object('project_id',p.id,'branch_id',b.id,'object_key',key_value,'revision',rev,'action',action_value,'geometry_hash',geometry_value,'properties',properties_value,'source_instruction_id',i.id)::text,'sha256'),'hex');
   insert into aec.object_revisions(project_id,branch_id,object_key,revision,state,geometry_hash,properties,source_instruction_id,parent_revision_id,content_hash,created_by) values(p.id,b.id,key_value,rev,case when action_value='remove' then 'removed' else 'active' end,geometry_value,properties_value,i.id,prev.id,content_h,auth.uid()) returning * into new_rev;
   changed_refs:=changed_refs||jsonb_build_array('object:'||key_value||':v'||rev::text);
 end loop;
 execution_h:=encode(extensions.digest(jsonb_build_object('instruction_hash',i.interpretation_hash,'branch_id',b.id,'changes',changed_refs,'reason',target_reason)::text,'sha256'),'hex');
 perform set_config('conceptspaces.design_change_phase','execute',true);update aec.change_instructions set status='executed',execution_hash=execution_h,executed_by=auth.uid(),executed_at=now() where id=i.id returning * into i;
 perform set_config('conceptspaces.configuration_phase','commit',true);insert into public.project_commits(project_id,branch_id,parent_commit_hashes,content_hash,message,changed_object_refs,author_type,author_ref) values(p.id,b.id,jsonb_build_array(b.head_commit_hash),execution_h,'Approved design instruction execution '||i.id::text,changed_refs,'human',auth.uid()::text) on conflict(project_id,content_hash) do nothing;update public.project_branches set head_commit_hash=execution_h where id=b.id;
 perform audit.append_event(p.organisation_id,p.id,'design.change.executed','change_instruction',i.id,null,to_jsonb(i),execution_h,gen_random_uuid());return jsonb_build_object('instruction_id',i.id,'branch_id',b.id,'execution_hash',execution_h,'changed_object_refs',changed_refs);
end;$$;
revoke all on function public.execute_design_change_instruction(uuid,text) from public,anon;grant execute on function public.execute_design_change_instruction(uuid,text) to authenticated;

create or replace function public.compare_object_revisions(target_project_id uuid,target_branch_a uuid,target_branch_b uuid)
returns jsonb language plpgsql stable security invoker set search_path='aec','public','project','auth','pg_temp' as $$
begin
 if auth.uid() is null or not project.can_access_project(target_project_id) then raise exception 'project_access_required';end if;if not exists(select 1 from public.project_branches where id=target_branch_a and project_id=target_project_id) or not exists(select 1 from public.project_branches where id=target_branch_b and project_id=target_project_id) then raise exception 'comparison_branch_not_in_project';end if;
 return coalesce((with a as (select distinct on(object_key) object_key,state,revision,geometry_hash,properties,content_hash from aec.object_revisions where project_id=target_project_id and branch_id=target_branch_a order by object_key,revision desc),b as (select distinct on(object_key) object_key,state,revision,geometry_hash,properties,content_hash from aec.object_revisions where project_id=target_project_id and branch_id=target_branch_b order by object_key,revision desc),keys as (select object_key from a union select object_key from b) select jsonb_agg(jsonb_build_object('object_key',k.object_key,'change_type',case when a.object_key is null then 'added' when b.object_key is null then 'removed' when b.state='removed' and a.state<>'removed' then 'removed' when a.state='removed' and b.state<>'removed' then 'added' when a.geometry_hash is distinct from b.geometry_hash or a.properties is distinct from b.properties then 'modified' else 'unchanged' end,'revision_a',a.revision,'revision_b',b.revision,'geometry_changed',a.geometry_hash is distinct from b.geometry_hash,'properties_changed',a.properties is distinct from b.properties,'properties_a',a.properties,'properties_b',b.properties,'hash_a',a.content_hash,'hash_b',b.content_hash) order by k.object_key) from keys k left join a using(object_key) left join b using(object_key)),'[]'::jsonb);
end;$$;
revoke all on function public.compare_object_revisions(uuid,uuid,uuid) from public,anon;grant execute on function public.compare_object_revisions(uuid,uuid,uuid) to authenticated;

create or replace function public.list_design_review_workspace(target_project_id uuid)
returns jsonb language plpgsql stable security invoker set search_path='aec','public','project','auth','pg_temp' as $$
begin
 if auth.uid() is null or not project.can_access_project(target_project_id) then raise exception 'project_access_required';end if;return jsonb_build_object('intents',coalesce((select jsonb_agg(to_jsonb(d) order by d.version desc) from aec.design_intents d where d.project_id=target_project_id),'[]'::jsonb),'branches',coalesce((select jsonb_agg(to_jsonb(b) order by case when b.name='main' then 0 else 1 end,b.created_at desc) from public.project_branches b where b.project_id=target_project_id),'[]'::jsonb),'instructions',coalesce((select jsonb_agg(to_jsonb(i) order by i.created_at desc) from aec.change_instructions i where i.project_id=target_project_id),'[]'::jsonb),'objects',coalesce((select jsonb_agg(to_jsonb(o) order by o.object_key,o.revision desc) from aec.object_revisions o where o.project_id=target_project_id),'[]'::jsonb));
end;$$;
revoke all on function public.list_design_review_workspace(uuid) from public,anon;grant execute on function public.list_design_review_workspace(uuid) to authenticated;

commit;
