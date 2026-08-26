begin;

create or replace function aec.guard_interior_dna_snapshot()
returns trigger language plpgsql security definer set search_path='aec','pg_temp' as $$
begin
 if old.status='approved' then
  if not (new.status='superseded' and current_setting('conceptspaces.design_phase',true)='interiors') then raise exception 'approved_interior_dna_immutable'; end if;
  if (to_jsonb(new)-'status'-'updated_at') is distinct from (to_jsonb(old)-'status'-'updated_at') then raise exception 'approved_interior_dna_content_immutable'; end if;
 end if;
 return new;
end;$$;
revoke all on function aec.guard_interior_dna_snapshot() from public,anon,authenticated;
drop trigger if exists trg_interior_dna_snapshot on aec.interior_dna;
create trigger trg_interior_dna_snapshot before update on aec.interior_dna for each row execute function aec.guard_interior_dna_snapshot();

create or replace function aec.guard_interior_room_snapshot()
returns trigger language plpgsql security definer set search_path='aec','pg_temp' as $$
begin
 if old.status='issued' then raise exception 'issued_interior_room_package_immutable'; end if;
 if old.status='approved' then
  if not (new.status='issued' and current_setting('conceptspaces.design_phase',true)='interiors') then raise exception 'approved_interior_room_package_immutable'; end if;
  if (to_jsonb(new)-'status'-'issued_by'-'issued_at'-'updated_at') is distinct from (to_jsonb(old)-'status'-'issued_by'-'issued_at'-'updated_at') then raise exception 'approved_interior_room_content_immutable'; end if;
 end if;
 return new;
end;$$;
revoke all on function aec.guard_interior_room_snapshot() from public,anon,authenticated;
drop trigger if exists trg_interior_room_snapshot on aec.interior_room_packages;
create trigger trg_interior_room_snapshot before update on aec.interior_room_packages for each row execute function aec.guard_interior_room_snapshot();

create or replace function aec.guard_material_selection_snapshot()
returns trigger language plpgsql security definer set search_path='aec','pg_temp' as $$
begin
 if old.status in ('approved','locked') then
  if not (new.status='superseded' and current_setting('conceptspaces.design_phase',true)='interiors') then raise exception 'approved_material_selection_immutable'; end if;
  if (to_jsonb(new)-'status'-'updated_at') is distinct from (to_jsonb(old)-'status'-'updated_at') then raise exception 'approved_material_selection_content_immutable'; end if;
 end if;
 return new;
end;$$;
revoke all on function aec.guard_material_selection_snapshot() from public,anon,authenticated;
drop trigger if exists trg_material_selection_snapshot on aec.interior_material_selections;
create trigger trg_material_selection_snapshot before update on aec.interior_material_selections for each row execute function aec.guard_material_selection_snapshot();

create or replace function aec.guard_shop_drawing_snapshot()
returns trigger language plpgsql security definer set search_path='aec','pg_temp' as $$
begin
 if old.status='issued' then raise exception 'issued_shop_drawing_immutable'; end if;
 if old.status='approved' then
  if not (new.status='issued' and current_setting('conceptspaces.design_phase',true)='interiors') then raise exception 'approved_shop_drawing_immutable'; end if;
  if (to_jsonb(new)-'status'-'issued_by'-'issued_at'-'updated_at') is distinct from (to_jsonb(old)-'status'-'issued_by'-'issued_at'-'updated_at') then raise exception 'approved_shop_drawing_content_immutable'; end if;
 end if;
 return new;
end;$$;
revoke all on function aec.guard_shop_drawing_snapshot() from public,anon,authenticated;
drop trigger if exists trg_shop_drawing_snapshot on aec.interior_shop_drawings;
create trigger trg_shop_drawing_snapshot before update on aec.interior_shop_drawings for each row execute function aec.guard_shop_drawing_snapshot();

