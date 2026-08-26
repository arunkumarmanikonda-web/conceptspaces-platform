begin;

create or replace function project.current_user_has_project_role(target_project_id uuid,allowed_roles text[])
returns boolean
language sql
stable
security invoker
set search_path='project','auth','pg_temp'
as $$
 select exists(
  select 1 from project.project_members pm
  where pm.project_id=target_project_id and pm.user_id=auth.uid() and pm.status='active' and pm.role_code=any(allowed_roles)
 );
$$;
revoke all on function project.current_user_has_project_role(uuid,text[]) from public,anon;
grant execute on function project.current_user_has_project_role(uuid,text[]) to authenticated;

create or replace function aec.guard_approved_programme_baseline()
returns trigger language plpgsql security definer set search_path='aec','pg_temp' as $$
begin
 if old.status='approved' then
  if not (new.status='superseded' and current_setting('conceptspaces.design_phase',true)='programme') then raise exception 'approved_programme_immutable'; end if;
  if (to_jsonb(new)-'status'-'updated_at') is distinct from (to_jsonb(old)-'status'-'updated_at') then raise exception 'approved_programme_content_immutable'; end if;
 end if;
 return new;
end;$$;
revoke all on function aec.guard_approved_programme_baseline() from public,anon,authenticated;
drop trigger if exists trg_guard_approved_programme on aec.programme_baselines;
create trigger trg_guard_approved_programme before update on aec.programme_baselines for each row execute function aec.guard_approved_programme_baseline();

create or replace function public.create_programme_baseline(target_project_id uuid,input_payload jsonb)
returns uuid
language plpgsql security invoker
set search_path='public','aec','project','audit','extensions','auth','pg_temp'
as $$
declare baseline aec.programme_baselines%rowtype; item jsonb; version_value integer; hash_value text; item_hash_value text;
begin
 if auth.uid() is null or not project.can_manage_project(target_project_id) or not project.current_user_has_project_role(target_project_id,array['lead_architect','design_architect','project_architect','project_manager']) then raise exception 'programme_authority_required'; end if;
 if nullif(btrim(input_payload->>'title'),'') is null then raise exception 'programme_title_required'; end if;
 if jsonb_typeof(coalesce(input_payload->'items','[]'::jsonb))<>'array' or jsonb_array_length(coalesce(input_payload->'items','[]'::jsonb))=0 then raise exception 'programme_items_required'; end if;
 select coalesce(max(version),0)+1 into version_value from aec.programme_baselines where project_id=target_project_id;
 hash_value:=encode(extensions.digest(jsonb_build_object('project_id',target_project_id,'version',version_value,'title',btrim(input_payload->>'title'),'source_refs',coalesce(input_payload->'source_refs','[]'::jsonb),'items',input_payload->'items')::text,'sha256'),'hex');
 perform set_config('conceptspaces.design_phase','programme',true);
 insert into aec.programme_baselines(project_id,version,title,source_refs,status,programme_hash,created_by)
 values(target_project_id,version_value,btrim(input_payload->>'title'),coalesce(input_payload->'source_refs','[]'::jsonb),'draft',hash_value,auth.uid()) returning * into baseline;
 for item in select value from jsonb_array_elements(input_payload->'items') loop
  if nullif(btrim(item->>'code'),'') is null or nullif(btrim(item->>'space_type'),'') is null or coalesce(nullif(item->>'quantity','')::numeric,0)<=0 or nullif(btrim(item->>'source_ref'),'') is null then raise exception 'programme_item_invalid'; end if;
  if upper(coalesce(nullif(btrim(item->>'confidence'),''),'C')) not in ('A','B','C','D') then raise exception 'programme_item_confidence_invalid'; end if;
  item_hash_value:=encode(extensions.digest(jsonb_build_object('baseline_hash',hash_value,'item',item)::text,'sha256'),'hex');
  insert into aec.programme_items(programme_baseline_id,project_id,code,space_type,zone,quantity,target_area_each,area_unit,capacity,adjacency,operational_rules,priority,source_ref,confidence,notes,item_hash)
  values(baseline.id,target_project_id,upper(btrim(item->>'code')),btrim(item->>'space_type'),nullif(btrim(item->>'zone'),''),coalesce(nullif(item->>'quantity','')::numeric,1),nullif(item->>'target_area_each','')::numeric,coalesce(nullif(btrim(item->>'area_unit'),''),'sqm'),nullif(item->>'capacity','')::numeric,coalesce(item->'adjacency','[]'::jsonb),coalesce(item->'operational_rules','{}'::jsonb),coalesce(nullif(lower(btrim(item->>'priority')),''),'must'),btrim(item->>'source_ref'),upper(coalesce(nullif(btrim(item->>'confidence'),''),'C')),nullif(btrim(item->>'notes'),''),item_hash_value);
 end loop;
 perform audit.append_event((select organisation_id from project.projects where id=target_project_id),target_project_id,'programme.baseline.created','programme_baseline',baseline.id,null,to_jsonb(baseline),hash_value,gen_random_uuid());
 return baseline.id;
