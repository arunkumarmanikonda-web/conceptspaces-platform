begin;

create or replace function public.start_qto_run(target_project_id uuid,input_payload jsonb)
returns uuid language plpgsql security invoker set search_path='public','cost','cde','project','audit','extensions','auth','pg_temp' as $$
declare m cde.models%rowtype;q cost.qto_runs%rowtype;b cost.qto_benchmark_results%rowtype;org_id uuid;model_id_value uuid:=nullif(input_payload->>'model_id','')::uuid;rule_ref text:=btrim(input_payload->>'measurement_rule_set_ref');engine_ref_value text:=btrim(input_payload->>'engine_ref');engine_version_value text:=btrim(input_payload->>'engine_version');input_hash_value text;
begin
 if auth.uid() is null or not project.can_manage_project(target_project_id) then raise exception 'project_manage_authority_required';end if;
 select * into m from cde.models where id=model_id_value and project_id=target_project_id;if not found then raise exception 'model_not_found';end if;if m.status not in ('approved','issued') then raise exception 'approved_model_required';end if;
 if nullif(rule_ref,'') is null or nullif(engine_ref_value,'') is null or nullif(engine_version_value,'') is null then raise exception 'measurement_rule_set_and_engine_required';end if;
 select r.* into b from cost.qto_benchmark_results r join cost.qto_benchmark_cases bc on bc.id=r.case_id where r.status='approved' and r.passed and bc.status='approved' and bc.measurement_rule_set_ref=rule_ref and r.engine_ref=engine_ref_value and r.engine_version=engine_version_value order by r.reviewed_at desc limit 1;
 if b.id is null then raise exception 'QTO_BENCHMARK_CERTIFICATION_REQUIRED';end if;
 input_hash_value:=encode(extensions.digest(jsonb_build_object('project_id',target_project_id,'model_id',m.id,'model_checksum',m.checksum,'measurement_rule_set_ref',rule_ref,'engine_ref',engine_ref_value,'engine_version',engine_version_value,'benchmark_result_id',b.id,'benchmark_result_hash',b.result_hash,'classification_ref',nullif(btrim(input_payload->>'classification_ref'),''),'exclusions',coalesce(input_payload->'exclusions','[]'::jsonb),'tolerance',coalesce(input_payload->'tolerance','{}'::jsonb))::text,'sha256'),'hex');
 perform set_config('conceptspaces.cost_phase','qto_create',true);
 insert into cost.qto_runs(project_id,model_id,model_checksum,measurement_rule_set_ref,classification_ref,exclusions,tolerance,input_hash,status,created_by,engine_ref,engine_version,benchmark_result_id) values(target_project_id,m.id,m.checksum,rule_ref,nullif(btrim(input_payload->>'classification_ref'),''),coalesce(input_payload->'exclusions','[]'::jsonb),coalesce(input_payload->'tolerance','{}'::jsonb),input_hash_value,'queued',auth.uid(),engine_ref_value,engine_version_value,b.id) returning * into q;
 select organisation_id into org_id from project.projects where id=target_project_id;
 perform audit.append_event(org_id,target_project_id,'cost.qto.started','qto_run',q.id,null,to_jsonb(q),input_hash_value,gen_random_uuid());return q.id;
end;$$;
revoke all on function public.start_qto_run(uuid,jsonb) from public,anon;grant execute on function public.start_qto_run(uuid,jsonb) to authenticated;

commit;
