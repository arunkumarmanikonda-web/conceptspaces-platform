begin;

create or replace function public.upsert_professional_profile(target_organisation_id uuid,input_payload jsonb)
returns uuid language plpgsql security invoker
set search_path='engagement','core','audit','extensions','auth','pg_temp' as $$
declare target_user uuid:=coalesce(nullif(input_payload->>'user_id','')::uuid,auth.uid()); r engagement.professional_profiles%rowtype; h text; can_manage boolean;
begin
 if auth.uid() is null or not core.is_internal_org_member(target_organisation_id) then raise exception 'organisation_access_required'; end if;
 can_manage:=target_user=auth.uid() or core.has_org_role(target_organisation_id,array['super_admin','org_admin','project_manager']);
 if not can_manage then raise exception 'professional_profile_management_authority_required'; end if;
 if not exists(select 1 from core.memberships m where m.organisation_id=target_organisation_id and m.user_id=target_user and m.status='active') then raise exception 'professional_user_active_membership_required'; end if;
 if nullif(btrim(input_payload->>'discipline'),'') is null then raise exception 'professional_discipline_required'; end if;
 h:=encode(extensions.digest(jsonb_build_object('organisation_id',target_organisation_id,'user_id',target_user,'display_name',coalesce(nullif(btrim(input_payload->>'display_name'),''),(select coalesce(display_name,email::text,target_user::text) from core.profiles where user_id=target_user)),'discipline',lower(btrim(input_payload->>'discipline')),'registration_summary',coalesce(input_payload->>'registration_summary',''),'geographies',coalesce(input_payload->'geographies','[]'::jsonb),'typologies',coalesce(input_payload->'typologies','[]'::jsonb),'skills',coalesce(input_payload->'skills','[]'::jsonb),'years_experience',coalesce(nullif(input_payload->>'years_experience','')::numeric,0),'fee_rate',nullif(input_payload->>'fee_rate','')::numeric,'fee_currency',upper(coalesce(nullif(input_payload->>'fee_currency',''),'INR')),'capacity_hours_week',coalesce(nullif(input_payload->>'capacity_hours_week','')::numeric,40),'availability_status',lower(coalesce(nullif(input_payload->>'availability_status',''),'active')))::text,'sha256'),'hex');
 perform set_config('conceptspaces.professional_phase','profile',true);
 insert into engagement.professional_profiles(organisation_id,user_id,display_name,discipline,registration_summary,geographies,typologies,skills,years_experience,fee_rate,fee_currency,capacity_hours_week,availability_status,profile_hash,created_by)
 values(target_organisation_id,target_user,coalesce(nullif(btrim(input_payload->>'display_name'),''),(select coalesce(display_name,email::text,target_user::text) from core.profiles where user_id=target_user)),lower(btrim(input_payload->>'discipline')),nullif(btrim(input_payload->>'registration_summary'),''),coalesce(input_payload->'geographies','[]'::jsonb),coalesce(input_payload->'typologies','[]'::jsonb),coalesce(input_payload->'skills','[]'::jsonb),coalesce(nullif(input_payload->>'years_experience','')::numeric,0),nullif(input_payload->>'fee_rate','')::numeric,upper(coalesce(nullif(input_payload->>'fee_currency',''),'INR')),coalesce(nullif(input_payload->>'capacity_hours_week','')::numeric,40),lower(coalesce(nullif(input_payload->>'availability_status',''),'active')),h,auth.uid())
 on conflict(organisation_id,user_id) do update set display_name=excluded.display_name,discipline=excluded.discipline,registration_summary=excluded.registration_summary,geographies=excluded.geographies,typologies=excluded.typologies,skills=excluded.skills,years_experience=excluded.years_experience,fee_rate=excluded.fee_rate,fee_currency=excluded.fee_currency,capacity_hours_week=excluded.capacity_hours_week,availability_status=excluded.availability_status,profile_hash=excluded.profile_hash,updated_at=now() returning * into r;
 perform audit.append_event(target_organisation_id,null,'professional.profile_saved','professional_profile',r.id,null,to_jsonb(r),h,gen_random_uuid());return r.id;