end;$$;
revoke all on function public.create_programme_baseline(uuid,jsonb) from public,anon;
grant execute on function public.create_programme_baseline(uuid,jsonb) to authenticated;

create or replace function public.approve_programme_baseline(target_baseline_id uuid,target_reason text)
returns text
language plpgsql security invoker
set search_path='public','aec','project','audit','auth','pg_temp'
as $$
declare baseline aec.programme_baselines%rowtype; before_state jsonb;
begin
 select * into baseline from aec.programme_baselines where id=target_baseline_id for update;
 if not found or auth.uid() is null or not project.can_manage_project(baseline.project_id) or not project.current_user_has_project_role(baseline.project_id,array['lead_architect','project_manager','client_approver']) then raise exception 'programme_approval_authority_required'; end if;
 if baseline.status<>'draft' or nullif(btrim(target_reason),'') is null then raise exception 'programme_not_approvable'; end if;
 if not exists(select 1 from aec.programme_items i where i.programme_baseline_id=baseline.id) then raise exception 'programme_items_required'; end if;
 before_state:=to_jsonb(baseline); perform set_config('conceptspaces.design_phase','programme',true);
 update aec.programme_baselines set status='superseded',updated_at=now() where project_id=baseline.project_id and status='approved';
 update aec.programme_baselines set status='approved',approved_by=auth.uid(),approved_at=now(),updated_at=now() where id=baseline.id returning * into baseline;
 perform audit.append_event((select organisation_id from project.projects where id=baseline.project_id),baseline.project_id,'programme.baseline.approved','programme_baseline',baseline.id,before_state,to_jsonb(baseline),target_reason,gen_random_uuid());
 return baseline.status;
end;$$;
revoke all on function public.approve_programme_baseline(uuid,text) from public,anon;
grant execute on function public.approve_programme_baseline(uuid,text) to authenticated;

