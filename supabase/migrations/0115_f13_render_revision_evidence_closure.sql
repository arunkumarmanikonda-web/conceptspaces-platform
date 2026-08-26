begin;

create table if not exists aec.interior_render_records(
 id uuid primary key default gen_random_uuid(),
 project_id uuid not null references project.projects(id) on delete cascade,
 room_package_id uuid not null references aec.interior_room_packages(id) on delete restrict,
 render_ref text not null,
 design_revision_ref text not null,
 model_revision_hash text not null,
 dna_id uuid not null references aec.interior_dna(id) on delete restrict,
 dna_hash text not null,
 renderer text not null,
 renderer_version text not null,
 source_refs jsonb not null default '[]'::jsonb,
 material_selection_refs jsonb not null default '[]'::jsonb,
 geometry_source_ref text,
 conceptual boolean not null default true,
 metadata_hash text not null,
 created_by uuid references auth.users(id) on delete set null,
 created_at timestamptz not null default now(),
 unique(project_id,render_ref)
);
alter table aec.interior_render_records enable row level security;
grant select,insert on aec.interior_render_records to authenticated;
create policy interior_render_read on aec.interior_render_records for select to authenticated using(project.can_access_project(project_id));
create policy interior_render_insert on aec.interior_render_records for insert to authenticated with check(project.can_manage_project(project_id) and created_by=auth.uid() and current_setting('conceptspaces.design_phase',true)='interiors_render');

create or replace function public.register_interior_render(target_project_id uuid,input_payload jsonb)
returns uuid language plpgsql security invoker set search_path='public','aec','project','audit','extensions','auth','pg_temp' as $$
declare room aec.interior_room_packages%rowtype;dna aec.interior_dna%rowtype;r aec.interior_render_records%rowtype;room_id uuid:=nullif(input_payload->>'room_package_id','')::uuid;conceptual_value boolean:=coalesce((input_payload->>'conceptual')::boolean,true);h text;
begin
 if auth.uid() is null or not project.can_manage_project(target_project_id) or not project.current_user_has_project_role(target_project_id,array['interior_designer','lead_architect','project_manager']) then raise exception 'interior_render_authority_required';end if;
 select * into room from aec.interior_room_packages where id=room_id and project_id=target_project_id and status in ('approved','issued');if not found then raise exception 'approved_room_package_required';end if;
 select * into dna from aec.interior_dna where id=room.dna_id and project_id=target_project_id and status='approved';if not found then raise exception 'approved_interior_dna_required';end if;
 if nullif(btrim(input_payload->>'render_ref'),'') is null or nullif(btrim(input_payload->>'renderer'),'') is null or nullif(btrim(input_payload->>'renderer_version'),'') is null then raise exception 'render_reference_engine_version_required';end if;
 if jsonb_typeof(coalesce(input_payload->'source_refs','[]'::jsonb))<>'array' or jsonb_typeof(coalesce(input_payload->'material_selection_refs','[]'::jsonb))<>'array' then raise exception 'render_sources_must_be_arrays';end if;
 if not conceptual_value and (nullif(btrim(input_payload->>'geometry_source_ref'),'') is null or jsonb_array_length(coalesce(input_payload->'material_selection_refs','[]'::jsonb))=0) then raise exception 'NON_CONCEPTUAL_RENDER_REQUIRES_GEOMETRY_AND_MATERIAL_SOURCES';end if;
 if lower(room.model_revision_hash) !~ '^[0-9a-f]{64}$' then raise exception 'room_model_revision_hash_invalid';end if;
 h:=encode(extensions.digest(jsonb_build_object('project_id',target_project_id,'room_package_id',room.id,'room_package_hash',room.package_hash,'render_ref',btrim(input_payload->>'render_ref'),'design_revision_ref',room.design_revision_ref,'model_revision_hash',room.model_revision_hash,'dna_id',dna.id,'dna_hash',dna.dna_hash,'renderer',btrim(input_payload->>'renderer'),'renderer_version',btrim(input_payload->>'renderer_version'),'source_refs',coalesce(input_payload->'source_refs','[]'::jsonb),'material_selection_refs',coalesce(input_payload->'material_selection_refs','[]'::jsonb),'geometry_source_ref',nullif(btrim(input_payload->>'geometry_source_ref'),''),'conceptual',conceptual_value)::text,'sha256'),'hex');
 perform set_config('conceptspaces.design_phase','interiors_render',true);
 insert into aec.interior_render_records(project_id,room_package_id,render_ref,design_revision_ref,model_revision_hash,dna_id,dna_hash,renderer,renderer_version,source_refs,material_selection_refs,geometry_source_ref,conceptual,metadata_hash,created_by)
 values(target_project_id,room.id,btrim(input_payload->>'render_ref'),room.design_revision_ref,room.model_revision_hash,dna.id,dna.dna_hash,btrim(input_payload->>'renderer'),btrim(input_payload->>'renderer_version'),coalesce(input_payload->'source_refs','[]'::jsonb),coalesce(input_payload->'material_selection_refs','[]'::jsonb),nullif(btrim(input_payload->>'geometry_source_ref'),''),conceptual_value,h,auth.uid()) returning * into r;
 perform audit.append_event((select organisation_id from project.projects where id=target_project_id),target_project_id,'interior.render.registered','interior_render',r.id,null,to_jsonb(r),h,gen_random_uuid());return r.id;
end;$$;
revoke all on function public.register_interior_render(uuid,jsonb) from public,anon;grant execute on function public.register_interior_render(uuid,jsonb) to authenticated;

create or replace function public.list_interiors_workspace(target_project_id uuid)
returns jsonb language plpgsql stable security invoker set search_path='public','aec','project','auth','pg_temp' as $$
begin
 if auth.uid() is null or not project.can_access_project(target_project_id) then raise exception 'project_access_required';end if;
 return jsonb_build_object(
 'dna',coalesce((select jsonb_agg(to_jsonb(d) order by d.version desc) from aec.interior_dna d where d.project_id=target_project_id),'[]'::jsonb),
 'rooms',coalesce((select jsonb_agg(to_jsonb(r) order by r.space_ref,r.version desc) from aec.interior_room_packages r where r.project_id=target_project_id),'[]'::jsonb),
 'materials',coalesce((select jsonb_agg(to_jsonb(m) order by m.created_at desc) from aec.interior_material_selections m where m.project_id=target_project_id),'[]'::jsonb),
 'shop_drawings',coalesce((select jsonb_agg(to_jsonb(s) order by s.component_ref,s.version desc) from aec.interior_shop_drawings s where s.project_id=target_project_id),'[]'::jsonb),
 'renders',coalesce((select jsonb_agg(to_jsonb(r) order by r.created_at desc) from aec.interior_render_records r where r.project_id=target_project_id),'[]'::jsonb));
end;$$;
revoke all on function public.list_interiors_workspace(uuid) from public,anon;grant execute on function public.list_interiors_workspace(uuid) to authenticated;

commit;
