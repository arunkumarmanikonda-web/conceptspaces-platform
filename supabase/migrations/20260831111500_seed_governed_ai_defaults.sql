begin;

do $$
declare
  seed_admin uuid;
  agent_hash text;
  model_hash text;
  prompt_hash text;
begin
  select m.user_id into seed_admin
  from core.memberships m
  where m.status='active' and m.role_code='super_admin'
  order by m.created_at
  limit 1;

  if seed_admin is null then
    raise exception 'active_super_admin_required_for_ai_defaults';
  end if;

  agent_hash:=encode(extensions.digest('project-intelligence:v1'::text,'sha256'),'hex');
  model_hash:=encode(extensions.digest('openai:gpt-5.4:vercel-ai-gateway:v1'::text,'sha256'),'hex');
  prompt_hash:=encode(extensions.digest('project-intelligence:prompt:v1'::text,'sha256'),'hex');

  insert into ai.agent_definitions(
    code,name,purpose,max_criticality,allowed_autonomy,allowed_tools,
    prohibited_actions,no_hallucination_zones,requires_grounding,
    requires_human_approval_for,enabled,created_by,updated_by,definition_hash
  ) values (
    'project-intelligence','Project Intelligence','Generate evidence-grounded project analysis, spatial options and review-ready design recommendations.',
    'C2','ai_draft','["project_context","document_retrieval","structured_output"]'::jsonb,
    '["issue_construction_documents","approve_design","alter_verified_facts","submit_to_authorities"]'::jsonb,
    '["dimensions","title_and_ownership","statutory_compliance","professional_certification","cost_commitments"]'::jsonb,
    true,'["client_facing_release","drawing_issue","regulatory_claim","cost_commitment"]'::jsonb,
    false,seed_admin,seed_admin,agent_hash
  ) on conflict(code) do nothing;

  insert into ai.model_profiles(
    provider,model,purpose,enabled,max_criticality,supports_structured_output,
    supports_vision,supports_tool_use,data_residency,cost_policy,
    latency_target_ms,evaluation_threshold,secret_ref,created_by,profile_hash
  ) values (
    'openai','gpt-5.4','Primary governed reasoning model through Vercel AI Gateway.',false,'C2',true,true,true,
    'provider-managed','{"daily_budget_usd":25,"per_run_budget_usd":1.5}'::jsonb,
    45000,0.9000,'vercel-oidc:ai-gateway',seed_admin,model_hash
  ) on conflict(provider,model,purpose) do nothing;

  insert into ai.prompt_versions(
    agent_code,version,template,output_schema_ref,system_policy_ref,status,created_by,prompt_hash
  ) values (
    'project-intelligence',1,
    'Act as the governed Concept Spaces project-intelligence agent. Use only the supplied project facts and evidence references. Separate verified facts, client declarations, assumptions, conflicts and missing information. Never invent dimensions, approvals, codes, ownership, costs or professional certification. Produce review-ready options with explicit rationale, risks, dependencies and human approval gates. Any drawing or layout is a preliminary design study until independently checked and professionally approved.',
    'conceptspaces.ai.project-intelligence.v1','conceptspaces.ai.governance.v1','draft',seed_admin,prompt_hash
  ) on conflict(agent_code,version) do nothing;

  insert into ai.evaluation_cases(suite_code,name,input,expected_assertions,criticality,active,regression_tolerance)
  select 'project-intelligence','Two adjacent plots: preserve parcel truth and avoid invented dimensions',
    '{"project_type":"residential","parcels":[{"area_sq_yd":114.82},{"area_sq_yd":114.82}],"combined_area_sq_yd":229.64,"dimensions":null}'::jsonb,
    '["states both parcel areas","keeps parcel boundaries explicit","does not invent side dimensions","labels output preliminary","requests survey evidence before dimensional release"]'::jsonb,
    'C2',true,0.02
  where not exists(
    select 1 from ai.evaluation_cases where suite_code='project-intelligence' and name='Two adjacent plots: preserve parcel truth and avoid invented dimensions'
  );
end $$;

commit;
