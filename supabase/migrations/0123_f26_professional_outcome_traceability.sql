begin;

alter table engagement.professional_performance_metrics add column if not exists source_outcome_signal_id uuid references public.outcome_signals(id) on delete restrict;

create or replace function public.record_professional_performance(target_profile_id uuid,target_project_id uuid,input_payload jsonb)
returns uuid language plpgsql security invoker set search_path='engagement','project','public','audit','extensions','auth','pg_temp' as $$
declare p engagement.professional_profiles%rowtype;proj project.projects%rowtype;r engagement.professional_performance_metrics%rowtype;s public.outcome_signals%rowtype;outcome text:=lower(btrim(input_payload->>'outcome_type'));source_ref_value text:=btrim(input_payload->>'source_ref');source_hash_value text:=lower(btrim(input_payload->>'source_hash'));expected_hash text;
begin
 select * into p from engagement.professional_profiles where id=target_profile_id;if not found then raise exception 'professional_profile_not_found';end if;
 select * into proj from project.projects where id=target_project_id;if not found or proj.organisation_id<>p.organisation_id then raise exception 'professional_project_organisation_mismatch';end if;
 if auth.uid() is null or not project.can_access_project(target_project_id) then raise exception 'project_access_required';end if;
 if nullif(btrim(input_payload->>'metric_code'),'') is null or nullif(input_payload->>'metric_value','') is null or nullif(btrim(input_payload->>'unit'),'') is null then raise exception 'performance_metric_fields_required';end if;
 if outcome not in ('first_pass_quality','correction','schedule','rfi','ncr','cost_impact','review','other') then raise exception 'performance_outcome_type_invalid';end if;
 if nullif(source_ref_value,'') is null or source_hash_value !~ '^[0-9a-f]{64}$' then raise exception 'performance_source_outcome_evidence_required';end if;
 select * into s from public.outcome_signals os where os.project_id=target_project_id and (os.id::text=source_ref_value or os.source_ref=source_ref_value) order by os.captured_at desc limit 1;
 if not found then raise exception 'PERFORMANCE_SOURCE_MUST_BE_GOVERNED_PROJECT_OUTCOME';end if;
 expected_hash:=encode(extensions.digest(jsonb_build_object('id',s.id,'project_id',s.project_id,'signal_type',s.signal_type,'source_ref',s.source_ref,'value',s.value,'confidence',s.confidence,'captured_at',s.captured_at)::text,'sha256'),'hex');
 if source_hash_value<>expected_hash then raise exception 'PERFORMANCE_SOURCE_HASH_MISMATCH';end if;
 perform set_config('conceptspaces.professional_phase','performance',true);
 insert into engagement.professional_performance_metrics(organisation_id,profile_id,project_id,metric_code,metric_value,unit,outcome_type,source_ref,source_hash,notes,recorded_by,source_outcome_signal_id)
 values(proj.organisation_id,p.id,proj.id,lower(btrim(input_payload->>'metric_code')),nullif(input_payload->>'metric_value','')::numeric,btrim(input_payload->>'unit'),outcome,s.id::text,expected_hash,nullif(btrim(input_payload->>'notes'),''),auth.uid(),s.id) returning * into r;
 perform audit.append_event(proj.organisation_id,proj.id,'professional.performance_recorded','professional_performance_metric',r.id,null,to_jsonb(r),expected_hash,gen_random_uuid());return r.id;
end;$$;
revoke all on function public.record_professional_performance(uuid,uuid,jsonb) from public,anon;grant execute on function public.record_professional_performance(uuid,uuid,jsonb) to authenticated;

create or replace function public.list_professional_outcome_sources(target_project_id uuid)
returns jsonb language plpgsql stable security invoker set search_path='public','project','extensions','auth','pg_temp' as $$
begin
 if auth.uid() is null or not project.can_access_project(target_project_id) then raise exception 'project_access_required';end if;
 return coalesce((select jsonb_agg(jsonb_build_object('id',s.id,'signal_type',s.signal_type,'source_ref',s.source_ref,'value',s.value,'confidence',s.confidence,'captured_at',s.captured_at,'source_hash',encode(extensions.digest(jsonb_build_object('id',s.id,'project_id',s.project_id,'signal_type',s.signal_type,'source_ref',s.source_ref,'value',s.value,'confidence',s.confidence,'captured_at',s.captured_at)::text,'sha256'),'hex')) order by s.captured_at desc) from public.outcome_signals s where s.project_id=target_project_id),'[]'::jsonb);
end;$$;
revoke all on function public.list_professional_outcome_sources(uuid) from public,anon;grant execute on function public.list_professional_outcome_sources(uuid) to authenticated;

commit;
