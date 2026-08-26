begin;

create or replace function public.list_ai_runtime_workspace()
returns jsonb
language plpgsql
stable
security invoker
set search_path='ai','project','core','auth','pg_temp'
as $$
begin
  if auth.uid() is null or not core.is_platform_admin() then
    raise exception 'platform_admin_required';
  end if;

  return jsonb_build_object(
    'projects',coalesce((
      select jsonb_agg(jsonb_build_object(
        'id',p.id,
        'organisation_id',p.organisation_id,
        'code',p.code::text,
        'name',p.name,
        'criticality',p.criticality,
        'status',p.status
      ) order by p.created_at desc)
      from project.projects p
    ),'[]'::jsonb),
    'agents',coalesce((
      select jsonb_agg(jsonb_build_object(
        'code',a.code::text,
        'name',a.name,
        'enabled',a.enabled,
        'max_criticality',a.max_criticality,
        'allowed_autonomy',a.allowed_autonomy,
        'requires_grounding',a.requires_grounding,
        'definition_hash',a.definition_hash
      ) order by a.code)
      from ai.agent_definitions a
    ),'[]'::jsonb),
    'models',coalesce((
      select jsonb_agg(jsonb_build_object(
        'id',m.id,
        'provider',m.provider,
        'model',m.model,
        'enabled',m.enabled,
        'max_criticality',m.max_criticality,
        'evaluation_threshold',m.evaluation_threshold,
        'profile_hash',m.profile_hash
      ) order by m.provider,m.model)
      from ai.model_profiles m
    ),'[]'::jsonb),
    'runs',coalesce((
      select jsonb_agg(jsonb_build_object(
        'id',r.id,
        'organisation_id',r.organisation_id,
        'project_id',r.project_id,
        'agent_code',r.agent_code::text,
        'model_profile_id',r.model_profile_id,
        'prompt_version_id',r.prompt_version_id,
        'status',r.status,
        'criticality',r.criticality,
        'input_ref',r.input_ref,
        'output_ref',r.output_ref,
        'output_status',r.output_status,
        'output_hash',r.output_hash,
        'grounding_status',r.grounding_status,
        'evidence_refs',r.evidence_refs,
        'correlation_id',r.correlation_id,
        'started_at',r.started_at,
        'finished_at',r.finished_at,
        'created_at',r.created_at
      ) order by r.created_at desc)
      from (select * from ai.agent_runs order by created_at desc limit 100) r
    ),'[]'::jsonb),
    'learning_candidates',coalesce((
      select jsonb_agg(jsonb_build_object(
        'id',c.id,
        'source_project_id',c.source_project_id,
        'source_type',c.source_type,
        'source_ref',c.source_ref,
        'stage',c.stage,
        'privacy_state',c.privacy_state,
        'evidence_quality',c.evidence_quality,
        'benchmark_delta',c.benchmark_delta,
        'expert_reviewers',c.expert_reviewers,
        'rollback_ref',c.rollback_ref,
        'promotion_scope',c.promotion_scope,
        'privacy_reviewed_by',c.privacy_reviewed_by,
        'privacy_reviewed_at',c.privacy_reviewed_at,
        'expert_reviewed_by',c.expert_reviewed_by,
        'expert_reviewed_at',c.expert_reviewed_at,
        'promoted_at',c.promoted_at,
        'candidate_hash',c.candidate_hash,
        'created_at',c.created_at,
        'updated_at',c.updated_at
      ) order by c.updated_at desc)
      from (select * from ai.learning_candidates order by updated_at desc limit 100) c
    ),'[]'::jsonb)
  );
end;
$$;

revoke all on function public.list_ai_runtime_workspace() from public,anon;
grant execute on function public.list_ai_runtime_workspace() to authenticated;

commit;