end;$$;
revoke all on function public.upsert_professional_profile(uuid,jsonb) from public,anon;grant execute on function public.upsert_professional_profile(uuid,jsonb) to authenticated;

create or replace function public.record_professional_competency(target_profile_id uuid,input_payload jsonb)
returns uuid language plpgsql security invoker
set search_path='engagement','core','audit','auth','pg_temp' as $$
declare p engagement.professional_profiles%rowtype; r engagement.professional_competencies%rowtype; code_value text:=lower(btrim(input_payload->>'competency_code')); level_value int:=nullif(input_payload->>'level','')::int;
begin
 select * into p from engagement.professional_profiles where id=target_profile_id;if not found then raise exception 'professional_profile_not_found'; end if;
 if auth.uid() is null or not core.has_org_role(p.organisation_id,array['super_admin','org_admin','project_manager']) then raise exception 'competency_verification_authority_required'; end if;
 if code_value='' or level_value not between 1 and 5 then raise exception 'competency_code_or_level_invalid'; end if;
 perform set_config('conceptspaces.professional_phase','competency',true);
 insert into engagement.professional_competencies(profile_id,organisation_id,competency_code,level,evidence_refs,verified_by,verified_at)
 values(p.id,p.organisation_id,code_value,level_value,coalesce(input_payload->'evidence_refs','[]'::jsonb),auth.uid(),now())
 on conflict(profile_id,competency_code) do update set level=excluded.level,evidence_refs=excluded.evidence_refs,verified_by=auth.uid(),verified_at=now() returning * into r;
 perform audit.append_event(p.organisation_id,null,'professional.competency_verified','professional_competency',r.id,null,to_jsonb(r),null,gen_random_uuid());return r.id;
end;$$;
revoke all on function public.record_professional_competency(uuid,jsonb) from public,anon;grant execute on function public.record_professional_competency(uuid,jsonb) to authenticated;

create or replace function public.record_professional_availability(target_profile_id uuid,input_payload jsonb)
returns uuid language plpgsql security invoker
set search_path='engagement','core','audit','auth','pg_temp' as $$
declare p engagement.professional_profiles%rowtype; r engagement.professional_availability%rowtype;
begin
 select * into p from engagement.professional_profiles where id=target_profile_id;if not found then raise exception 'professional_profile_not_found'; end if;
 if auth.uid() is null or not (p.user_id=auth.uid() or core.has_org_role(p.organisation_id,array['super_admin','org_admin','project_manager'])) then raise exception 'availability_authority_required'; end if;
 perform set_config('conceptspaces.professional_phase','availability',true);
 insert into engagement.professional_availability(profile_id,organisation_id,available_from,available_until,capacity_hours_week,note,created_by)
 values(p.id,p.organisation_id,coalesce(nullif(input_payload->>'available_from','')::date,current_date),nullif(input_payload->>'available_until','')::date,coalesce(nullif(input_payload->>'capacity_hours_week','')::numeric,p.capacity_hours_week),nullif(btrim(input_payload->>'note'),''),auth.uid()) returning * into r;
 perform audit.append_event(p.organisation_id,null,'professional.availability_recorded','professional_availability',r.id,null,to_jsonb(r),null,gen_random_uuid());return r.id;
end;$$;
revoke all on function public.record_professional_availability(uuid,jsonb) from public,anon;grant execute on function public.record_professional_availability(uuid,jsonb) to authenticated;