create or replace function public.create_interior_dna(target_project_id uuid,input_payload jsonb)
returns uuid language plpgsql security invoker
set search_path='public','aec','project','audit','extensions','auth','pg_temp' as $$
declare dna aec.interior_dna%rowtype; version_value integer; hash_value text; confidence_value text:=upper(coalesce(nullif(btrim(input_payload->>'confidence'),''),'C'));
begin
 if auth.uid() is null or not project.can_manage_project(target_project_id) or not project.current_user_has_project_role(target_project_id,array['interior_designer','lead_architect','project_manager']) then raise exception 'interior_dna_authority_required'; end if;
 if nullif(btrim(input_payload->>'narrative'),'') is null or jsonb_typeof(coalesce(input_payload->'source_refs','[]'::jsonb))<>'array' or jsonb_array_length(coalesce(input_payload->'source_refs','[]'::jsonb))=0 then raise exception 'interior_dna_brief_source_required'; end if;
 if confidence_value not in ('A','B','C','D') then raise exception 'interior_dna_confidence_invalid'; end if;
 select coalesce(max(version),0)+1 into version_value from aec.interior_dna where project_id=target_project_id;
 hash_value:=encode(extensions.digest(jsonb_build_object('project_id',target_project_id,'version',version_value,'narrative',btrim(input_payload->>'narrative'),'palette',coalesce(input_payload->'palette','[]'::jsonb),'material_rules',coalesce(input_payload->'material_rules','[]'::jsonb),'lighting_rules',coalesce(input_payload->'lighting_rules','[]'::jsonb),'joinery_rules',coalesce(input_payload->'joinery_rules','[]'::jsonb),'ffe_rules',coalesce(input_payload->'ffe_rules','[]'::jsonb),'prohibited_elements',coalesce(input_payload->'prohibited_elements','[]'::jsonb),'source_refs',input_payload->'source_refs','confidence',confidence_value)::text,'sha256'),'hex');
 perform set_config('conceptspaces.design_phase','interiors',true);
 insert into aec.interior_dna(project_id,version,narrative,palette,material_rules,lighting_rules,joinery_rules,ffe_rules,prohibited_elements,source_refs,confidence,status,dna_hash,created_by)
 values(target_project_id,version_value,btrim(input_payload->>'narrative'),coalesce(input_payload->'palette','[]'::jsonb),coalesce(input_payload->'material_rules','[]'::jsonb),coalesce(input_payload->'lighting_rules','[]'::jsonb),coalesce(input_payload->'joinery_rules','[]'::jsonb),coalesce(input_payload->'ffe_rules','[]'::jsonb),coalesce(input_payload->'prohibited_elements','[]'::jsonb),input_payload->'source_refs',confidence_value,'draft',hash_value,auth.uid()) returning * into dna;
 perform audit.append_event((select organisation_id from project.projects where id=target_project_id),target_project_id,'interior.dna.created','interior_dna',dna.id,null,to_jsonb(dna),hash_value,gen_random_uuid()); return dna.id;
end;$$;
revoke all on function public.create_interior_dna(uuid,jsonb) from public,anon; grant execute on function public.create_interior_dna(uuid,jsonb) to authenticated;

create or replace function public.transition_interior_dna(target_dna_id uuid,target_status text,target_reason text)
returns text language plpgsql security invoker
set search_path='public','aec','project','audit','auth','pg_temp' as $$
declare dna aec.interior_dna%rowtype; before_state jsonb; value text:=lower(btrim(target_status));
begin
 select * into dna from aec.interior_dna where id=target_dna_id for update;
 if not found or auth.uid() is null or not project.can_manage_project(dna.project_id) then raise exception 'interior_dna_authority_required'; end if;
 if value not in ('review','approved','rejected') or nullif(btrim(target_reason),'') is null then raise exception 'interior_dna_transition_invalid'; end if;
 if dna.status='draft' and value not in ('review','rejected') then raise exception 'interior_dna_requires_review'; end if;
 if dna.status='review' and value not in ('approved','rejected') then raise exception 'interior_dna_review_transition_invalid'; end if;
 if value='approved' then
  if not project.current_user_has_project_role(dna.project_id,array['lead_architect','client_approver','interior_designer']) then raise exception 'interior_dna_approval_role_required'; end if;
  if dna.created_by=auth.uid() then raise exception 'interior_dna_independent_approval_required'; end if;
 end if;
 before_state:=to_jsonb(dna); perform set_config('conceptspaces.design_phase','interiors',true);
 if value='approved' then update aec.interior_dna set status='superseded',updated_at=now() where project_id=dna.project_id and status='approved'; end if;
 update aec.interior_dna set status=value,approved_by=case when value='approved' then auth.uid() else approved_by end,approved_at=case when value='approved' then now() else approved_at end,updated_at=now() where id=dna.id returning * into dna;
 perform audit.append_event((select organisation_id from project.projects where id=dna.project_id),dna.project_id,'interior.dna.'||value,'interior_dna',dna.id,before_state,to_jsonb(dna),target_reason,gen_random_uuid()); return dna.status;
