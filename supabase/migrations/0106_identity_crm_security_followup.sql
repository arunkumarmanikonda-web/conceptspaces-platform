begin;

-- Keep arbitrary-user access simulation internal/service-side; browser users use evaluate_current_access().
revoke execute on function public.simulate_access_decision(uuid,text,uuid,uuid,text[],boolean) from authenticated;
grant execute on function public.simulate_access_decision(uuid,text,uuid,uuid,text[],boolean) to service_role;

-- Lead merge is the only workflow allowed to re-parent activity records.
grant update on public.crm_activities to authenticated;
drop policy if exists crm_activities_merge_update on public.crm_activities;
create policy crm_activities_merge_update on public.crm_activities
for update to authenticated
using(core.has_org_role(organisation_id,array['super_admin','org_admin','sales','project_manager']))
with check(core.has_org_role(organisation_id,array['super_admin','org_admin','sales','project_manager']) and current_setting('conceptspaces.crm_phase',true)='merge');

commit;
