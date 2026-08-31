begin;

create table if not exists public.drawing_reference_packs(
 id uuid primary key default gen_random_uuid(), organisation_id uuid references core.organisations(id) on delete cascade,
 project_id uuid references project.projects(id) on delete cascade, name text not null, typology text not null,
 source_title text not null, source_reference text not null, source_checksum text not null check(source_checksum ~ '^[0-9a-f]{64}$'),
 status text not null default 'draft' check(status in('draft','review','active_reference','retired')),
 applicability jsonb not null default '{}'::jsonb, extracted_features jsonb not null default '{}'::jsonb,
 design_principles jsonb not null default '[]'::jsonb check(jsonb_typeof(design_principles)='array'), limitations jsonb not null default '[]'::jsonb,
 created_by uuid references auth.users(id) on delete set null, approved_by uuid references auth.users(id) on delete set null,
 approved_at timestamptz, created_at timestamptz not null default now(), updated_at timestamptz not null default now(), unique(source_checksum)
);
alter table public.drawing_reference_packs enable row level security;
grant select,insert,update on public.drawing_reference_packs to authenticated;
create policy drawing_reference_admin_read on public.drawing_reference_packs for select to authenticated using(core.is_platform_admin());
create policy drawing_reference_admin_write on public.drawing_reference_packs for all to authenticated using(core.is_platform_admin()) with check(core.is_platform_admin());

insert into public.drawing_reference_packs(organisation_id,name,typology,source_title,source_reference,source_checksum,status,applicability,extracted_features,design_principles,limitations)
select o.id,'Spring Valley Twin-Plot Residential Grammar','residential','CRN553371 - AMIT - Typical Floor Plan - 09.06.2025','controlled-upload://CRN553371-AMIT-A102',
 '7b244c4b092295cd74c5ecc3da052857c317148a1de65bee749908a3048d9049','active_reference',
 '{"plot_configuration":"two_adjacent_equal_plots","plot_numbers":[60,61],"frontage_each":"20 ft 2 in","depth":"51 ft 3 in","floor":"typical","drawing_number":"A102"}'::jsonb,
 '{"units_per_floor":2,"relationship":"mirrored_about_central_party_line","shared_core":{"stair":"central dog-legged stair","lift":{"area_sq_ft":25,"clear_size":"5 ft x 5 ft"}},"per_unit":{"bedrooms":[{"area_sq_ft":122,"size":"9 ft 5 in x 11 ft 5 in"},{"area_sq_ft":120,"size":"10 ft x 12 ft"}],"drawing_room":{"area_sq_ft":111,"size":"9 ft x 12 ft 4 in"},"family_room":{"area_sq_ft":227,"size":"13 ft 4 in x 15 ft 8 in"},"kitchen":{"area_sq_ft":53,"size":"5 ft 8 in x 10 ft 10 in"},"toilets":[{"area_sq_ft":30,"size":"6 ft 8 in x 4 ft 6 in"},{"area_sq_ft":33,"size":"5 ft 8 in x 5 ft 9 in"}],"balconies":["3 ft rear balcony","2 ft 6 in front balcony"],"service_elements":["shaft","shoe rack","mandir"]},"construction_notes":{"floor_to_floor":"10 ft","steps":18,"stair_tread":"10 in","riser":"6 in","external_wall":"6 in","internal_wall":"4 in"}}'::jsonb,
 '["Preserve both legal plots and the central division even when studying a combined building.","Use a symmetrical two-unit arrangement around a shared central stair and lift.","Maintain a clear public-to-private sequence: front drawing room, central family room, rear bedroom zone.","Place kitchens, toilets and shafts to form rational wet-service clusters without compromising room access.","Show furniture, door swings, room names, areas, principal dimensions, balconies, core and title-block provenance in every review drawing.","Never invent survey, setback, structural or statutory facts; flag them as unresolved evidence."]'::jsonb,
 '["Reference drawing is not a survey or title document.","Its dimensions and planning decisions require project-specific verification.","It must not be copied blindly or represented as construction-ready output."]'::jsonb
from core.organisations o where o.name='Concept Spaces'
on conflict(source_checksum) do update set extracted_features=excluded.extracted_features,design_principles=excluded.design_principles,status='active_reference',updated_at=now();

create or replace function public.generate_preliminary_layout_set(target_project_id uuid)
returns uuid language plpgsql security definer set search_path='public','project','aec','auth','pg_temp' as $$
declare option_id uuid; reference_row public.drawing_reference_packs%rowtype;
begin
 if auth.uid() is null or not project.can_access_project(target_project_id) then raise exception 'project_access_required'; end if;
 insert into aec.design_branches(project_id,code,title,branch_reason,status,created_by)
 values(target_project_id,'main','Main','Architecture bridge for governed reference-grounded generation','active',auth.uid()) on conflict(project_id,code) do nothing;
 option_id:=public.generate_preliminary_layout_set_core(target_project_id);
 select r.* into reference_row from public.drawing_reference_packs r join project.projects p on p.id=target_project_id
 where r.status='active_reference' and r.typology=p.typology and (r.organisation_id is null or r.organisation_id=p.organisation_id)
 order by r.approved_at desc nulls last,r.created_at desc limit 1;
 if found then
  update aec.design_options set name='Reference-Grounded Concept Layout A - Shared Core',generated_by='hybrid',
   metrics=metrics||jsonb_build_object('generator','reference-grounded-layout@2.0.0','reference_pack',jsonb_build_object('id',reference_row.id,'name',reference_row.name,'source_checksum',reference_row.source_checksum,'features',reference_row.extracted_features,'principles',reference_row.design_principles)),
   assumptions=assumptions||jsonb_build_array('Spatial organisation is guided by approved reference pack '||reference_row.name||'; it is not copied or treated as project authority.')
  where id=option_id;
 end if;
 return option_id;
end;$$;
revoke all on function public.generate_preliminary_layout_set(uuid) from public,anon;
grant execute on function public.generate_preliminary_layout_set(uuid) to authenticated;

commit;