create or replace function public.declare_professional_conflict(target_profile_id uuid,target_project_id uuid,target_conflict_type text,target_details text)
returns uuid language plpgsql security invoker
set search_path='engagement','project','core','audit','auth','pg_temp' as $$
declare p engagement.professional_profiles%rowtype; project_row project.projects%rowtype; r engagement.professional_conflicts%rowtype;
begin
 select * into p from engagement.professional_profiles where id=target_profile_id;if not found then raise exception 'professional_profile_not_found'; end if;
 select * into project_row from project.projects where id=target_project_id;if not found then raise exception 'project_not_found'; end if;
 if p.organisation_id<>project_row.organisation_id then raise exception 'professional_project_organisation_mismatch'; end if;
 if auth.uid() is null or not project.can_access_project(target_project_id) or not (p.user_id=auth.uid() or project.can_manage_project(target_project_id)) then raise exception 'conflict_declaration_authority_required'; end if;
 if nullif(btrim(target_conflict_type),'') is null or nullif(btrim(target_details),'') is null then raise exception 'conflict_type_and_details_required'; end if;
 perform set_config('conceptspaces.professional_phase','conflict',true);
 insert into engagement.professional_conflicts(profile_id,project_id,conflict_type,details,declared_by) values(p.id,target_project_id,lower(btrim(target_conflict_type)),btrim(target_details),auth.uid()) returning * into r;
 perform audit.append_event(p.organisation_id,target_project_id,'professional.conflict_declared','professional_conflict',r.id,null,to_jsonb(r),null,gen_random_uuid());return r.id;
end;$$;
revoke all on function public.declare_professional_conflict(uuid,uuid,text,text) from public,anon;grant execute on function public.declare_professional_conflict(uuid,uuid,text,text) to authenticated;

create or replace function public.clear_professional_conflict(target_conflict_id uuid,target_reason text)
returns text language plpgsql security invoker
set search_path='engagement','project','audit','auth','pg_temp' as $$
declare r engagement.professional_conflicts%rowtype; p engagement.professional_profiles%rowtype; before_state jsonb;
begin
 select * into r from engagement.professional_conflicts where id=target_conflict_id for update;if not found then raise exception 'professional_conflict_not_found'; end if;
 if auth.uid() is null or not project.can_manage_project(r.project_id) then raise exception 'conflict_clearance_authority_required'; end if;
 if r.status<>'open' then return r.status;end if;if nullif(btrim(target_reason),'') is null then raise exception 'conflict_clearance_reason_required'; end if;
 select * into p from engagement.professional_profiles where id=r.profile_id;before_state:=to_jsonb(r);perform set_config('conceptspaces.professional_phase','conflict_clear',true);
 update engagement.professional_conflicts set status='cleared',cleared_by=auth.uid(),cleared_at=now(),clearance_reason=btrim(target_reason) where id=r.id returning * into r;
 perform audit.append_event(p.organisation_id,r.project_id,'professional.conflict_cleared','professional_conflict',r.id,before_state,to_jsonb(r),target_reason,gen_random_uuid());return r.status;
end;$$;
revoke all on function public.clear_professional_conflict(uuid,text) from public,anon;grant execute on function public.clear_professional_conflict(uuid,text) to authenticated;

create or replace function engagement.professional_candidate_eligible(target_profile_id uuid,target_project_id uuid,target_role_code text,target_discipline text,target_allocation numeric default 0)
returns boolean language plpgsql stable security invoker
set search_path='engagement','core','project','auth','pg_temp' as $$
declare p engagement.professional_profiles%rowtype; proj project.projects%rowtype; req engagement.professional_role_requirements%rowtype; current_allocation numeric; controlled_role boolean:=lower(target_role_code) in ('lead_architect','architect','structural_engineer','mep_engineer','quantity_surveyor','regulatory_reviewer');
begin
 select * into p from engagement.professional_profiles where id=target_profile_id;if not found then return false;end if;
 select * into proj from project.projects where id=target_project_id;if not found or p.organisation_id<>proj.organisation_id then return false;end if;
 if p.availability_status in ('unavailable','suspended') then return false;end if;
 if lower(p.discipline)<>lower(btrim(target_discipline)) then return false;end if;
 if exists(select 1 from engagement.professional_conflicts c where c.profile_id=p.id and c.project_id=target_project_id and c.status='open') then return false;end if;
 if controlled_role and not core.has_verified_professional_eligibility(p.user_id,lower(target_role_code)) then return false;end if;
 select * into req from engagement.professional_role_requirements r where r.project_id=target_project_id and lower(r.role_code::text)=lower(target_role_code) and lower(r.discipline)=lower(target_discipline) order by r.created_at desc limit 1;
 if found and jsonb_array_length(req.credential_types)>0 and exists(select 1 from jsonb_array_elements_text(req.credential_types) x where not exists(select 1 from core.professional_credentials c where c.user_id=p.user_id and c.credential_type=x and c.verification_status='verified' and (c.valid_from is null or c.valid_from<=current_date) and (c.valid_until is null or c.valid_until>=current_date))) then return false;end if;
 select coalesce(sum(coalesce(a.allocation_percent,0)),0) into current_allocation from engagement.project_professional_assignments a where a.user_id=p.user_id and a.state in ('accepted','active') and (a.ends_at is null or a.ends_at>now());
 if current_allocation+coalesce(target_allocation,0)>100 then return false;end if;
 return true;
