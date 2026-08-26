begin;

create or replace function public.record_cde_model_validation(target_model_id uuid,input_payload jsonb)
returns uuid
language plpgsql security invoker
set search_path=public,cde,project,coordination,audit,auth,pg_temp
as $$
declare m cde.models%rowtype; v cde.model_validation_runs%rowtype; org_id uuid; validation_type_value text; result_hash_value text; issue_id uuid;
begin
  select * into m from cde.models where id=target_model_id for update;
  if not found or auth.uid() is null or not project.can_manage_project(m.project_id) then raise exception 'model_manage_authority_required'; end if;
  if m.status in ('issued','superseded','withdrawn') then raise exception 'immutable_model_revision'; end if;
  validation_type_value:=lower(coalesce(nullif(btrim(input_payload->>'validation_type'),''),'ifc'));
  if validation_type_value not in ('ifc','ids','geometry','semantic','round_trip') then raise exception 'unsupported_validation_type'; end if;
  result_hash_value:=lower(coalesce(input_payload->>'result_hash',''));
  if result_hash_value !~ '^[0-9a-f]{64}$' then raise exception 'validation_result_hash_required'; end if;
  perform set_config('conceptspaces.model_phase','validate',true);
  insert into cde.model_validation_runs(project_id,model_id,validation_type,adapter_key,adapter_version,passed,result_hash,findings,evidence_refs,created_by)
  values(m.project_id,m.id,validation_type_value,nullif(btrim(input_payload->>'adapter_key'),''),nullif(btrim(input_payload->>'adapter_version'),''),coalesce((input_payload->>'passed')::boolean,false),result_hash_value,coalesce(input_payload->'findings','[]'::jsonb),coalesce(input_payload->'evidence_refs','[]'::jsonb),auth.uid()) returning * into v;
  update cde.models set validation_summary=jsonb_build_object('validation_run_id',v.id,'type',v.validation_type,'passed',v.passed,'findings',v.findings,'validated_at',v.created_at),validation_hash=v.result_hash,updated_at=now() where id=m.id returning * into m;
  if not v.passed then
    issue_id:=public.create_coordination_issue(jsonb_build_object('project_id',m.project_id,'issue_type','coordination','title',upper(v.validation_type)||' validation failed · '||m.model_name,'description','Model validation failed. Review structured findings in validation run '||v.id::text,'priority',case when jsonb_array_length(v.findings)>0 then 'high' else 'medium' end,'criticality',coalesce(nullif(upper(input_payload->>'criticality'),''),'C2')));
    perform set_config('conceptspaces.coordination_phase','raise',true);
    insert into coordination.issue_links(issue_id,resource_type,resource_id,relationship) values(issue_id,'model',m.id,'validation_failure') on conflict do nothing;
  end if;
  select organisation_id into org_id from project.projects where id=m.project_id;
  perform audit.append_event(org_id,m.project_id,'cde.model.validation_recorded','model_validation',v.id,null,to_jsonb(v),v.result_hash,gen_random_uuid());
  return v.id;
end;$$;
revoke all on function public.record_cde_model_validation(uuid,jsonb) from public,anon;
grant execute on function public.record_cde_model_validation(uuid,jsonb) to authenticated;

commit;