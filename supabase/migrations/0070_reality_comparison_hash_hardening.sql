begin;

create or replace function public.record_reality_comparison(target_capture_id uuid, input_payload jsonb)
returns text
language plpgsql security invoker
set search_path=public,cde,project,audit,extensions,auth,pg_temp
as $$
declare
  r public.reality_captures%rowtype;
  m cde.models%rowtype;
  d public.reality_deviations%rowtype;
  item jsonb;
  deviations_value jsonb:=coalesce(input_payload->'deviations','[]'::jsonb);
  comparison_hash_value text;
  org_id uuid;
  confidence_value numeric;
  severity_value text;
  type_value text;
  tolerance_num numeric;
begin
  select * into r from public.reality_captures where id=target_capture_id for update;
  if not found or auth.uid() is null or not project.can_manage_project(r.project_id) then raise exception 'reality_compare_authority_required'; end if;
  if r.comparison_status not in ('queued','processing','failed') then raise exception 'reality_capture_not_comparable'; end if;
  select * into m from cde.models where id=r.model_id;
  if not found or m.checksum is distinct from r.model_checksum or m.status not in ('approved','issued') then raise exception 'REALITY_REGISTRATION_FAILED'; end if;
  if jsonb_typeof(deviations_value)<>'array' then raise exception 'reality_deviations_array_required'; end if;

  comparison_hash_value:=encode(extensions.digest(jsonb_build_object(
    'capture_id',r.id,
    'registration_hash',r.registration_hash,
    'model_id',r.model_id,
    'model_checksum',r.model_checksum,
    'coordinate_system',r.coordinate_system,
    'tolerance',r.tolerance,
    'deviations',deviations_value,
    'engine_ref',coalesce(input_payload->>'engine_ref',''),
    'algorithm_version',coalesce(input_payload->>'algorithm_version','')
  )::text,'sha256'),'hex');

  perform set_config('conceptspaces.reality_phase','compare',true);
  delete from public.reality_deviations where comparison_id=r.id and status='detected';
  for item in select value from jsonb_array_elements(deviations_value) loop
    type_value:=lower(btrim(item->>'deviation_type'));
    severity_value:=lower(btrim(item->>'severity'));
    confidence_value:=nullif(item->>'confidence','')::numeric;
    tolerance_num:=nullif(item->>'permitted_tolerance','')::numeric;
    if type_value not in ('position','dimension','missing','unexpected','finish','progress','quality') then raise exception 'reality_deviation_type_invalid'; end if;
    if severity_value not in ('informational','minor','major','critical') then raise exception 'reality_deviation_severity_invalid'; end if;
    if confidence_value is null or confidence_value<0 or confidence_value>1 then raise exception 'reality_confidence_required'; end if;
    if jsonb_typeof(coalesce(item->'evidence_refs','[]'::jsonb))<>'array' or jsonb_array_length(coalesce(item->'evidence_refs','[]'::jsonb))=0 then raise exception 'reality_deviation_evidence_required'; end if;
    insert into public.reality_deviations(comparison_id,project_id,model_object_ref,location_ref,deviation_type,measured_value,permitted_tolerance,unit,severity,status,evidence_refs,confidence,source_model_checksum)
    values(r.id,r.project_id,nullif(btrim(item->>'model_object_ref'),''),nullif(btrim(item->>'location_ref'),''),type_value,nullif(item->>'measured_value','')::numeric,tolerance_num,nullif(btrim(item->>'unit'),''),severity_value,'detected',item->'evidence_refs',confidence_value,r.model_checksum) returning * into d;
  end loop;

  update public.reality_captures
  set comparison_hash=comparison_hash_value,
      comparison_status=case when jsonb_array_length(deviations_value)>0 then 'review_required' else 'accepted' end,
      reviewed_by=case when jsonb_array_length(deviations_value)=0 then auth.uid() else null end,
      reviewed_at=case when jsonb_array_length(deviations_value)=0 then now() else null end,
      review_note=case when jsonb_array_length(deviations_value)=0 then 'No deviations reported by deterministic comparison payload.' else null end
  where id=r.id returning * into r;

  select organisation_id into org_id from project.projects where id=r.project_id;
  perform audit.append_event(org_id,r.project_id,'reality.comparison.recorded','reality_capture',r.id,null,to_jsonb(r),comparison_hash_value,gen_random_uuid());
  return r.comparison_status;
end;$$;

revoke all on function public.record_reality_comparison(uuid,jsonb) from public,anon;
grant execute on function public.record_reality_comparison(uuid,jsonb) to authenticated;

commit;