end;$$;
revoke all on function engagement.professional_candidate_eligible(uuid,uuid,text,text,numeric) from public,anon;grant execute on function engagement.professional_candidate_eligible(uuid,uuid,text,text,numeric) to authenticated;

create or replace function public.recommend_professionals(target_project_id uuid,target_role_code text,target_discipline text)
returns jsonb language plpgsql stable security invoker
set search_path='engagement','core','project','auth','pg_temp' as $$
declare proj project.projects%rowtype;
begin
 if auth.uid() is null or not project.can_access_project(target_project_id) then raise exception 'project_access_required';end if;
 select * into proj from project.projects where id=target_project_id;
 return coalesce((select jsonb_agg(to_jsonb(x) order by x.score desc,x.display_name) from (
  select p.id profile_id,p.user_id,p.display_name,p.discipline,p.years_experience,p.skills,p.typologies,p.capacity_hours_week,p.availability_status,
   round((50 + least(p.years_experience,15) + case when p.typologies ? proj.typology then 10 else 0 end + greatest(0,25-coalesce(w.allocated,0)/4))::numeric,2) score,
   coalesce(w.allocated,0) allocated_percent,
   jsonb_build_array('eligible','no_open_conflict','capacity_available') evidence
  from engagement.professional_profiles p
  left join lateral (select coalesce(sum(coalesce(a.allocation_percent,0)),0) allocated from engagement.project_professional_assignments a where a.user_id=p.user_id and a.state in ('accepted','active') and (a.ends_at is null or a.ends_at>now())) w on true
  where p.organisation_id=proj.organisation_id and engagement.professional_candidate_eligible(p.id,target_project_id,target_role_code,target_discipline,0)
 ) x),'[]'::jsonb);
end;$$;
revoke all on function public.recommend_professionals(uuid,text,text) from public,anon;grant execute on function public.recommend_professionals(uuid,text,text) to authenticated;