create or replace function public.register_climate_study(target_project_id uuid,input_payload jsonb)
returns uuid
language plpgsql security invoker
set search_path='public','aec','project','audit','auth','pg_temp'
as $$
declare study aec.climate_studies%rowtype; type_value text:=lower(btrim(input_payload->>'study_type')); confidence_value text:=upper(coalesce(nullif(btrim(input_payload->>'confidence'),''),'C'));
begin
 if auth.uid() is null or not project.can_manage_project(target_project_id) or not project.current_user_has_project_role(target_project_id,array['sustainability_consultant','lead_architect','design_architect','project_manager']) then raise exception 'climate_study_authority_required'; end if;
 if type_value not in ('sun_path','solar','shadow','daylight','glare','ventilation','wind','energy','water','flood','embodied_carbon','other') then raise exception 'climate_study_type_invalid'; end if;
 if nullif(btrim(input_payload->>'title'),'') is null or nullif(btrim(input_payload->>'engine_ref'),'') is null or nullif(btrim(input_payload->>'engine_version'),'') is null or nullif(btrim(input_payload->>'method_ref'),'') is null then raise exception 'climate_method_engine_required'; end if;
 if length(coalesce(input_payload->>'input_hash',''))<>64 or length(coalesce(input_payload->>'output_hash',''))<>64 then raise exception 'climate_hash_invalid'; end if;
 if jsonb_typeof(coalesce(input_payload->'evidence_refs','[]'::jsonb))<>'array' or jsonb_array_length(coalesce(input_payload->'evidence_refs','[]'::jsonb))=0 then raise exception 'climate_evidence_required'; end if;
 if confidence_value not in ('A','B','C','D') then raise exception 'climate_confidence_invalid'; end if;
 perform set_config('conceptspaces.design_phase','climate',true);
 insert into aec.climate_studies(project_id,study_type,title,source_model_ref,source_model_hash,weather_source_ref,engine_ref,engine_version,method_ref,input_snapshot,result_summary,evidence_refs,input_hash,output_hash,confidence,status,created_by)
 values(target_project_id,type_value,btrim(input_payload->>'title'),nullif(btrim(input_payload->>'source_model_ref'),''),nullif(btrim(input_payload->>'source_model_hash'),''),nullif(btrim(input_payload->>'weather_source_ref'),''),btrim(input_payload->>'engine_ref'),btrim(input_payload->>'engine_version'),btrim(input_payload->>'method_ref'),coalesce(input_payload->'input_snapshot','{}'::jsonb),coalesce(input_payload->'result_summary','{}'::jsonb),input_payload->'evidence_refs',input_payload->>'input_hash',input_payload->>'output_hash',confidence_value,'completed',auth.uid()) returning * into study;
 perform audit.append_event((select organisation_id from project.projects where id=target_project_id),target_project_id,'climate.study.registered','climate_study',study.id,null,to_jsonb(study),study.output_hash,gen_random_uuid());
 return study.id;
end;$$;
revoke all on function public.register_climate_study(uuid,jsonb) from public,anon;
grant execute on function public.register_climate_study(uuid,jsonb) to authenticated;

create or replace function public.review_climate_study(target_study_id uuid,target_decision text,target_reason text)
returns text
language plpgsql security invoker
set search_path='public','aec','project','audit','auth','pg_temp'
as $$
declare study aec.climate_studies%rowtype; before_state jsonb; decision_value text:=lower(btrim(target_decision));
begin
 select * into study from aec.climate_studies where id=target_study_id for update;
 if not found or auth.uid() is null or not project.can_manage_project(study.project_id) or not project.current_user_has_project_role(study.project_id,array['sustainability_consultant','lead_architect','project_manager']) then raise exception 'climate_review_authority_required'; end if;
 if decision_value not in ('reviewed','approved','rejected') or nullif(btrim(target_reason),'') is null then raise exception 'climate_review_invalid'; end if;
 if study.status not in ('completed','reviewed') then raise exception 'climate_study_not_reviewable'; end if;
 if decision_value='approved' and study.created_by=auth.uid() then raise exception 'climate_approval_independent_review_required'; end if;
 before_state:=to_jsonb(study); perform set_config('conceptspaces.design_phase','climate',true);
 update aec.climate_studies set status=decision_value,reviewed_by=auth.uid(),reviewed_at=now(),approved_by=case when decision_value='approved' then auth.uid() else approved_by end,approved_at=case when decision_value='approved' then now() else approved_at end,updated_at=now() where id=study.id returning * into study;
 perform audit.append_event((select organisation_id from project.projects where id=study.project_id),study.project_id,'climate.study.'||decision_value,'climate_study',study.id,before_state,to_jsonb(study),target_reason,gen_random_uuid()); return study.status;
end;$$;
revoke all on function public.review_climate_study(uuid,text,text) from public,anon;
grant execute on function public.review_climate_study(uuid,text,text) to authenticated;

