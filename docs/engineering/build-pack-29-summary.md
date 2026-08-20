# Build Pack 29 — Governed Coordination Runtime

Build Pack 29 activates the cross-discipline coordination layer that Release Assurance depends on. Coordination is no longer represented by illustrative rows or by an empty engineering matrix. Each coordination decision is now linked to a governed issue, accountable owner, exact source/target resource baseline, resolution evidence and release impact.

## Runtime activated

- `engineering.coordination_matrix` is operated through governed RPCs rather than direct client writes.
- Raising a matrix item atomically creates its underlying coordination issue and captures the selected source/target resource hashes.
- Matrix rows now require complete source/target resource identity and non-empty captured hashes at the database constraint layer.
- Supported coordination resources are project-validated before capture and remain traceable to the source CDE/project object.
- Matrix state is constrained to `open`, `coordinating`, `resolved` and `accepted_deviation`.
- Resolution requires explicit rationale plus non-empty evidence references.
- Accepted deviations require an already-approved governed approval whose reviewed evidence hash equals the current coordination hash.
- Deviation review cannot even be requested against a stale coordination baseline.
- Matrix transitions keep the linked issue state synchronized so `/app/issues` cannot silently resolve or close coordination debt ahead of the matrix or against stale resources.
- Owner changes, state transitions, deviation requests, resolutions, reopens and re-baselines are written to the append-only coordination event ledger and audit chain.

## Resource freshness and replacement invariant

A coordination decision is valid only against the resource versions it actually reviewed.

- Source and target resource hashes are captured when the item is raised.
- `engineering.coordination_item_resources_current()` compares those captured hashes with the current linked resources.
- Positive coordination transitions fail closed when either linked baseline has changed.
- Missing or superseded resources render as unavailable/stale instead of throwing the whole coordination workspace.
- Strict mutation paths use a required-resource resolver, so missing/superseded resources can never be silently captured as a valid baseline.
- A governed re-baseline may retain the same source/target IDs and capture their new hashes, or replace one/both resources when an old baseline has been superseded.
- Re-baselining generates a new coordination hash, clears obsolete resolution/deviation evidence, reopens the linked issue, preserves historical issue links, adds links to replacement resources and writes the new snapshots to the governance ledger.
- Document-version, Project Truth, requirement, design-option, release-content and model-checksum changes touch affected matrix items so previously captured release evidence cannot remain fresh by timestamp accident.
- Release coordination capture refuses any project containing an open/coordinating item or a stale/missing linked-resource baseline.

## Live workspace

`/app/coordination` is now an authenticated operating console rather than a demo surface. It provides:

- project-scoped cross-discipline item creation;
- current CDE/project source and target resource selection;
- exact captured/current hash visibility;
- explicit unavailable/superseded resource state;
- stale-baseline KPI and per-item warning state;
- governed `Re-baseline + Reopen` recovery;
- replacement source/target selection where a baseline was superseded;
- evidence-backed resolution;
- exact-hash deviation approval requests and acceptance;
- owner reassignment from active project membership;
- append-only coordination governance ledger;
- direct handoff to the approvals workspace.

When a linked resource becomes stale, Start Coordinating, Resolve, deviation request/acceptance and ordinary reopen controls are suppressed until the item is re-baselined.

## Release Assurance coupling

Build Pack 28 remains the final release authority. Pack 29 strengthens one of its source evidence streams:

1. open or coordinating matrix items block release capture;
2. resolved/deviation items with changed, missing or superseded linked resources also block release capture;
3. only a fully current coordination matrix can be captured as release evidence;
4. subsequent linked-resource mutation invalidates the freshness window of previously captured coordination evidence.

This prevents a package from being issued on the strength of coordination that was completed against an obsolete drawing, model, truth record, requirement, design option or release package.

## Database and security verification

Production Supabase migrations:

- `0046_coordination_matrix_runtime.sql`
- `0047_coordination_resource_freshness.sql`
- `0048_coordination_rebaseline_hardening.sql`

Production migration history records `coordination_matrix_runtime`, `coordination_resource_freshness` and `coordination_rebaseline_hardening`.

Verification checkpoint:

- Supabase project status: `ACTIVE_HEALTHY`
- security advisor: zero findings after all Pack 29 migrations
- governed raise, transition, refresh and replacement re-baseline RPCs: granted to `authenticated`
- transition, refresh and replacement re-baseline RPCs: `SECURITY INVOKER`
- source/target baseline constraints: validated
- model checksum freshness trigger: active
- missing/superseded resource resolver: verified to return a soft stale snapshot for workspace display
- governed refresh-phase RLS: permits only the matrix/event/link writes needed by re-baselining
- matrix/event tables: live and RLS-protected
- current production data: zero coordination items/events, ready for first governed project use

The remaining performance-advisor notices are the pre-existing platform backlog plus expected unused-index notices on newly activated empty coordination tables; Pack 29 introduced no new RLS planner warning.

## Deployment gate

The Pack 29 branch is required to pass the same promotion discipline as prior packs: exact-head Vercel preview READY, GitHub CI green on dependency/security/migration validation, TypeScript, tests and production build, merge to `main`, then confirmation of the production deployment on the merged SHA.
