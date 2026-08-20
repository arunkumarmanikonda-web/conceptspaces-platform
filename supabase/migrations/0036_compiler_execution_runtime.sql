begin;

alter table public.compilation_runs add column if not exists input_hash text;
alter table public.compilation_runs add column if not exists output_hash text;
alter table public.compilation_runs add column if not exists execution_manifest jsonb not null default '{}'::jsonb;
alter table public.compilation_runs add column if not exists blocked_reasons jsonb not null default '[]'::jsonb;
create unique index if not exists compilation_runs_project_input_unique on public.compilation_runs(project_id,input_hash) where input_hash is not null;

-- Browser access remains read-only. Compiler mutations are service-owned after user authority has been proven by the JWT-bound worker.
grant select on public.compilation_runs,public.compiler_input_snapshots,public.compiler_stage_runs,public.pareto_candidates,public.project_branches,public.project_commits to authenticated;

grant usage on schema engineering,interiors to authenticated;
grant select on engineering.engines,engineering.architecture_packages,engineering.structural_schemes,engineering.mep_systems,engineering.coordination_matrix,interiors.design_dna to authenticated;

create or replace function public.prepare_compiler_input(target_project_id uuid,target_objective text default 'balanced')
returns jsonb language plpgsql stable security invoker
set search_path=public,project,aec,regula,engineering,interiors,core,auth,pg_temp
as $$
declare p project.projects%rowtype; latest_geometry jsonb; latest_regula jsonb; payload jsonb;
begin
 if auth.uid() is null or not project.can_access_project(target_project_id) then raise exception 'project_access_required';end if;
 select * into p from project.projects where id=target_project_id;if not found then raise exception 'project_not_found';end if;
 select jsonb_build_object('id',g.id,'verification',g.verification,'engine_valid',g.engine_valid,'content_hash',g.content_hash,'area',g.area,'coordinate_system',g.coordinate_system,'source_type',g.source_type,'source_reference',g.source_reference,'geometry',g.geometry,'validation_messages',g.validation_messages,'created_at',g.created_at)
 into latest_geometry from aec.site_geometries g where g.project_id=p.id order by g.created_at desc limit 1;
 select jsonb_build_object('run',to_jsonb(er),'findings',coalesce((select jsonb_agg(jsonb_build_object('rule_id',f.rule_id,'disposition',f.disposition,'status',f.status,'explanation',f.explanation,'observed_value',f.observed_value,'required_value',f.required_value) order by f.checked_at,f.id) from regula.compliance_findings f where f.evaluation_run_id=er.id),'[]'::jsonb))
 into latest_regula from regula.evaluation_runs er where er.project_id=p.id order by er.created_at desc limit 1;
 payload:=jsonb_build_object(
  'project',jsonb_build_object('id',p.id,'organisation_id',p.organisation_id,'code',p.code::text,'name',p.name,'typology',p.typology,'stage',p.stage,'criticality',p.criticality,'status',p.status,'jurisdiction_country',p.jurisdiction_country,'jurisdiction_state',p.jurisdiction_state,'jurisdiction_city',p.jurisdiction_city),
  'objective',lower(coalesce(nullif(btrim(target_objective),''),'balanced')),
  'truth',coalesce((select jsonb_agg(jsonb_build_object('id',t.id,'kind',t.kind,'record_key',t.record_key,'value',t.value,'unit',t.unit,'status',t.status,'confidence',t.confidence,'criticality',t.criticality,'source_reference',t.source_reference) order by t.record_key,t.created_at desc) from project.truth_records t where t.project_id=p.id and t.valid_until is null),'[]'::jsonb),
  'requirements',coalesce((select jsonb_agg(jsonb_build_object('id',r.id,'code',r.code::text,'statement',r.statement,'category',r.category,'acceptance_criteria',r.acceptance_criteria,'status',r.status,'criticality',r.criticality) order by r.code) from project.requirements r where r.project_id=p.id),'[]'::jsonb),
  'geometry',latest_geometry,
  'regula',latest_regula,
  'engineering_engines',coalesce((select jsonb_agg(jsonb_build_object('id',e.id,'code',e.code::text,'discipline',e.discipline,'engine_type',e.engine_type,'version',e.version,'certification_status',e.certification_status,'maximum_criticality',e.maximum_criticality,'enabled',e.enabled) order by e.discipline,e.code) from engineering.engines e where e.enabled=true),'[]'::jsonb),
  'discipline_state',jsonb_build_object(
    'architecture',coalesce((select jsonb_agg(to_jsonb(a) order by a.created_at desc) from engineering.architecture_packages a where a.project_id=p.id),'[]'::jsonb),
    'structure',coalesce((select jsonb_agg(to_jsonb(s) order by s.created_at desc) from engineering.structural_schemes s where s.project_id=p.id),'[]'::jsonb),
    'mepf',coalesce((select jsonb_agg(to_jsonb(m) order by m.created_at desc) from engineering.mep_systems m where m.project_id=p.id),'[]'::jsonb),
    'interiors',coalesce((select jsonb_agg(to_jsonb(d) order by d.created_at desc) from interiors.design_dna d where d.project_id=p.id),'[]'::jsonb)
  )
 );return payload;