create or replace function public.create_economic_scenario(target_project_id uuid,input_payload jsonb)
returns uuid
language plpgsql security invoker
set search_path='public','aec','project','audit','auth','pg_temp'
as $$
declare scenario aec.economic_scenarios%rowtype; version_value integer; confidence_value text:=upper(coalesce(nullif(btrim(input_payload->>'confidence'),''),'C'));
begin
 if auth.uid() is null or not project.can_manage_project(target_project_id) or not project.current_user_has_project_role(target_project_id,array['qs_cost_manager','project_manager','finance','lead_architect','client_approver']) then raise exception 'economics_authority_required'; end if;
 if nullif(btrim(input_payload->>'name'),'') is null or nullif(btrim(input_payload->>'calculation_ref'),'') is null or nullif(btrim(input_payload->>'model_version'),'') is null then raise exception 'economic_model_identity_required'; end if;
 if jsonb_typeof(coalesce(input_payload->'assumptions','{}'::jsonb))<>'object' or jsonb_typeof(coalesce(input_payload->'assumption_sources','{}'::jsonb))<>'object' or jsonb_typeof(coalesce(input_payload->'metrics','{}'::jsonb))<>'object' then raise exception 'economic_payload_invalid'; end if;
 if coalesce(input_payload->'metrics','{}'::jsonb)='{}'::jsonb then raise exception 'economic_metrics_required'; end if;
 if length(coalesce(input_payload->>'input_hash',''))<>64 or length(coalesce(input_payload->>'output_hash',''))<>64 then raise exception 'economic_hash_invalid'; end if;
 if confidence_value not in ('A','B','C','D') then raise exception 'economic_confidence_invalid'; end if;
 select coalesce(max(version),0)+1 into version_value from aec.economic_scenarios where project_id=target_project_id and name=btrim(input_payload->>'name');
 perform set_config('conceptspaces.design_phase','economics',true);
 insert into aec.economic_scenarios(project_id,name,version,assumptions,assumption_sources,metrics,sensitivity,calculation_ref,model_version,input_hash,output_hash,confidence,status,created_by)
 values(target_project_id,btrim(input_payload->>'name'),version_value,input_payload->'assumptions',input_payload->'assumption_sources',input_payload->'metrics',coalesce(input_payload->'sensitivity','{}'::jsonb),btrim(input_payload->>'calculation_ref'),btrim(input_payload->>'model_version'),input_payload->>'input_hash',input_payload->>'output_hash',confidence_value,'draft',auth.uid()) returning * into scenario;
 perform audit.append_event((select organisation_id from project.projects where id=target_project_id),target_project_id,'economics.scenario.created','economic_scenario',scenario.id,null,to_jsonb(scenario),scenario.output_hash,gen_random_uuid()); return scenario.id;
end;$$;
revoke all on function public.create_economic_scenario(uuid,jsonb) from public,anon;
grant execute on function public.create_economic_scenario(uuid,jsonb) to authenticated;

create or replace function public.review_economic_scenario(target_scenario_id uuid,target_decision text,target_reason text)
returns text
language plpgsql security invoker
set search_path='public','aec','project','audit','auth','pg_temp'
as $$
declare scenario aec.economic_scenarios%rowtype; before_state jsonb; decision_value text:=lower(btrim(target_decision));
begin
 select * into scenario from aec.economic_scenarios where id=target_scenario_id for update;
 if not found or auth.uid() is null or not project.can_manage_project(scenario.project_id) or not project.current_user_has_project_role(scenario.project_id,array['qs_cost_manager','project_manager','finance','client_approver']) then raise exception 'economics_review_authority_required'; end if;
 if scenario.status<>'draft' or decision_value not in ('reviewed','rejected') or nullif(btrim(target_reason),'') is null then raise exception 'economic_review_invalid'; end if;
 if scenario.created_by=auth.uid() then raise exception 'economic_review_maker_checker_required'; end if;
 before_state:=to_jsonb(scenario); perform set_config('conceptspaces.design_phase','economics',true);
 update aec.economic_scenarios set status=decision_value,reviewed_by=auth.uid(),reviewed_at=now(),updated_at=now() where id=scenario.id returning * into scenario;
 perform audit.append_event((select organisation_id from project.projects where id=scenario.project_id),scenario.project_id,'economics.scenario.'||decision_value,'economic_scenario',scenario.id,before_state,to_jsonb(scenario),target_reason,gen_random_uuid()); return scenario.status;
