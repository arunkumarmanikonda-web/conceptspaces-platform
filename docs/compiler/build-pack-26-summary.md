# Build Pack 26 — Governed Design Genome™ Runtime

## Objective

Convert the existing Design Genome schema and learning standard into an executable, human-governed learning runtime without allowing autonomous self-training or direct promotion from one project outcome.

## Delivered

### Database runtime

Migrations `0037`–`0039` add and harden:

- `public.design_genome_stage_events` as the learning-transition evidence ledger.
- `record_outcome_signal(...)` for project-authorised outcome capture.
- `set_outcome_signal_privacy(...)` for platform-admin privacy classification.
- `propose_design_genome_candidate(...)` for platform-admin learning observations.
- `advance_design_genome_candidate(...)` for sequential governed promotion.
- `list_learning_workspace()` for authenticated workspace state.
- transaction-local RLS mutation phases so browser table writes cannot bypass governed RPC paths.
- covering indexes and RLS query-plan optimisation for the new learning runtime.

### Promotion invariants

A candidate may progress only through:

`observation → evidence → privacy_review → expert_review → benchmark → shadow → controlled_production`

Retirement is permitted as a terminal state.

The database rejects:

- stage skipping;
- Evidence promotion without outcomes from at least two distinct projects;
- Expert Review before every source signal is privacy-approved;
- Benchmark promotion without expert-review references;
- Shadow promotion without benchmark evidence and a measurable evidence score;
- Controlled Production without expert evidence, benchmark evidence and a rollback reference;
- promotion of a retired candidate.

## Workspace activation

`/app/learning` is now a live authenticated operating surface. It supports:

- project outcome evidence capture;
- signal confidence and source references;
- platform-admin privacy approval/exclusion;
- evidence selection for a proposed reusable principle;
- Design Genome candidate creation at Observation;
- sequential stage promotion with stage-specific evidence fields;
- human retirement of candidates;
- live pipeline counts and governance state.

Project teams can contribute project-scoped evidence where they have management authority. Reusable learning promotion remains a platform-admin action.

## Verification

- Supabase production migrations applied successfully.
- Supabase security advisor returned zero security findings after RPC hardening.
- The new RPCs use `SECURITY INVOKER` and RLS-governed mutation phases.
- Build Pack 26-specific performance findings were addressed with an actor FK index and init-plan-safe RLS expressions.
- Vercel preview for the complete UI branch built successfully with Next.js/Turbopack.

## Safety boundary

Design Genome is a controlled knowledge-promotion system, not an autonomous training loop. Project outcomes remain evidence until they pass the required privacy, expert, benchmark and shadow gates. Controlled Production remains reversible and does not grant autonomous engineering release authority.