end;$$;
revoke all on function public.prepare_compiler_input(uuid,text) from public,anon;
grant execute on function public.prepare_compiler_input(uuid,text) to authenticated;

create or replace function public.authorize_compiler_runtime(target_project_id uuid)
returns boolean language sql stable security invoker set search_path=project,public,auth,pg_temp
as $$ select auth.uid() is not null and project.can_manage_project(target_project_id); $$;
revoke all on function public.authorize_compiler_runtime(uuid) from public,anon;
grant execute on function public.authorize_compiler_runtime(uuid) to authenticated;

create or replace function public.persist_compiler_run(
 target_project_id uuid,target_actor_id uuid,target_objective text,target_input_hash text,target_output_hash text,target_snapshot jsonb,target_stages jsonb,target_candidates jsonb,target_status text,target_blocked_reasons jsonb
)
returns uuid language plpgsql security invoker
set search_path=public,project,core,auth,pg_temp
as $$
declare p project.projects%rowtype; branch_id uuid; snapshot_id uuid; run_id uuid; item jsonb; candidate jsonb; branch_head text; stage_name text; stage_input_hash text; stage_output_hash text; final_status text:=lower(target_status); criticality_value text;
begin
 if current_user<>'service_role' then raise exception 'service_role_required';end if;
 if target_input_hash !~ '^[0-9a-f]{64}$' or target_output_hash !~ '^[0-9a-f]{64}$' then raise exception 'invalid_compiler_hash';end if;
 if final_status not in ('blocked','awaiting_review','completed','failed') then raise exception 'invalid_compiler_status';end if;
 select * into p from project.projects where id=target_project_id;if not found then raise exception 'project_not_found';end if;
 if not exists(select 1 from core.memberships m where m.organisation_id=p.organisation_id and m.user_id=target_actor_id and m.status='active') and not exists(select 1 from project.project_members pm where pm.project_id=p.id and pm.user_id=target_actor_id and pm.status='active') then raise exception 'actor_project_authority_required';end if;
 if jsonb_typeof(target_snapshot)<>'object' or jsonb_typeof(target_stages)<>'array' or jsonb_typeof(target_candidates)<>'array' then raise exception 'invalid_compiler_payload';end if;

 select b.id,b.head_commit_hash into branch_id,branch_head from public.project_branches b where b.project_id=p.id and b.status='active' order by b.created_at limit 1;
 if branch_id is null then branch_head:=target_input_hash;insert into public.project_branches(project_id,name,head_commit_hash,purpose,status,created_by) values(p.id,'main',branch_head,'Governed Building Compiler project branch','active',target_actor_id) returning id into branch_id;end if;

 insert into public.compiler_input_snapshots(project_id,branch_id,project_truth_hash,regulation_hash,programme_hash,requirement_hash,design_state_hash,cost_state_hash,climate_state_hash,source_refs)
 values(p.id,branch_id,coalesce(target_snapshot#>>'{hashes,project_truth}',target_input_hash),coalesce(target_snapshot#>>'{hashes,regulation}',target_input_hash),coalesce(target_snapshot#>>'{hashes,programme}',target_input_hash),coalesce(target_snapshot#>>'{hashes,requirements}',target_input_hash),target_snapshot#>>'{hashes,design}',target_snapshot#>>'{hashes,cost}',target_snapshot#>>'{hashes,climate}',coalesce(target_snapshot->'source_refs','[]'::jsonb)) returning id into snapshot_id;

 insert into public.compilation_runs(project_id,branch_id,input_snapshot_id,objective,status,requested_by,final_artifact_refs,input_hash,output_hash,execution_manifest,blocked_reasons,completed_at)
 values(p.id,branch_id,snapshot_id,left(coalesce(target_objective,'balanced'),120),final_status,target_actor_id,'[]'::jsonb,target_input_hash,target_output_hash,coalesce(target_snapshot,'{}'::jsonb),coalesce(target_blocked_reasons,'[]'::jsonb),case when final_status in ('completed','failed','blocked','awaiting_review') then now() else null end)
 on conflict(project_id,input_hash) where input_hash is not null do update set output_hash=excluded.output_hash,status=excluded.status,execution_manifest=excluded.execution_manifest,blocked_reasons=excluded.blocked_reasons,completed_at=excluded.completed_at
 returning id into run_id;
 delete from public.compiler_stage_runs where compilation_run_id=run_id;delete from public.pareto_candidates where compilation_run_id=run_id;

 for item in select value from jsonb_array_elements(target_stages) loop
   stage_name:=item->>'stage';stage_input_hash:=coalesce(item->>'input_hash',target_input_hash);stage_output_hash:=nullif(item->>'output_hash','');criticality_value:=coalesce(item->>'criticality',p.criticality);
   if stage_name not in ('project_truth','regulatory_context','programme','feasibility','option_generation','architecture','structure','mepf','interiors','quantity_cost','coordination','assurance') then raise exception 'invalid_compiler_stage';end if;
   insert into public.compiler_stage_runs(compilation_run_id,stage,status,criticality,engine_refs,agent_run_refs,input_hash,output_hash,evidence_refs,assumptions,validation_finding_refs,started_at,completed_at)
   values(run_id,stage_name,coalesce(item->>'status','blocked'),criticality_value,coalesce(item->'engine_refs','[]'::jsonb),coalesce(item->'agent_run_refs','[]'::jsonb),stage_input_hash,stage_output_hash,coalesce(item->'evidence_refs','[]'::jsonb),coalesce(item->'assumptions','[]'::jsonb),coalesce(item->'validation_finding_refs','[]'::jsonb),now(),now());
 end loop;
 for candidate in select value from jsonb_array_elements(target_candidates) loop
   insert into public.pareto_candidates(compilation_run_id,option_id,objective_metrics,dominated,constraint_violations,compliance_state,human_shortlisted)
   values(run_id,coalesce(nullif(candidate->>'option_id','')::uuid,gen_random_uuid()),coalesce(candidate->'objective_metrics','{}'::jsonb),coalesce((candidate->>'dominated')::boolean,false),coalesce(candidate->'constraint_violations','[]'::jsonb),coalesce(candidate->>'compliance_state','not_verified'),false);
 end loop;

 insert into public.project_commits(project_id,branch_id,parent_commit_hashes,content_hash,message,changed_object_refs,author_type,author_ref)
 values(p.id,branch_id,case when branch_head is null then '[]'::jsonb else jsonb_build_array(branch_head) end,target_output_hash,'Building Compiler run '||run_id::text,jsonb_build_array('compilation_run:'||run_id::text),'hybrid',target_actor_id::text)
 on conflict(project_id,content_hash) do nothing;
 update public.project_branches set head_commit_hash=target_output_hash where id=branch_id;
 return run_id;
end;$$;
revoke all on function public.persist_compiler_run(uuid,uuid,text,text,text,jsonb,jsonb,jsonb,text,jsonb) from public,anon,authenticated;
grant execute on function public.persist_compiler_run(uuid,uuid,text,text,text,jsonb,jsonb,jsonb,text,jsonb) to service_role;

create or replace function public.list_project_compiler_state(target_project_id uuid)
returns jsonb language plpgsql stable security invoker set search_path=public,project,auth,pg_temp
as $$
declare latest_run uuid;
begin
 if auth.uid() is null or not project.can_access_project(target_project_id) then raise exception 'project_access_required';end if;
 select r.id into latest_run from public.compilation_runs r where r.project_id=target_project_id order by r.created_at desc limit 1;
 return jsonb_build_object(
  'run',(select to_jsonb(r) from public.compilation_runs r where r.id=latest_run),
  'stages',coalesce((select jsonb_agg(to_jsonb(s) order by case s.stage when 'project_truth' then 1 when 'regulatory_context' then 2 when 'programme' then 3 when 'feasibility' then 4 when 'option_generation' then 5 when 'architecture' then 6 when 'structure' then 7 when 'mepf' then 8 when 'interiors' then 9 when 'quantity_cost' then 10 when 'coordination' then 11 else 12 end) from public.compiler_stage_runs s where s.compilation_run_id=latest_run),'[]'::jsonb),
  'candidates',coalesce((select jsonb_agg(to_jsonb(c) order by c.created_at) from public.pareto_candidates c where c.compilation_run_id=latest_run),'[]'::jsonb),
  'branches',coalesce((select jsonb_agg(to_jsonb(b) order by b.created_at) from public.project_branches b where b.project_id=target_project_id),'[]'::jsonb)
 );
end;$$;
revoke all on function public.list_project_compiler_state(uuid) from public,anon;
grant execute on function public.list_project_compiler_state(uuid) to authenticated;

-- Human shortlist is deliberately separate from option generation.
grant update(human_shortlisted) on public.pareto_candidates to authenticated;
drop policy if exists pareto_shortlist_update on public.pareto_candidates;
create policy pareto_shortlist_update on public.pareto_candidates for update to authenticated
using(current_setting('conceptspaces.compiler_phase',true)='shortlist' and exists(select 1 from public.compilation_runs r where r.id=compilation_run_id and project.can_manage_project(r.project_id)))
with check(current_setting('conceptspaces.compiler_phase',true)='shortlist' and human_shortlisted=true);
create or replace function public.shortlist_compiler_candidate(target_candidate_id uuid)
returns void language plpgsql security invoker set search_path=public,project,auth,pg_temp
as $$
declare c public.pareto_candidates%rowtype;run public.compilation_runs%rowtype;
begin select * into c from public.pareto_candidates where id=target_candidate_id for update;if not found then raise exception 'candidate_not_found';end if;select * into run from public.compilation_runs where id=c.compilation_run_id;if not project.can_manage_project(run.project_id) then raise exception 'project_manage_authority_required';end if;perform set_config('conceptspaces.compiler_phase','shortlist',true);update public.pareto_candidates set human_shortlisted=true where id=c.id;end;$$;
revoke all on function public.shortlist_compiler_candidate(uuid) from public,anon;grant execute on function public.shortlist_compiler_candidate(uuid) to authenticated;

commit;