end;$$;
revoke all on function public.review_economic_scenario(uuid,text,text) from public,anon;
grant execute on function public.review_economic_scenario(uuid,text,text) to authenticated;

create or replace function public.select_economic_scenario(target_scenario_id uuid,target_reason text)
returns text
language plpgsql security invoker
set search_path='public','aec','project','audit','auth','pg_temp'
as $$
declare scenario aec.economic_scenarios%rowtype; before_state jsonb;
begin
 select * into scenario from aec.economic_scenarios where id=target_scenario_id for update;
 if not found or auth.uid() is null or not project.can_manage_project(scenario.project_id) or not project.current_user_has_project_role(scenario.project_id,array['project_manager','qs_cost_manager','client_approver']) then raise exception 'economics_selection_authority_required'; end if;
 if scenario.status<>'reviewed' or nullif(btrim(target_reason),'') is null then raise exception 'economic_scenario_not_selectable'; end if;
 before_state:=to_jsonb(scenario); perform set_config('conceptspaces.design_phase','economics',true);
 update aec.economic_scenarios set status='superseded',updated_at=now() where project_id=scenario.project_id and status='selected';
 update aec.economic_scenarios set status='selected',selected_by=auth.uid(),selected_at=now(),updated_at=now() where id=scenario.id returning * into scenario;
 perform audit.append_event((select organisation_id from project.projects where id=scenario.project_id),scenario.project_id,'economics.scenario.selected','economic_scenario',scenario.id,before_state,to_jsonb(scenario),target_reason,gen_random_uuid()); return scenario.status;
end;$$;
revoke all on function public.select_economic_scenario(uuid,text) from public,anon;
grant execute on function public.select_economic_scenario(uuid,text) to authenticated;

create or replace function public.list_programme_workspace(target_project_id uuid)
returns jsonb language plpgsql stable security invoker set search_path='public','aec','project','auth','pg_temp' as $$
begin if auth.uid() is null or not project.can_access_project(target_project_id) then raise exception 'project_access_required'; end if; return jsonb_build_object('baselines',coalesce((select jsonb_agg(to_jsonb(b) order by b.version desc) from aec.programme_baselines b where b.project_id=target_project_id),'[]'::jsonb),'items',coalesce((select jsonb_agg(to_jsonb(i) order by i.programme_baseline_id,i.code) from aec.programme_items i where i.project_id=target_project_id),'[]'::jsonb),'requirements',coalesce((select jsonb_agg(to_jsonb(r) order by r.code) from project.requirements r where r.project_id=target_project_id),'[]'::jsonb)); end;$$;
revoke all on function public.list_programme_workspace(uuid) from public,anon; grant execute on function public.list_programme_workspace(uuid) to authenticated;

create or replace function public.list_climate_workspace(target_project_id uuid)
returns jsonb language plpgsql stable security invoker set search_path='public','aec','project','auth','pg_temp' as $$
begin if auth.uid() is null or not project.can_access_project(target_project_id) then raise exception 'project_access_required'; end if; return jsonb_build_object('studies',coalesce((select jsonb_agg(to_jsonb(s) order by s.created_at desc) from aec.climate_studies s where s.project_id=target_project_id),'[]'::jsonb)); end;$$;
revoke all on function public.list_climate_workspace(uuid) from public,anon; grant execute on function public.list_climate_workspace(uuid) to authenticated;

create or replace function public.list_economics_workspace(target_project_id uuid)
returns jsonb language plpgsql stable security invoker set search_path='public','aec','project','auth','pg_temp' as $$
begin if auth.uid() is null or not project.can_access_project(target_project_id) then raise exception 'project_access_required'; end if; return jsonb_build_object('scenarios',coalesce((select jsonb_agg(to_jsonb(s) order by s.name,s.version desc) from aec.economic_scenarios s where s.project_id=target_project_id),'[]'::jsonb)); end;$$;
revoke all on function public.list_economics_workspace(uuid) from public,anon; grant execute on function public.list_economics_workspace(uuid) to authenticated;

commit;