end;$$;
revoke all on function public.transition_interior_dna(uuid,text,text) from public,anon; grant execute on function public.transition_interior_dna(uuid,text,text) to authenticated;

create or replace function public.create_interior_room_package(target_project_id uuid,input_payload jsonb)
returns uuid language plpgsql security invoker
set search_path='public','aec','project','audit','extensions','auth','pg_temp' as $$
declare dna aec.interior_dna%rowtype; package aec.interior_room_packages%rowtype; version_value integer; hash_value text; dna_id_value uuid:=nullif(input_payload->>'dna_id','')::uuid;
begin
 if auth.uid() is null or not project.can_manage_project(target_project_id) or not project.current_user_has_project_role(target_project_id,array['interior_designer','lead_architect','project_manager']) then raise exception 'interior_room_authority_required'; end if;
 select * into dna from aec.interior_dna where id=dna_id_value and project_id=target_project_id and status='approved'; if not found then raise exception 'approved_interior_dna_required'; end if;
 if nullif(btrim(input_payload->>'space_ref'),'') is null or nullif(btrim(input_payload->>'design_revision_ref'),'') is null or length(coalesce(input_payload->>'model_revision_hash',''))<>64 then raise exception 'interior_room_revision_identity_required'; end if;
 select coalesce(max(version),0)+1 into version_value from aec.interior_room_packages where project_id=target_project_id and space_ref=btrim(input_payload->>'space_ref');
 hash_value:=encode(extensions.digest(jsonb_build_object('project_id',target_project_id,'space_ref',btrim(input_payload->>'space_ref'),'version',version_value,'dna_hash',dna.dna_hash,'design_revision_ref',btrim(input_payload->>'design_revision_ref'),'model_revision_hash',input_payload->>'model_revision_hash','layout_refs',coalesce(input_payload->'layout_refs','[]'::jsonb),'elevation_refs',coalesce(input_payload->'elevation_refs','[]'::jsonb),'finishes',coalesce(input_payload->'finishes','[]'::jsonb),'lighting',coalesce(input_payload->'lighting','[]'::jsonb),'furniture',coalesce(input_payload->'furniture','[]'::jsonb),'visualisation_refs',coalesce(input_payload->'visualisation_refs','[]'::jsonb),'drawing_refs',coalesce(input_payload->'drawing_refs','[]'::jsonb),'boq_refs',coalesce(input_payload->'boq_refs','[]'::jsonb),'coordination_checks',coalesce(input_payload->'coordination_checks','[]'::jsonb))::text,'sha256'),'hex');
 perform set_config('conceptspaces.design_phase','interiors',true);
 insert into aec.interior_room_packages(project_id,dna_id,space_ref,version,design_revision_ref,model_revision_hash,layout_refs,elevation_refs,finishes,lighting,furniture,visualisation_refs,drawing_refs,boq_refs,coordination_checks,status,package_hash,created_by)
 values(target_project_id,dna.id,btrim(input_payload->>'space_ref'),version_value,btrim(input_payload->>'design_revision_ref'),input_payload->>'model_revision_hash',coalesce(input_payload->'layout_refs','[]'::jsonb),coalesce(input_payload->'elevation_refs','[]'::jsonb),coalesce(input_payload->'finishes','[]'::jsonb),coalesce(input_payload->'lighting','[]'::jsonb),coalesce(input_payload->'furniture','[]'::jsonb),coalesce(input_payload->'visualisation_refs','[]'::jsonb),coalesce(input_payload->'drawing_refs','[]'::jsonb),coalesce(input_payload->'boq_refs','[]'::jsonb),coalesce(input_payload->'coordination_checks','[]'::jsonb),'draft',hash_value,auth.uid()) returning * into package;
 perform audit.append_event((select organisation_id from project.projects where id=target_project_id),target_project_id,'interior.room_package.created','interior_room_package',package.id,null,to_jsonb(package),hash_value,gen_random_uuid()); return package.id;
end;$$;
revoke all on function public.create_interior_room_package(uuid,jsonb) from public,anon; grant execute on function public.create_interior_room_package(uuid,jsonb) to authenticated;

