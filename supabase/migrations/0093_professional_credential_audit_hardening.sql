begin;

create or replace function public.submit_professional_credential(input_payload jsonb)
returns uuid language plpgsql security invoker
set search_path='core','audit','public','auth','pg_temp' as $$
declare credential_id uuid; org_row record; c core.professional_credentials%rowtype;
begin
 if auth.uid() is null then raise exception 'authentication_required'; end if;
 if nullif(btrim(input_payload->>'credential_type'),'') is null or nullif(btrim(input_payload->>'issuing_body'),'') is null or nullif(btrim(input_payload->>'registration_number'),'') is null then raise exception 'credential_type_issuing_body_and_registration_required'; end if;
 insert into core.professional_credentials(user_id,credential_type,issuing_body,registration_number,discipline,valid_from,valid_until,verification_status,evidence_uri)
 values(auth.uid(),btrim(input_payload->>'credential_type'),btrim(input_payload->>'issuing_body'),btrim(input_payload->>'registration_number'),nullif(btrim(input_payload->>'discipline'),''),nullif(input_payload->>'valid_from','')::date,nullif(input_payload->>'valid_until','')::date,'pending',nullif(btrim(input_payload->>'evidence_uri'),'')) returning * into c;
 credential_id:=c.id;
 for org_row in select distinct organisation_id from core.memberships where user_id=auth.uid() and status='active' loop
  perform audit.append_event(org_row.organisation_id,null,'professional.credential_submitted','professional_credential',c.id,null,to_jsonb(c),c.evidence_uri,gen_random_uuid());
 end loop;
 return credential_id;
end;$$;
revoke all on function public.submit_professional_credential(jsonb) from public,anon;grant execute on function public.submit_professional_credential(jsonb) to authenticated;

create or replace function public.review_professional_credential(target_credential_id uuid,decision text)
returns void language plpgsql security invoker
set search_path='core','audit','public','auth','pg_temp' as $$
declare c core.professional_credentials%rowtype; before_state jsonb; org_row record; d text:=lower(btrim(decision));
begin
 if d not in ('verified','rejected','expired') then raise exception 'unsupported_credential_decision'; end if;
 select * into c from core.professional_credentials where id=target_credential_id for update;if not found then raise exception 'credential_not_found'; end if;
 if not (core.is_platform_admin() or exists(select 1 from core.memberships target_m join core.memberships admin_m on admin_m.organisation_id=target_m.organisation_id where target_m.user_id=c.user_id and target_m.status='active' and admin_m.user_id=auth.uid() and admin_m.status='active' and admin_m.role_code='org_admin')) then raise exception 'credential_reviewer_authority_required'; end if;
 before_state:=to_jsonb(c);
 update core.professional_credentials set verification_status=d,verified_by=case when d='verified' then auth.uid() else null end,verified_at=case when d='verified' then now() else null end where id=target_credential_id returning * into c;
 for org_row in select distinct organisation_id from core.memberships where user_id=c.user_id and status='active' loop
  perform audit.append_event(org_row.organisation_id,null,'professional.credential_'||d,'professional_credential',c.id,before_state,to_jsonb(c),c.evidence_uri,gen_random_uuid());
 end loop;
end;$$;
revoke all on function public.review_professional_credential(uuid,text) from public,anon;grant execute on function public.review_professional_credential(uuid,text) to authenticated;

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
 if new_p.id=old_a.professional_profile_id then raise exception 'replacement_must_use_different_professional';end if;
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

commit;
