begin;

-- F07: external clients receive only the current non-superseded project-stage baseline.
create or replace function engagement.current_client_stage_projection(target_project_id uuid)
returns jsonb
language plpgsql
stable security definer
set search_path='engagement','project','auth','pg_temp'
as $$
declare baseline_value int;
begin
  if auth.uid() is null or not engagement.client_can_access_project(target_project_id) then raise exception 'CLIENT_PERMISSION_DENIED'; end if;
  select max(s.baseline_version) into baseline_value from project.project_stages s where s.project_id=target_project_id and s.state<>'superseded';
  if baseline_value is null then return '[]'::jsonb; end if;
  return coalesce((
    select jsonb_agg(jsonb_build_object(
      'id',s.id,'stage_code',s.stage_code,'title',s.title,'sequence',s.sequence,'state',s.state,
      'planned_start',s.planned_start,'planned_finish',s.planned_finish,'actual_start',s.actual_start,'actual_finish',s.actual_finish,
      'baseline_version',s.baseline_version,'contracted_modules',s.contracted_modules
    ) order by s.sequence)
    from project.project_stages s
    where s.project_id=target_project_id and s.baseline_version=baseline_value and s.state<>'superseded'
  ),'[]'::jsonb);
end;
$$;
revoke all on function engagement.current_client_stage_projection(uuid) from public,anon;
grant execute on function engagement.current_client_stage_projection(uuid) to authenticated;

create or replace function public.list_client_portal_workspace(target_project_id uuid)
returns jsonb
language plpgsql
stable security invoker
set search_path='public','engagement','project','auth','pg_temp'
as $$
declare payload jsonb; internal_mode boolean;
begin
  payload:=engagement.list_client_portal_workspace_impl(target_project_id);
  internal_mode:=project.can_access_project(target_project_id);
  if not internal_mode then
    payload:=jsonb_set(payload,'{stages}',engagement.current_client_stage_projection(target_project_id),true);
  end if;
  return payload;
end;
$$;
revoke all on function public.list_client_portal_workspace(uuid) from public,anon;
grant execute on function public.list_client_portal_workspace(uuid) to authenticated;

-- Generic downstream invalidation used whenever authoritative site/project truth changes.
create or replace function project.invalidate_compiler_runs(target_project_id uuid,target_reason text,target_evidence_hash text)
returns integer
language plpgsql
security definer
set search_path='project','public','audit','extensions','pg_temp'
as $$
declare affected int:=0; org_id uuid;
begin
  if nullif(btrim(target_reason),'') is null then raise exception 'invalidation_reason_required'; end if;
  if target_evidence_hash !~ '^[0-9a-f]{64}$' then raise exception 'invalidation_evidence_hash_required'; end if;
  select organisation_id into org_id from project.projects where id=target_project_id;
  if org_id is null then raise exception 'project_not_found'; end if;
  update public.compilation_runs r
     set status='superseded',
         blocked_reasons=coalesce(r.blocked_reasons,'[]'::jsonb)||jsonb_build_array(jsonb_build_object('code','INPUT_VERSION_STALE','reason',target_reason,'evidence_hash',target_evidence_hash,'invalidated_at',now()))
   where r.project_id=target_project_id and r.status in ('queued','running','blocked','awaiting_review','completed');
  get diagnostics affected=row_count;
  if affected>0 then
    perform audit.append_event(org_id,target_project_id,'compiler.input_invalidated','project',target_project_id,null,jsonb_build_object('affected_runs',affected,'reason',target_reason,'evidence_hash',target_evidence_hash),target_evidence_hash,gen_random_uuid());
  end if;
  return affected;
end;
$$;
revoke all on function project.invalidate_compiler_runs(uuid,text,text) from public,anon,authenticated;

-- Governed Project Truth mutation. Drafts may be captured by project roles; verification requires evidence and authority.
drop policy if exists truth_record_governed_update on project.truth_records;
create policy truth_record_governed_update on project.truth_records for update to authenticated
using(project.can_access_project(project_id))
with check(project.can_access_project(project_id) and current_setting('conceptspaces.truth_phase',true) in ('verify','supersede'));

