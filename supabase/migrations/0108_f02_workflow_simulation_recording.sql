begin;

create or replace function public.record_workflow_simulation(target_workflow_id uuid,target_reason text)
returns jsonb language plpgsql security invoker set search_path='workflow','core','audit','auth','pg_temp' as $$
declare r workflow.workflow_versions%rowtype;sim jsonb;before_state jsonb;audit_org uuid;
begin
 select * into r from workflow.workflow_versions where id=target_workflow_id for update;if not found then raise exception 'workflow_version_not_found';end if;
 if auth.uid() is null then raise exception 'authentication_required';end if;
 if r.organisation_id is null then if not core.is_platform_admin() then raise exception 'platform_admin_required';end if;elsif not (core.is_platform_admin() or core.has_org_role(r.organisation_id,array['org_admin'])) then raise exception 'organisation_admin_required';end if;
 if r.status not in ('draft','review') then raise exception 'workflow_simulation_only_before_publish';end if;
 if nullif(btrim(target_reason),'') is null then raise exception 'simulation_reason_required';end if;
 before_state:=to_jsonb(r);sim:=public.simulate_workflow_version(r.id);
 perform set_config('conceptspaces.workflow_phase','review',true);
 update workflow.workflow_versions set simulation_result=sim,updated_at=now() where id=r.id returning * into r;
 audit_org:=coalesce(r.organisation_id,(select organisation_id from core.memberships where user_id=auth.uid() and status='active' limit 1));if audit_org is not null then perform audit.append_event(audit_org,null,'workflow.simulated','workflow_version',r.id,before_state,to_jsonb(r),target_reason,gen_random_uuid());end if;
 return sim;
end;$$;
revoke all on function public.record_workflow_simulation(uuid,text) from public,anon;
grant execute on function public.record_workflow_simulation(uuid,text) to authenticated;

commit;
