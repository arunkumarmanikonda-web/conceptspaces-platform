begin;

drop policy if exists privacy_processing_update on privacy.processing_records;
create policy privacy_processing_update on privacy.processing_records for update to authenticated
using(core.has_org_role(organisation_id,array['super_admin','org_admin']))
with check(core.has_org_role(organisation_id,array['super_admin','org_admin']) and current_setting('conceptspaces.privacy_phase',true)='processing');

commit;
