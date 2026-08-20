# Build Pack 30 — Building Git & Change Impact Runtime

Build Pack 30 activates governed project configuration control. The former illustrative **Project Branches** and **Change Impact Engine™** surfaces are now live operating workspaces backed by exact project configuration hashes, immutable commit lineage and maker-checker change approval.

## Building Git

- Project `main` is bootstrapped from the current governed project configuration hash.
- Genesis commits preserve the exact initial branch head.
- Alternative branches are created from a specific parent head and cannot silently diverge from an unknown baseline.
- Branch names are validated and `main` is reserved.
- Active option branches can be frozen, reactivated or abandoned with a mandatory audit reason.
- Applied project changes create immutable commits with parent hash, analysis hash, source-object references, author and message.
- The exact applied commit hash is retained on the governed change request so a later branch advance cannot be merged under an older approval.
- Governed merges require an applied change on the source branch and create a two-parent merge commit.
- Merged and abandoned branches are terminal.

## Change Impact Engine™

A change request records:

- project and branch;
- change reference, title and description;
- source object references;
- declared affected disciplines;
- lifecycle state from `draft` through analysis, approval and application.

`analyze_project_change()` freezes both the project configuration baseline and the current branch head, then inventories the current downstream blast radius:

- project requirements;
- latest REGULA compliance findings;
- CDE documents and models in affected disciplines;
- discipline-relevant BOQ lines;
- active project contracts;
- cross-discipline coordination items and resource freshness;
- unissued release safety cases;
- engineering calculations in affected disciplines;
- open project programme/work tasks.

The analysis stores estimated cost delta, schedule delta, Decision Reversal Cost™, criticality, confidence, the analyzed branch-head hash and an immutable `analysis_hash`. A new analysis supersedes the prior analysis rather than rewriting it.

## Fail-closed approval and application

- If coordination or release impact exists, analysis criticality is automatically elevated to at least C3.
- Project changes use the existing governed approval runtime.
- Approval requests explicitly cite the exact analysis hash.
- C3/C4 decisions therefore inherit independent maker-checker and verified professional eligibility controls.
- Synchronisation refuses an approval whose decision evidence hash does not equal the latest analysis hash.
- Approval/application is blocked if either the live project configuration hash or the analyzed branch head changes after analysis.
- Application creates an immutable Building Git commit and records that exact commit hash on the change request; it does not silently mutate design-domain data.
- Branch merge is separately governed and is blocked if the project baseline changed, the source branch moved beyond the approved applied commit, or the approved change is otherwise no longer current.

## Live workspaces

`/app/change-impact` now supports proposal, analysis/re-analysis, exact-hash approval request, approval synchronisation, commit and cancellation.

`/app/branches` now supports main bootstrap, exact-head branching, freeze/reactivate/abandon controls, governed merge and the immutable commit ledger.

## Production database checkpoint

Production Supabase migrations:

- `0049_configuration_control_foundation.sql`
- `0050_change_impact_execution.sql`
- `0051_configuration_branch_freshness.sql`

Verification:

- Supabase security advisor: zero findings after all three Pack 30 migrations.
- Configuration/change RPCs are executable by `authenticated` only through RLS-gated governed mutation phases.
- `project_change_requests` has RLS enabled.
- Exact project-configuration freshness and exact analyzed branch-head freshness are both required before approval/application.
- Applied changes retain the exact applied commit hash, and governed merge rejects a source branch that advanced beyond it.
- Production currently contains zero project branches and zero change requests.
- Production currently contains zero active `project.project_members`, so no tenant/project data was fabricated merely to run a destructive smoke transaction. Runtime verification therefore used schema/function/RLS checks plus application compilation; the first real project member can bootstrap `main` from the current project state through the workspace.

## Release discipline

Pack 30 is promoted only after the exact final branch head is Vercel READY, GitHub CI passes dependency audit, repository security/migration validation, TypeScript, tests and production build, and the merged `main` deployment is independently READY in production.