create or replace function public.transition_interior_room_package(target_package_id uuid,target_status text,target_reason text)
returns text language plpgsql security invoker
set search_path='public','aec','project','audit','auth','pg_temp' as $$
declare package aec.interior_room_packages%rowtype; before_state jsonb; value text:=lower(btrim(target_status)); critical_open integer;
begin
 select * into package from aec.interior_room_packages where id=target_package_id for update;
 if not found or auth.uid() is null or not project.can_manage_project(package.project_id) then raise exception 'interior_room_authority_required'; end if;
 if value not in ('coordinating','for_review','approved','issued','rejected') or nullif(btrim(target_reason),'') is null then raise exception 'interior_room_transition_invalid'; end if;
 if package.status='draft' and value not in ('coordinating','for_review','rejected') then raise exception 'interior_room_transition_invalid'; end if;
 if package.status='coordinating' and value not in ('for_review','rejected') then raise exception 'interior_room_transition_invalid'; end if;
 if package.status='for_review' and value not in ('approved','rejected') then raise exception 'interior_room_transition_invalid'; end if;
 if package.status='approved' and value<>'issued' then raise exception 'interior_room_transition_invalid'; end if;
 select count(*) into critical_open from jsonb_array_elements(coalesce(package.coordination_checks,'[]'::jsonb)) x where lower(coalesce(x->>'severity','')) in ('critical','c3','c4') and lower(coalesce(x->>'status','open')) not in ('resolved','passed','closed','accepted');
 if value in ('approved','issued') and critical_open>0 then raise exception 'interior_critical_coordination_checks_open'; end if;
 if value='approved' then if package.created_by=auth.uid() then raise exception 'interior_room_independent_approval_required'; end if; if not project.current_user_has_project_role(package.project_id,array['interior_designer','lead_architect','client_approver']) then raise exception 'interior_room_approval_role_required'; end if; end if;
 if value='issued' and jsonb_array_length(package.drawing_refs)=0 then raise exception 'interior_room_drawings_required_for_issue'; end if;
 before_state:=to_jsonb(package); perform set_config('conceptspaces.design_phase','interiors',true);
 update aec.interior_room_packages set status=value,approved_by=case when value='approved' then auth.uid() else approved_by end,approved_at=case when value='approved' then now() else approved_at end,issued_by=case when value='issued' then auth.uid() else issued_by end,issued_at=case when value='issued' then now() else issued_at end,updated_at=now() where id=package.id returning * into package;
 perform audit.append_event((select organisation_id from project.projects where id=package.project_id),package.project_id,'interior.room_package.'||value,'interior_room_package',package.id,before_state,to_jsonb(package),target_reason,gen_random_uuid()); return package.status;
end;$$;
revoke all on function public.transition_interior_room_package(uuid,text,text) from public,anon; grant execute on function public.transition_interior_room_package(uuid,text,text) to authenticated;

