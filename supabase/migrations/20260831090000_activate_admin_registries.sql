begin;

grant select,insert,update on table public.quality_gate_definitions to authenticated;
grant select,insert,update on table public.content_entries,public.content_versions to authenticated;
grant select,insert,update on table public.document_templates,public.template_versions to authenticated;
grant usage on schema feasibility to authenticated;
grant select,insert,update on table feasibility.typology_packs to authenticated;

drop policy if exists admin_quality_gate_read on public.quality_gate_definitions;
create policy admin_quality_gate_read on public.quality_gate_definitions for select to authenticated using(core.is_platform_admin());
drop policy if exists admin_quality_gate_write on public.quality_gate_definitions;
create policy admin_quality_gate_write on public.quality_gate_definitions for all to authenticated using(core.is_platform_admin()) with check(core.is_platform_admin());

drop policy if exists admin_content_entry_access on public.content_entries;
create policy admin_content_entry_access on public.content_entries for all to authenticated
using(core.is_platform_admin()) with check(core.is_platform_admin() and owner_user_id=auth.uid());
drop policy if exists admin_content_version_access on public.content_versions;
create policy admin_content_version_access on public.content_versions for all to authenticated
using(core.is_platform_admin()) with check(core.is_platform_admin() and created_by=auth.uid());

drop policy if exists admin_document_template_access on public.document_templates;
create policy admin_document_template_access on public.document_templates for all to authenticated
using(core.is_platform_admin()) with check(core.is_platform_admin());
drop policy if exists admin_template_version_access on public.template_versions;
create policy admin_template_version_access on public.template_versions for all to authenticated
using(core.is_platform_admin()) with check(core.is_platform_admin() and created_by=auth.uid());

drop policy if exists admin_typology_pack_access on feasibility.typology_packs;
create policy admin_typology_pack_access on feasibility.typology_packs for all to authenticated
using(core.is_platform_admin()) with check(core.is_platform_admin());

insert into public.quality_gate_definitions(code,name,stage,description,blocking,criticalities,evidence_required,enabled)
values
 ('TYPECHECK','TypeScript type safety','pull_request','All workspaces must pass static type checking.',true,'["C0","C1","C2","C3","C4"]','["ci:typecheck"]',true),
 ('TESTS','Automated test suite','pull_request','Unit, integration and contract tests must pass.',true,'["C0","C1","C2","C3","C4"]','["ci:test"]',true),
 ('SECURITY','Security assurance','pull_request','Dependency, secret and database security checks must have no unresolved critical finding.',true,'["C1","C2","C3","C4"]','["ci:security","supabase:advisor"]',true),
 ('PROD_BUILD','Production build','preview','The production application must compile into a deployable immutable artifact.',true,'["C0","C1","C2","C3","C4"]','["vercel:build"]',true),
 ('RUNTIME_SMOKE','Production runtime smoke','production','Health, readiness, authentication and core workspace routes must pass after deployment.',true,'["C0","C1","C2","C3","C4"]','["vercel:deployment","runtime:smoke"]',true)
on conflict(code) do update set name=excluded.name,stage=excluded.stage,description=excluded.description,
blocking=excluded.blocking,criticalities=excluded.criticalities,evidence_required=excluded.evidence_required,
enabled=excluded.enabled,updated_at=now();

insert into feasibility.typology_packs(code,name,typology,version,programme_categories,planning_principles,operational_principles,engineering_considerations,sustainability_considerations,commercial_drivers,benchmark_sources,questionnaire,state)
values
 ('TYP-HOTEL','Hotel / Resort','hospitality',1,'["keys","food_and_beverage","events","back_of_house"]','["guest_service_separation","arrival_sequence","key_efficiency"]','["service_flow","housekeeping","banqueting"]','["vertical_transport","mep_intensity","life_safety"]','["water","energy","heat"]','["adr","occupancy","revenue_per_available_room"]','[]','[]','draft'),
 ('TYP-MIXED','Mixed Use','mixed_use',1,'["retail","office","hospitality","parking"]','["separate_arrivals","shared_infrastructure"]','["loading_and_service","vertical_zoning"]','["fire_strategy","mep_zoning"]','["mobility","energy"]','["tenant_mix","phasing"]','[]','[]','draft'),
 ('TYP-RESI','Residential','residential',1,'["dwelling_units","amenities","parking","services"]','["privacy_gradient","daylight","cross_ventilation"]','["resident_service_separation","maintenance_access"]','["structural_grid","mep_shafts","life_safety"]','["water","energy","thermal_comfort"]','["saleable_efficiency","unit_mix"]','[]','[]','draft'),
 ('TYP-HOSP','Hospital','healthcare',1,'["clinical","diagnostic","inpatient","support"]','["clean_dirty_separation","patient_staff_public_flows"]','["infection_control","critical_care_continuity"]','["medical_gases","resilience","life_safety"]','["energy","water","waste"]','["bed_mix","equipment_intensity"]','[]','[]','draft'),
 ('TYP-RETAIL','Retail / Mall','retail',1,'["anchor","vanilla","cinema","food_and_beverage","parking"]','["customer_loop","visibility","egress"]','["loading","waste","tenant_access"]','["long_span","mep_diversity","fire_strategy"]','["energy","mobility","heat"]','["tenant_mix","trading_density"]','[]','[]','draft')
on conflict(code) do nothing;

commit;
