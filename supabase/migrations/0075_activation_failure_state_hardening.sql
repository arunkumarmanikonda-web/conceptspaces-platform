begin;

create or replace function public.activate_project(target_activation_id uuid,target_reason text)
returns text
language plpgsql security invoker
set search_path=public,engagement,project,core,audit,auth,pg_temp
as $$
declare a engagement.activations%rowtype; p project.projects%rowtype; c public.contracts%rowtype; before_state jsonb; missing text[]:=array[]::text[];
begin
 select * into a from engagement.activations where id=target_activation_id for update;
 if not found then raise exception 'activation_not_found'; end if;
 select * into p from project.projects where id=a.project_id for update;
 select * into c from public.contracts where id=a.contract_id;
 if auth.uid() is null or not project.can_manage_project(p.id) then raise exception 'project_activation_authority_required'; end if;
 if nullif(btrim(target_reason),'') is null then raise exception 'activation_reason_required'; end if;
 if not a.proposal_accepted then missing:=array_append(missing,'proposal_accepted'); end if;
 if not a.contract_executed or c.status<>'active' or c.execution_hash is null then missing:=array_append(missing,'contract_executed'); end if;
 if not a.initial_payment_satisfied then missing:=array_append(missing,'initial_payment'); end if;
 if not a.required_kyc_satisfied then missing:=array_append(missing,'required_kyc'); end if;
 if not a.project_team_ready then missing:=array_append(missing,'project_team'); end if;
 if not a.client_users_ready then missing:=array_append(missing,'client_users'); end if;
 if not a.site_info_ready then missing:=array_append(missing,'site_info'); end if;
 if not a.data_classification_ready then missing:=array_append(missing,'data_classification'); end if;
 before_state:=to_jsonb(a);
 perform set_config('conceptspaces.activation_phase','activation_execute',true);
 if cardinality(missing)>0 then
   update engagement.activations set state='blocked',blocked_reason='ACTIVATION_PREREQUISITE_MISSING:'||array_to_string(missing,','),updated_at=now() where id=a.id returning * into a;
   perform audit.append_event(p.organisation_id,p.id,'project.activation.blocked','activation',a.id,before_state,to_jsonb(a),array_to_string(missing,','),gen_random_uuid());
   return 'blocked';
 end if;
 update engagement.activations set state='activated',blocked_reason=null,activated_by=auth.uid(),activated_at=now(),updated_at=now() where id=a.id returning * into a;
 update project.projects set lifecycle_state='active',status='active',updated_at=now() where id=p.id;
 if not exists(select 1 from project.project_stages s where s.project_id=p.id and s.source_contract_id=c.id and s.state<>'superseded') then perform public.initialise_project_stage_plan(p.id,c.id,'{}'::jsonb); end if;
 perform audit.append_event(p.organisation_id,p.id,'project.activated','activation',a.id,before_state,to_jsonb(a),target_reason,gen_random_uuid());
 return 'active';
end;$$;

create or replace function public.transition_project_stage(target_project_stage_id uuid,target_state text,input_payload jsonb default '{}'::jsonb)
returns text
language plpgsql security invoker
set search_path=public,project,audit,auth,pg_temp
as $$
declare s project.project_stages%rowtype; p project.projects%rowtype; state_value text:=lower(btrim(target_state)); dep text; before_state jsonb;
begin
 select * into s from project.project_stages where id=target_project_stage_id for update; if not found then raise exception 'project_stage_not_found'; end if;
 select * into p from project.projects where id=s.project_id;
 if auth.uid() is null or not project.can_manage_project(p.id) then raise exception 'stage_transition_authority_required'; end if;
 if p.lifecycle_state<>'active' then raise exception 'project_not_active'; end if;
 if state_value not in ('ready','in_progress','internal_review','client_review','approved','frozen') then raise exception 'stage_state_invalid'; end if;
 if s.state in ('superseded','frozen') then raise exception 'terminal_stage_state'; end if;
 if state_value='ready' then
   if s.state<>'not_started' then raise exception 'invalid_stage_transition'; end if;
   for dep in select jsonb_array_elements_text(s.dependencies) loop
     if not exists(select 1 from project.project_stages d where d.project_id=s.project_id and d.stage_code=dep and d.baseline_version=s.baseline_version and d.state='frozen') then raise exception 'STAGE_DEPENDENCY_BLOCKED:%',dep; end if;
   end loop;
 end if;
 if state_value='in_progress' and s.state<>'ready' then raise exception 'stage_readiness_required'; end if;
 if state_value='internal_review' and s.state<>'in_progress' then raise exception 'invalid_stage_transition'; end if;
 if state_value='client_review' and s.state<>'internal_review' then raise exception 'invalid_stage_transition'; end if;
 if state_value='approved' and s.state not in ('internal_review','client_review') then raise exception 'invalid_stage_transition'; end if;
 if state_value='frozen' and s.state<>'approved' then raise exception 'invalid_stage_transition'; end if;
 if state_value in ('internal_review','client_review','approved','frozen') and (jsonb_typeof(coalesce(input_payload->'evidence_refs','[]'::jsonb))<>'array' or jsonb_array_length(coalesce(input_payload->'evidence_refs','[]'::jsonb))=0) then raise exception 'stage_transition_evidence_required'; end if;
 before_state:=to_jsonb(s); perform set_config('conceptspaces.activation_phase','stage_transition',true);
 update project.project_stages set state=state_value,actual_start=case when state_value='in_progress' and actual_start is null then current_date else actual_start end,actual_finish=case when state_value='frozen' then current_date else actual_finish end,updated_at=now() where id=s.id returning * into s;
 insert into project.stage_events(project_stage_id,project_id,from_state,to_state,reason,evidence_refs,actor_id) values(s.id,s.project_id,before_state->>'state',state_value,nullif(btrim(input_payload->>'reason'),''),coalesce(input_payload->'evidence_refs','[]'::jsonb),auth.uid());
 perform audit.append_event(p.organisation_id,p.id,'project.stage.'||state_value,'project_stage',s.id,before_state,to_jsonb(s),input_payload->>'reason',gen_random_uuid());
 return s.state;
end;$$;

commit;