create or replace function public.assign_project_professional(target_project_id uuid,target_profile_id uuid,target_role_code text,target_discipline text,target_allocation_percent numeric,target_appointment_ref text)
returns uuid language plpgsql security invoker
set search_path='engagement','project','audit','extensions','auth','pg_temp' as $$
declare p engagement.professional_profiles%rowtype; proj project.projects%rowtype; a engagement.project_professional_assignments%rowtype; h text;
begin
 if auth.uid() is null or not project.can_manage_project(target_project_id) then raise exception 'professional_assignment_authority_required';end if;
 select * into p from engagement.professional_profiles where id=target_profile_id;if not found then raise exception 'professional_profile_not_found';end if;
 select * into proj from project.projects where id=target_project_id;if p.organisation_id<>proj.organisation_id then raise exception 'professional_project_organisation_mismatch';end if;
 if target_allocation_percent<=0 or target_allocation_percent>100 then raise exception 'professional_allocation_invalid';end if;
 if not engagement.professional_candidate_eligible(p.id,target_project_id,target_role_code,target_discipline,target_allocation_percent) then raise exception 'NO_ELIGIBLE_PROFESSIONAL';end if;
 if lower(target_role_code) in ('lead_architect','architect','structural_engineer','mep_engineer','quantity_surveyor','regulatory_reviewer') and nullif(btrim(target_appointment_ref),'') is null then raise exception 'professional_appointment_reference_required';end if;
 h:=encode(extensions.digest(jsonb_build_object('project_id',target_project_id,'profile_id',p.id,'user_id',p.user_id,'role',lower(target_role_code),'discipline',lower(target_discipline),'allocation',target_allocation_percent,'appointment_ref',coalesce(target_appointment_ref,''))::text,'sha256'),'hex');
 perform set_config('conceptspaces.professional_phase','assign',true);
 insert into engagement.project_professional_assignments(project_id,role_code,discipline,user_id,professional_profile_id,state,starts_at,allocation_percent,appointment_ref,assigned_by,assignment_hash)
 values(target_project_id,lower(target_role_code),lower(target_discipline),p.user_id,p.id,'active',now(),target_allocation_percent,nullif(btrim(target_appointment_ref),''),auth.uid(),h) returning * into a;
 insert into engagement.professional_assignment_events(assignment_id,project_id,event_type,to_state,reason,actor_id,snapshot) values(a.id,target_project_id,'assigned','active','Human assignment from eligible recommendation set',auth.uid(),to_jsonb(a));
 perform audit.append_event(proj.organisation_id,target_project_id,'professional.assignment_created','project_professional_assignment',a.id,null,to_jsonb(a),h,gen_random_uuid());return a.id;
end;$$;
revoke all on function public.assign_project_professional(uuid,uuid,text,text,numeric,text) from public,anon;grant execute on function public.assign_project_professional(uuid,uuid,text,text,numeric,text) to authenticated;

create or replace function public.replace_project_professional(target_assignment_id uuid,target_new_profile_id uuid,target_reason text)
returns uuid language plpgsql security invoker
set search_path='engagement','project','audit','extensions','auth','pg_temp' as $$
declare old_a engagement.project_professional_assignments%rowtype; new_p engagement.professional_profiles%rowtype; new_a engagement.project_professional_assignments%rowtype; proj project.projects%rowtype; before_state jsonb; h text;
begin
 select * into old_a from engagement.project_professional_assignments where id=target_assignment_id for update;if not found then raise exception 'professional_assignment_not_found';end if;
 if auth.uid() is null or not project.can_manage_project(old_a.project_id) then raise exception 'professional_assignment_authority_required';end if;
 if old_a.state not in ('accepted','active') then raise exception 'professional_assignment_not_replaceable';end if;
 if nullif(btrim(target_reason),'') is null then raise exception 'professional_replacement_reason_required';end if;
 select * into new_p from engagement.professional_profiles where id=target_new_profile_id;if not found then raise exception 'professional_profile_not_found';end if;
 if not engagement.professional_candidate_eligible(new_p.id,old_a.project_id,old_a.role_code::text,old_a.discipline,coalesce(old_a.allocation_percent,0)) then raise exception 'NO_ELIGIBLE_PROFESSIONAL';end if;
 select * into proj from project.projects where id=old_a.project_id;before_state:=to_jsonb(old_a);
 h:=encode(extensions.digest(jsonb_build_object('project_id',old_a.project_id,'supersedes',old_a.id,'profile_id',new_p.id,'user_id',new_p.user_id,'role',old_a.role_code::text,'discipline',old_a.discipline,'allocation',old_a.allocation_percent,'reason',btrim(target_reason))::text,'sha256'),'hex');
 perform set_config('conceptspaces.professional_phase','replace',true);
 update engagement.project_professional_assignments set state='removed',ends_at=now(),replacement_reason=btrim(target_reason),updated_at=now() where id=old_a.id returning * into old_a;
 insert into engagement.project_professional_assignments(project_id,role_code,discipline,user_id,professional_profile_id,state,starts_at,allocation_percent,appointment_ref,assigned_by,supersedes_assignment_id,replacement_reason,assignment_hash)
 values(old_a.project_id,old_a.role_code,old_a.discipline,new_p.user_id,new_p.id,'active',now(),old_a.allocation_percent,old_a.appointment_ref,auth.uid(),old_a.id,btrim(target_reason),h) returning * into new_a;
 insert into engagement.professional_assignment_events(assignment_id,project_id,event_type,from_state,to_state,reason,actor_id,snapshot) values(old_a.id,old_a.project_id,'replaced','active','removed',target_reason,auth.uid(),before_state);
 insert into engagement.professional_assignment_events(assignment_id,project_id,event_type,to_state,reason,actor_id,snapshot) values(new_a.id,new_a.project_id,'replacement_assigned','active',target_reason,auth.uid(),to_jsonb(new_a));
 perform audit.append_event(proj.organisation_id,old_a.project_id,'professional.assignment_replaced','project_professional_assignment',new_a.id,before_state,to_jsonb(new_a),target_reason,gen_random_uuid());return new_a.id;
