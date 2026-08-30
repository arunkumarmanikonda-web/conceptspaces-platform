begin;

-- Authenticated project startup computes the immutable main-branch snapshot.
grant usage on schema configuration, cost to authenticated;
grant select on cost.cost_plans to authenticated;

-- JWT-bound Edge Functions prove user authority first, then persist deterministic
-- engine results with the service role. Custom schemas do not inherit privileges.
grant usage on schema core, project, configuration, audit to service_role;
grant select on core.memberships to service_role;
grant select on project.projects, project.project_members to service_role;

grant select, insert on aec.site_geometries to service_role;
grant update(evaluated_at) on aec.site_geometries to service_role;

grant select, insert, update on public.compilation_runs to service_role;
grant select, insert on public.compiler_input_snapshots to service_role;
grant select, insert, delete on public.compiler_stage_runs to service_role;
grant select, insert, delete on public.pareto_candidates to service_role;
grant select, insert, update on public.project_branches to service_role;
grant select, insert on public.project_commits to service_role;

grant execute on function configuration.project_configuration_hash(uuid) to service_role;

commit;