grant update on project.truth_records to authenticated;

create or replace function public.create_project_truth_record(target_project_id uuid,input_payload jsonb)
returns uuid
language plpgsql security invoker
set search_path='project','core','audit','auth','pg_temp'
as $$
declare p project.projects%rowtype;r project.truth_records%rowtype;k text:=lower(btrim(input_payload->>'kind'));conf text:=upper(coalesce(nullif(btrim(input_payload->>'confidence'),''),'D'));crit text:=upper(coalesce(nullif(btrim(input_payload->>'criticality'),''),'C1'));
begin
  select * into p from project.projects where id=target_project_id;
  if not found or auth.uid() is null or not project.can_access_project(p.id) then raise exception 'project_access_required'; end if;
  if k not in ('fact','assumption','decision','requirement','constraint','evidence') then raise exception 'truth_kind_invalid'; end if;
  if nullif(btrim(input_payload->>'record_key'),'') is null or not (input_payload ? 'value') then raise exception 'truth_key_value_required'; end if;
  if conf not in ('A','B','C','D') or crit not in ('C0','C1','C2','C3','C4') then raise exception 'truth_confidence_criticality_invalid'; end if;
  insert into project.truth_records(project_id,kind,record_key,value,unit,source_type,source_reference,confidence,status,criticality,valid_from,created_by)
  values(p.id,k,btrim(input_payload->>'record_key'),input_payload->'value',nullif(btrim(input_payload->>'unit'),''),nullif(btrim(input_payload->>'source_type'),''),nullif(btrim(input_payload->>'source_reference'),''),conf,'draft',crit,now(),auth.uid()) returning * into r;
  perform audit.append_event(p.organisation_id,p.id,'project.truth.drafted','truth_record',r.id,null,to_jsonb(r),null,gen_random_uuid());
  return r.id;
end;
$$;
revoke all on function public.create_project_truth_record(uuid,jsonb) from public,anon;
grant execute on function public.create_project_truth_record(uuid,jsonb) to authenticated;

create or replace function public.verify_project_truth_record(target_truth_id uuid,target_reason text)
returns text
language plpgsql security invoker
set search_path='project','core','audit','extensions','auth','pg_temp'
as $$
declare r project.truth_records%rowtype;p project.projects%rowtype;before_state jsonb;h text;
begin
  select * into r from project.truth_records where id=target_truth_id for update;
  if not found then raise exception 'truth_record_not_found'; end if;
  select * into p from project.projects where id=r.project_id;
  if auth.uid() is null or not project.can_manage_project(p.id) then raise exception 'project_manage_authority_required'; end if;
  if r.status<>'draft' then raise exception 'truth_record_not_draft'; end if;
  if nullif(btrim(r.source_type),'') is null or nullif(btrim(r.source_reference),'') is null then raise exception 'verified_fact_requires_source'; end if;
  if nullif(btrim(target_reason),'') is null then raise exception 'truth_verification_reason_required'; end if;
  h:=encode(extensions.digest(jsonb_build_object('project_id',r.project_id,'kind',r.kind,'record_key',r.record_key,'value',r.value,'unit',r.unit,'source_type',r.source_type,'source_reference',r.source_reference,'confidence',r.confidence,'criticality',r.criticality)::text,'sha256'),'hex');
  before_state:=to_jsonb(r);
  perform set_config('conceptspaces.truth_phase','verify',true);
  update project.truth_records set status='verified',verified_by=auth.uid(),verified_at=now(),updated_at=now() where id=r.id returning * into r;
  perform project.invalidate_compiler_runs(p.id,'Verified Project Truth changed: '||r.record_key,h);
  perform audit.append_event(p.organisation_id,p.id,'project.truth.verified','truth_record',r.id,before_state,to_jsonb(r),h,gen_random_uuid());
  return r.status;
end;
$$;
revoke all on function public.verify_project_truth_record(uuid,text) from public,anon;
grant execute on function public.verify_project_truth_record(uuid,text) to authenticated;