end;$$;
revoke all on function public.replace_project_professional(uuid,uuid,text) from public,anon;grant execute on function public.replace_project_professional(uuid,uuid,text) to authenticated;

create or replace function public.record_professional_performance(target_profile_id uuid,target_project_id uuid,input_payload jsonb)
returns uuid language plpgsql security invoker
set search_path='engagement','project','audit','auth','pg_temp' as $$
declare p engagement.professional_profiles%rowtype; proj project.projects%rowtype; r engagement.professional_performance_metrics%rowtype; outcome text:=lower(btrim(input_payload->>'outcome_type'));
begin
 select * into p from engagement.professional_profiles where id=target_profile_id;if not found then raise exception 'professional_profile_not_found';end if;
 select * into proj from project.projects where id=target_project_id;if not found or proj.organisation_id<>p.organisation_id then raise exception 'professional_project_organisation_mismatch';end if;
 if auth.uid() is null or not project.can_access_project(target_project_id) then raise exception 'project_access_required';end if;
 if nullif(btrim(input_payload->>'metric_code'),'') is null or nullif(input_payload->>'metric_value','') is null or nullif(btrim(input_payload->>'unit'),'') is null then raise exception 'performance_metric_fields_required';end if;
 if outcome not in ('first_pass_quality','correction','schedule','rfi','ncr','cost_impact','review','other') then raise exception 'performance_outcome_type_invalid';end if;
 if nullif(btrim(input_payload->>'source_ref'),'') is null or nullif(btrim(input_payload->>'source_hash'),'') is null then raise exception 'performance_source_outcome_evidence_required';end if;
 perform set_config('conceptspaces.professional_phase','performance',true);
 insert into engagement.professional_performance_metrics(organisation_id,profile_id,project_id,metric_code,metric_value,unit,outcome_type,source_ref,source_hash,notes,recorded_by)
 values(proj.organisation_id,p.id,proj.id,lower(btrim(input_payload->>'metric_code')),nullif(input_payload->>'metric_value','')::numeric,btrim(input_payload->>'unit'),outcome,btrim(input_payload->>'source_ref'),btrim(input_payload->>'source_hash'),nullif(btrim(input_payload->>'notes'),''),auth.uid()) returning * into r;
 perform audit.append_event(proj.organisation_id,proj.id,'professional.performance_recorded','professional_performance_metric',r.id,null,to_jsonb(r),r.source_hash,gen_random_uuid());return r.id;
end;$$;
revoke all on function public.record_professional_performance(uuid,uuid,jsonb) from public,anon;grant execute on function public.record_professional_performance(uuid,uuid,jsonb) to authenticated;