create or replace function public.create_interior_material_selection(target_project_id uuid,input_payload jsonb)
returns uuid language plpgsql security invoker
set search_path='public','aec','project','audit','extensions','auth','pg_temp' as $$
declare dna aec.interior_dna%rowtype; selection aec.interior_material_selections%rowtype; base aec.interior_material_selections%rowtype; hash_value text; dna_id_value uuid:=nullif(input_payload->>'dna_id','')::uuid; base_id_value uuid:=nullif(input_payload->>'base_selection_id','')::uuid;
begin
 if auth.uid() is null or not project.can_manage_project(target_project_id) or not project.current_user_has_project_role(target_project_id,array['interior_designer','lead_architect','qs_cost_manager','project_manager']) then raise exception 'interior_material_authority_required'; end if;
 select * into dna from aec.interior_dna where id=dna_id_value and project_id=target_project_id and status='approved'; if not found then raise exception 'approved_interior_dna_required'; end if;
 if nullif(btrim(input_payload->>'material_code'),'') is null or nullif(btrim(input_payload->>'source_ref'),'') is null or jsonb_typeof(coalesce(input_payload->'specification','{}'::jsonb))<>'object' or coalesce(input_payload->'specification','{}'::jsonb)='{}'::jsonb then raise exception 'material_source_specification_required'; end if;
 if base_id_value is not null then
  select * into base from aec.interior_material_selections where id=base_id_value and project_id=target_project_id and status in ('approved','locked'); if not found then raise exception 'base_material_selection_invalid'; end if;
  if jsonb_typeof(coalesce(input_payload->'substitution_delta','{}'::jsonb))<>'object' or not(coalesce(input_payload->'substitution_delta','{}'::jsonb) ?& array['cost','performance','lead_time']) then raise exception 'material_substitution_delta_required'; end if;
  if coalesce((input_payload#>>'{substitution_delta,performance,mandatory_degradation}')::boolean,false) and nullif(btrim(input_payload->>'approved_deviation_ref'),'') is null then raise exception 'material_performance_degradation_requires_deviation'; end if;
 end if;
 hash_value:=encode(extensions.digest(jsonb_build_object('project_id',target_project_id,'dna_hash',dna.dna_hash,'material_code',upper(btrim(input_payload->>'material_code')),'product_ref',nullif(btrim(input_payload->>'product_ref'),''),'source_ref',btrim(input_payload->>'source_ref'),'specification',input_payload->'specification','cost_amount',nullif(input_payload->>'cost_amount','')::numeric,'currency',coalesce(nullif(upper(btrim(input_payload->>'currency')),''),'INR'),'lead_time_days',nullif(input_payload->>'lead_time_days','')::numeric,'performance',coalesce(input_payload->'performance','{}'::jsonb),'sustainability',coalesce(input_payload->'sustainability','{}'::jsonb),'base_selection_id',base_id_value,'substitution_delta',coalesce(input_payload->'substitution_delta','{}'::jsonb),'approved_deviation_ref',nullif(btrim(input_payload->>'approved_deviation_ref'),''))::text,'sha256'),'hex');
 perform set_config('conceptspaces.design_phase','interiors',true);
 insert into aec.interior_material_selections(project_id,dna_id,room_package_id,base_selection_id,material_code,product_ref,source_ref,specification,cost_amount,currency,lead_time_days,performance,sustainability,substitution_delta,approved_deviation_ref,status,selection_hash,created_by)
 values(target_project_id,dna.id,nullif(input_payload->>'room_package_id','')::uuid,base_id_value,upper(btrim(input_payload->>'material_code')),nullif(btrim(input_payload->>'product_ref'),''),btrim(input_payload->>'source_ref'),input_payload->'specification',nullif(input_payload->>'cost_amount','')::numeric,coalesce(nullif(upper(btrim(input_payload->>'currency')),''),'INR'),nullif(input_payload->>'lead_time_days','')::numeric,coalesce(input_payload->'performance','{}'::jsonb),coalesce(input_payload->'sustainability','{}'::jsonb),coalesce(input_payload->'substitution_delta','{}'::jsonb),nullif(btrim(input_payload->>'approved_deviation_ref'),''),'proposed',hash_value,auth.uid()) returning * into selection;
 perform audit.append_event((select organisation_id from project.projects where id=target_project_id),target_project_id,'interior.material.proposed','interior_material_selection',selection.id,null,to_jsonb(selection),hash_value,gen_random_uuid()); return selection.id;
end;$$;
revoke all on function public.create_interior_material_selection(uuid,jsonb) from public,anon; grant execute on function public.create_interior_material_selection(uuid,jsonb) to authenticated;

create or replace function public.decide_interior_material_selection(target_selection_id uuid,target_decision text,target_reason text)
returns text language plpgsql security invoker
set search_path='public','aec','project','audit','auth','pg_temp' as $$
declare selection aec.interior_material_selections%rowtype; before_state jsonb; value text:=lower(btrim(target_decision));
begin
 select * into selection from aec.interior_material_selections where id=target_selection_id for update;
 if not found or auth.uid() is null or not project.can_manage_project(selection.project_id) or not project.current_user_has_project_role(selection.project_id,array['interior_designer','lead_architect','qs_cost_manager','client_approver']) then raise exception 'interior_material_decision_authority_required'; end if;
 if selection.status<>'proposed' or value not in ('approved','rejected','locked') or nullif(btrim(target_reason),'') is null then raise exception 'interior_material_decision_invalid'; end if;
 if value in ('approved','locked') and selection.created_by=auth.uid() then raise exception 'interior_material_independent_approval_required'; end if;
 before_state:=to_jsonb(selection); perform set_config('conceptspaces.design_phase','interiors',true);
 if value in ('approved','locked') and selection.base_selection_id is not null then update aec.interior_material_selections set status='superseded',updated_at=now() where id=selection.base_selection_id; end if;
 update aec.interior_material_selections set status=value,approved_by=case when value in ('approved','locked') then auth.uid() else approved_by end,approved_at=case when value in ('approved','locked') then now() else approved_at end,updated_at=now() where id=selection.id returning * into selection;
 perform audit.append_event((select organisation_id from project.projects where id=selection.project_id),selection.project_id,'interior.material.'||value,'interior_material_selection',selection.id,before_state,to_jsonb(selection),target_reason,gen_random_uuid()); return selection.status;
end;$$;
revoke all on function public.decide_interior_material_selection(uuid,text,text) from public,anon; grant execute on function public.decide_interior_material_selection(uuid,text,text) to authenticated;

create or replace function public.create_interior_shop_drawing(target_project_id uuid,input_payload jsonb)
returns uuid language plpgsql security invoker
set search_path='public','aec','project','audit','extensions','auth','pg_temp' as $$
declare room aec.interior_room_packages%rowtype; drawing aec.interior_shop_drawings%rowtype; version_value integer; hash_value text; room_id_value uuid:=nullif(input_payload->>'room_package_id','')::uuid;
begin
 if auth.uid() is null or not project.can_manage_project(target_project_id) or not project.current_user_has_project_role(target_project_id,array['interior_designer','lead_architect','project_manager']) then raise exception 'shop_drawing_authority_required'; end if;
 select * into room from aec.interior_room_packages where id=room_id_value and project_id=target_project_id and status in ('approved','issued'); if not found then raise exception 'approved_room_package_required'; end if;
 if nullif(btrim(input_payload->>'component_ref'),'') is null or nullif(btrim(input_payload->>'dimensional_source_ref'),'') is null or length(coalesce(input_payload->>'dimensional_source_hash',''))<>64 then raise exception 'shop_drawing_dimensional_source_required'; end if;
 if jsonb_typeof(coalesce(input_payload->'drawing_refs','[]'::jsonb))<>'array' or jsonb_array_length(coalesce(input_payload->'drawing_refs','[]'::jsonb))=0 then raise exception 'shop_drawing_refs_required'; end if;
 select coalesce(max(version),0)+1 into version_value from aec.interior_shop_drawings where project_id=target_project_id and component_ref=btrim(input_payload->>'component_ref');
 hash_value:=encode(extensions.digest(jsonb_build_object('project_id',target_project_id,'room_package_hash',room.package_hash,'component_ref',btrim(input_payload->>'component_ref'),'version',version_value,'dimensional_source_ref',btrim(input_payload->>'dimensional_source_ref'),'dimensional_source_hash',input_payload->>'dimensional_source_hash','drawing_refs',input_payload->'drawing_refs','detail_refs',coalesce(input_payload->'detail_refs','[]'::jsonb),'hardware_refs',coalesce(input_payload->'hardware_refs','[]'::jsonb),'tolerances',coalesce(input_payload->'tolerances','{}'::jsonb),'boq_refs',coalesce(input_payload->'boq_refs','[]'::jsonb),'coordination_checks',coalesce(input_payload->'coordination_checks','[]'::jsonb))::text,'sha256'),'hex');
 perform set_config('conceptspaces.design_phase','interiors',true);
 insert into aec.interior_shop_drawings(project_id,room_package_id,component_ref,version,dimensional_source_ref,dimensional_source_hash,drawing_refs,detail_refs,hardware_refs,tolerances,boq_refs,coordination_checks,status,drawing_hash,created_by)
 values(target_project_id,room.id,btrim(input_payload->>'component_ref'),version_value,btrim(input_payload->>'dimensional_source_ref'),input_payload->>'dimensional_source_hash',input_payload->'drawing_refs',coalesce(input_payload->'detail_refs','[]'::jsonb),coalesce(input_payload->'hardware_refs','[]'::jsonb),coalesce(input_payload->'tolerances','{}'::jsonb),coalesce(input_payload->'boq_refs','[]'::jsonb),coalesce(input_payload->'coordination_checks','[]'::jsonb),'draft',hash_value,auth.uid()) returning * into drawing;
 perform audit.append_event((select organisation_id from project.projects where id=target_project_id),target_project_id,'interior.shop_drawing.created','interior_shop_drawing',drawing.id,null,to_jsonb(drawing),hash_value,gen_random_uuid()); return drawing.id;
end;$$;
revoke all on function public.create_interior_shop_drawing(uuid,jsonb) from public,anon; grant execute on function public.create_interior_shop_drawing(uuid,jsonb) to authenticated;

create or replace function public.transition_interior_shop_drawing(target_drawing_id uuid,target_status text,target_reason text)
returns text language plpgsql security invoker
set search_path='public','aec','project','audit','auth','pg_temp' as $$
declare drawing aec.interior_shop_drawings%rowtype; before_state jsonb; value text:=lower(btrim(target_status)); critical_open integer;
begin
 select * into drawing from aec.interior_shop_drawings where id=target_drawing_id for update;
 if not found or auth.uid() is null or not project.can_manage_project(drawing.project_id) then raise exception 'shop_drawing_authority_required'; end if;
 if value not in ('vendor_review','designer_review','approved','issued','rejected') or nullif(btrim(target_reason),'') is null then raise exception 'shop_drawing_transition_invalid'; end if;
 if drawing.status='draft' and value not in ('vendor_review','designer_review','rejected') then raise exception 'shop_drawing_transition_invalid'; end if;
 if drawing.status='vendor_review' and value not in ('designer_review','rejected') then raise exception 'shop_drawing_transition_invalid'; end if;
 if drawing.status='designer_review' and value not in ('approved','rejected') then raise exception 'shop_drawing_transition_invalid'; end if;
 if drawing.status='approved' and value<>'issued' then raise exception 'shop_drawing_transition_invalid'; end if;
 select count(*) into critical_open from jsonb_array_elements(coalesce(drawing.coordination_checks,'[]'::jsonb)) x where lower(coalesce(x->>'severity','')) in ('critical','c3','c4') and lower(coalesce(x->>'status','open')) not in ('resolved','passed','closed','accepted');
 if value in ('approved','issued') and critical_open>0 then raise exception 'shop_detail_uncoordinated'; end if;
 if value='approved' then if drawing.created_by=auth.uid() then raise exception 'shop_drawing_independent_approval_required'; end if; if not project.current_user_has_project_role(drawing.project_id,array['interior_designer','lead_architect']) then raise exception 'shop_drawing_approval_role_required'; end if; end if;
 before_state:=to_jsonb(drawing); perform set_config('conceptspaces.design_phase','interiors',true);
 update aec.interior_shop_drawings set status=value,approved_by=case when value='approved' then auth.uid() else approved_by end,approved_at=case when value='approved' then now() else approved_at end,issued_by=case when value='issued' then auth.uid() else issued_by end,issued_at=case when value='issued' then now() else issued_at end,updated_at=now() where id=drawing.id returning * into drawing;
 perform audit.append_event((select organisation_id from project.projects where id=drawing.project_id),drawing.project_id,'interior.shop_drawing.'||value,'interior_shop_drawing',drawing.id,before_state,to_jsonb(drawing),target_reason,gen_random_uuid()); return drawing.status;
end;$$;
revoke all on function public.transition_interior_shop_drawing(uuid,text,text) from public,anon; grant execute on function public.transition_interior_shop_drawing(uuid,text,text) to authenticated;

create or replace function public.list_interiors_workspace(target_project_id uuid)
returns jsonb language plpgsql stable security invoker set search_path='public','aec','project','auth','pg_temp' as $$
begin if auth.uid() is null or not project.can_access_project(target_project_id) then raise exception 'project_access_required'; end if; return jsonb_build_object('dna',coalesce((select jsonb_agg(to_jsonb(d) order by d.version desc) from aec.interior_dna d where d.project_id=target_project_id),'[]'::jsonb),'rooms',coalesce((select jsonb_agg(to_jsonb(r) order by r.space_ref,r.version desc) from aec.interior_room_packages r where r.project_id=target_project_id),'[]'::jsonb),'materials',coalesce((select jsonb_agg(to_jsonb(m) order by m.created_at desc) from aec.interior_material_selections m where m.project_id=target_project_id),'[]'::jsonb),'shop_drawings',coalesce((select jsonb_agg(to_jsonb(s) order by s.component_ref,s.version desc) from aec.interior_shop_drawings s where s.project_id=target_project_id),'[]'::jsonb)); end;$$;
revoke all on function public.list_interiors_workspace(uuid) from public,anon; grant execute on function public.list_interiors_workspace(uuid) to authenticated;

commit;