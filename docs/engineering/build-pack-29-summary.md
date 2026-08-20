# Build Pack 29 — Governed Coordination Runtime

Build Pack 29 activates the cross-discipline coordination layer that Release Assurance depends on. Coordination is no longer represented by illustrative rows or by an empty engineering matrix. Each coordination decision is now linked to a governed issue, accountable owner, exact source/target resource baseline, resolution evidence and release impact.

## Runtime activated

- `engineering.coordination_matrix` is operated through governed RPCs rather than direct client writes.
- Raising a matrix item atomically creates its underlying coordination issue and captures the selected source/target resource hashes.
- Supported coordination resources are project-validated before capture and remain traceable to the source CDE/project object.
- Matrix state is constrained to `open`, `coordinating`, `resolved` and `accepted_deviation`.
- Resolution requires explicit rationale plus non-empty evidence references.
- Accepted deviations require an already-approved governed approval whose reviewed evidence hash equals the current coordination hash.
- Matrix transitions keep the linked issue state synchronized so `/app/issues` cannot silently close coordination debt ahead of the matrix.
- Owner changes, state transitions, deviation requests, resolutions, reopens and re-baselines are written to the append-only coordination event ledger and audit chain.

## Resource freshness invariant

A coordination decision is valid only against the resource versions it actually reviewed.

- Source and target resource hashes are captured when the item is raised.
- `engineering.coordination_item_resources_current()` compares those captured hashes with the current linked resources.
- Positive coordination transitions fail closed when either linked baseline has changed.
- A governed re-baseline operation captures the new resource snapshots, generates a new coordination hash, clears obsolete resolution/deviation evidence and reopens the linked issue.
- Updates to linked mutable resources touch affected matrix items so previously captured release evidence cannot remain fresh by timestamp accident.
- Release coordination capture now refuses any project containing an open/coordinating item or a stale linked-resource baseline.

## Live workspace

`/app/coordination` is now an authenticated operating console rather than a demo surface. It provides:

- project-scoped cross-discipline item creation;
- current CDE/project source and target resource selection;
- exact captured/current hash visibility;
- stale-baseline KPI and per-item warning state;
- governed `Re-baseline + Reopen` recovery;
- evidence-backed resolution;
- exact-hash deviation approval requests and acceptance;
- owner reassignment from active project membership;
- append-only coordination governance ledger;
- direct handoff to the approvals workspace.

When a linked resource becomes stale, Start Coordinating, Resolve, deviation request/acceptance and ordinary reopen controls are suppressed until the item is re-baselined.

## Release Assurance coupling

Build Pack 28 remains the final release authority. Pack 29 strengthens one of its source evidence streams:

1. open or coordinating matrix items block release capture;
2. resolved/deviation items with changed linked resource hashes also block release capture;
3. only a fully current coordination matrix can be captured as release evidence;
4. subsequent linked-resource mutation invalidates the freshness window of previously captured coordination evidence.

This prevents a package from being issued on the strength of coordination that was completed against an obsolete drawing, model, truth record, requirement, design option or release package.

## Database and security verification

Production Supabase migrations:

- `0046_coordination_matrix_runtime.sql`
- `0047_coordination_resource_freshness.sql`

Production migration history records both `coordination_matrix_runtime` and `coordination_resource_freshness`.

Verification checkpoint:

- Supabase project status: `ACTIVE_HEALTHY`
- security advisor: zero findings after both migrations
- governed raise, transition and refresh RPCs: granted to `authenticated`
- refresh and transition RPCs: `SECURITY INVOKER`
- matrix/event tables: live and RLS-protected
- current production data: zero coordination items/events, ready for first governed project use

The remaining performance-advisor notices are the pre-existing platform backlog plus expected unused-index notices on newly activated empty coordination tables; Pack 29 introduced no new RLS planner warning.

## Deployment gate

The Pack 29 branch is required to pass the same promotion discipline as prior packs: exact-head Vercel preview READY, GitHub CI green on dependency/security/migration validation, TypeScript, tests and production build, merge to `main`, then confirmation of the production deployment on the merged SHA.