create or replace function public.review_professional_performance(target_metric_id uuid,target_state text,target_reason text)
returns text language plpgsql security invoker
set search_path='engagement','project','audit','auth','pg_temp' as $$
declare r engagement.professional_performance_metrics%rowtype; before_state jsonb; state_value text:=lower(btrim(target_state));
begin
 select * into r from engagement.professional_performance_metrics where id=target_metric_id for update;if not found then raise exception 'professional_performance_metric_not_found';end if;
 if auth.uid() is null or not project.can_manage_project(r.project_id) then raise exception 'performance_review_authority_required';end if;
 if state_value not in ('validated','excluded') then raise exception 'performance_review_state_invalid';end if;
 if nullif(btrim(target_reason),'') is null then raise exception 'performance_review_reason_required';end if;before_state:=to_jsonb(r);
 perform set_config('conceptspaces.professional_phase','performance_review',true);
 update engagement.professional_performance_metrics set review_state=state_value,reviewed_by=auth.uid(),reviewed_at=now(),review_reason=btrim(target_reason) where id=r.id returning * into r;
 perform audit.append_event(r.organisation_id,r.project_id,'professional.performance_'||state_value,'professional_performance_metric',r.id,before_state,to_jsonb(r),target_reason,gen_random_uuid());return r.review_state;
end;$$;
revoke all on function public.review_professional_performance(uuid,text,text) from public,anon;grant execute on function public.review_professional_performance(uuid,text,text) to authenticated;

create or replace function public.list_professional_workspace(target_organisation_id uuid,target_project_id uuid default null)
returns jsonb language plpgsql stable security invoker
set search_path='engagement','core','project','auth','pg_temp' as $$
begin
 if auth.uid() is null or not core.is_internal_org_member(target_organisation_id) then raise exception 'organisation_access_required';end if;
 if target_project_id is not null and not project.can_access_project(target_project_id) then raise exception 'project_access_required';end if;
 return jsonb_build_object(
  'profiles',coalesce((select jsonb_agg(jsonb_build_object('id',p.id,'user_id',p.user_id,'display_name',p.display_name,'discipline',p.discipline,'registration_summary',p.registration_summary,'geographies',p.geographies,'typologies',p.typologies,'skills',p.skills,'years_experience',p.years_experience,'fee_rate',p.fee_rate,'fee_currency',p.fee_currency,'capacity_hours_week',p.capacity_hours_week,'availability_status',p.availability_status,'profile_hash',p.profile_hash,'credentials',coalesce((select jsonb_agg(jsonb_build_object('id',c.id,'credential_type',c.credential_type,'issuing_body',c.issuing_body,'registration_number',c.registration_number,'discipline',c.discipline,'valid_until',c.valid_until,'verification_status',c.verification_status,'evidence_uri',c.evidence_uri)) from core.professional_credentials c where c.user_id=p.user_id),'[]'::jsonb),'allocated_percent',coalesce((select sum(coalesce(a.allocation_percent,0)) from engagement.project_professional_assignments a where a.user_id=p.user_id and a.state in ('accepted','active') and (a.ends_at is null or a.ends_at>now())),0)) order by p.display_name) from engagement.professional_profiles p where p.organisation_id=target_organisation_id),'[]'::jsonb),
  'assignments',case when target_project_id is null then '[]'::jsonb else coalesce((select jsonb_agg(to_jsonb(a) order by a.created_at desc) from engagement.project_professional_assignments a where a.project_id=target_project_id),'[]'::jsonb) end,
  'conflicts',case when target_project_id is null then '[]'::jsonb else coalesce((select jsonb_agg(to_jsonb(c) order by c.declared_at desc) from engagement.professional_conflicts c where c.project_id=target_project_id),'[]'::jsonb) end,
  'performance',coalesce((select jsonb_agg(to_jsonb(m) order by m.recorded_at desc) from engagement.professional_performance_metrics m where m.organisation_id=target_organisation_id and (target_project_id is null or m.project_id=target_project_id)),'[]'::jsonb),
  'assignment_events',case when target_project_id is null then '[]'::jsonb else coalesce((select jsonb_agg(to_jsonb(e) order by e.created_at desc) from engagement.professional_assignment_events e where e.project_id=target_project_id),'[]'::jsonb) end
 );
end;$$;
revoke all on function public.list_professional_workspace(uuid,uuid) from public,anon;grant execute on function public.list_professional_workspace(uuid,uuid) to authenticated;

commit;