create or replace function public.supersede_project_truth_record(target_truth_id uuid,input_payload jsonb,target_reason text)
returns uuid
language plpgsql security invoker
set search_path='project','core','audit','auth','pg_temp'
as $$
declare old_r project.truth_records%rowtype;new_r project.truth_records%rowtype;p project.projects%rowtype;
begin
  select * into old_r from project.truth_records where id=target_truth_id for update;
  if not found then raise exception 'truth_record_not_found'; end if;
  select * into p from project.projects where id=old_r.project_id;
  if auth.uid() is null or not project.can_manage_project(p.id) then raise exception 'project_manage_authority_required'; end if;
  if old_r.status not in ('draft','verified') then raise exception 'truth_record_not_supersedable'; end if;
  if nullif(btrim(target_reason),'') is null then raise exception 'truth_supersession_reason_required'; end if;
  perform set_config('conceptspaces.truth_phase','supersede',true);
  update project.truth_records set status='superseded',valid_until=now(),updated_at=now() where id=old_r.id;
  insert into project.truth_records(project_id,kind,record_key,value,unit,source_type,source_reference,confidence,status,criticality,valid_from,supersedes_id,created_by)
  values(old_r.project_id,old_r.kind,old_r.record_key,coalesce(input_payload->'value',old_r.value),coalesce(nullif(btrim(input_payload->>'unit'),''),old_r.unit),coalesce(nullif(btrim(input_payload->>'source_type'),''),old_r.source_type),coalesce(nullif(btrim(input_payload->>'source_reference'),''),old_r.source_reference),upper(coalesce(nullif(btrim(input_payload->>'confidence'),''),old_r.confidence)),'draft',upper(coalesce(nullif(btrim(input_payload->>'criticality'),''),old_r.criticality)),now(),old_r.id,auth.uid()) returning * into new_r;
  perform audit.append_event(p.organisation_id,p.id,'project.truth.superseded','truth_record',old_r.id,to_jsonb(old_r),jsonb_build_object('replacement_id',new_r.id,'replacement',to_jsonb(new_r)),target_reason,gen_random_uuid());
  return new_r.id;
end;
$$;
revoke all on function public.supersede_project_truth_record(uuid,jsonb,text) from public,anon;
grant execute on function public.supersede_project_truth_record(uuid,jsonb,text) to authenticated;

-- Geometry verification is now auditable and invalidates compiler outputs that predate the newly authoritative boundary.
create or replace function public.verify_site_geometry(target_geometry_id uuid,target_content_hash text)
returns void
language plpgsql
security invoker
set search_path='aec','project','core','audit','public','auth','pg_temp'
as $$
declare g aec.site_geometries%rowtype;p project.projects%rowtype;actor uuid:=auth.uid();before_state jsonb;
begin
  if actor is null then raise exception 'authentication_required'; end if;
  select * into g from aec.site_geometries where id=target_geometry_id for update; if not found then raise exception 'geometry_not_found'; end if;
  select * into p from project.projects where id=g.project_id;
  if g.content_hash is distinct from lower(target_content_hash) then raise exception 'geometry_hash_changed'; end if;
  if not g.engine_valid then raise exception 'invalid_geometry_cannot_be_verified'; end if;
  if nullif(btrim(g.source_reference),'') is null then raise exception 'verified_geometry_source_reference_required'; end if;
  if not (core.has_verified_professional_eligibility(actor,'lead_architect') or core.has_verified_professional_eligibility(actor,'architect')) then raise exception 'verified_architectural_professional_required'; end if;
  before_state:=to_jsonb(g);
  perform set_config('conceptspaces.geometry_verify','on',true);perform set_config('conceptspaces.geometry_actor',actor::text,true);
  update aec.site_geometries set verification='professionally_verified',verified_by=actor,verified_at=now(),updated_at=now() where id=g.id returning * into g;
  perform project.invalidate_compiler_runs(g.project_id,'Authoritative site boundary verified',g.content_hash);
  perform audit.append_event(p.organisation_id,p.id,'site.geometry.verified','site_geometry',g.id,before_state,to_jsonb(g),g.content_hash,gen_random_uuid());
end;
$$;

commit;
