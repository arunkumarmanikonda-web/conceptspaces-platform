# Build Pack 28 — Release Assurance Runtime

## Objective

Activate final package release governance as a distinct, fail-closed safety layer. Engineering validation may produce release-eligible evidence, but it must never itself issue a package.

## Delivered

### Governed release objects

Migrations `0042`–`0044` activate and harden:

- package release gates with explicit criticality and required evidence policy;
- exact-content-hash release safety cases;
- release evidence bound to both a safety case and the exact package hash;
- package-level professional reviews with credential identity and exact reviewed hash;
- gate- and case-scoped release exceptions;
- controlled approval and issue timestamps and actors;
- current-evidence evaluation state.

All browser mutation paths run through `SECURITY INVOKER` RPCs and RLS phase guards. A narrow credential-validation helper returns only whether a reviewer credential remains current and discipline-compatible; raw third-party credential records remain protected by their existing RLS boundary.

### Release-gate policy

`create_release_gate(...)` requires:

- project-management authority;
- valid C0–C4 criticality;
- a non-empty, duplicate-free evidence policy;
- `document_hash` for every release gate;
- `professional_approval` for every C3/C4 release gate.

A gate begins `not_ready` and cannot be released by direct browser table mutation.

### Exact-hash safety cases

`create_release_safety_case(...)` requires package type, package reference and content hash. It automatically creates the package `document_hash` evidence and resets the gate to `not_ready`.

A changed package hash is a changed release object. Existing approvals are not transferable to changed content.

### Source-bound evidence capture

Build Pack 28 avoids copy/paste evidence claims by adding controlled capture paths:

- `capture_release_truth_snapshot(...)` hashes the current non-superseded Project Truth and rejects unresolved/unverified C3/C4 truth.
- `capture_release_coordination_check(...)` hashes the current coordination matrix and rejects open/coordinating items.
- `capture_release_regulatory_check(...)` accepts only the latest completed clean REGULA run for the project and binds its result hash.
- `capture_release_engineering_check(...)` accepts only a completed calculation from a currently eligible certified engine version with a current exact-output-hash professional engineering review.
- `capture_release_client_approval(...)` binds the client approval reference to the exact package content hash.

Generic release evidence cannot be marked as passing if the database cannot verify that it is current.

### Professional package review

`review_release_package(...)` requires:

- project access;
- a current verified credential owned by the reviewer;
- discipline compatibility with the release gate;
- an accepted/rejected professional decision;
- independent review for C3/C4 when the reviewer would otherwise be the safety-case creator.

The professional approval evidence is bound permanently to the exact package content hash.

### Exceptions and zero critical escape

Release exceptions are explicit governed records. C3/C4 exceptions in `open` or `accepted` state remain blocking. “Accepted” therefore means acknowledged and tracked, not waived for release. Only `resolved` or `rejected` removes that critical release block.

### Fresh evaluation, approval and issue

`evaluate_release_safety_case(...)` checks the latest evidence for every required evidence type and counts:

- missing required evidence;
- stale, failed or unverifiable required evidence;
- unresolved C3/C4 exceptions.

The case becomes `ready_for_review` only when every required evidence item is current and the zero-critical-escape condition is satisfied. Otherwise it becomes `blocked` and any prior approval is cleared.

`approve_release_safety_case(...)` performs a fresh evaluation immediately before approval.

`issue_release_safety_case(...)` requires the case already to be approved, then performs another fresh evaluation immediately before issue. If any evidence has changed, a credential has expired, a source has become stale, or a C3/C4 exception has appeared, issue fails closed instead of relying on the earlier approval.

### Workspace activation

`/app/releases` is now a live authenticated operating surface. It supports:

- release-gate definition;
- exact-hash safety-case assembly;
- source-bound evidence capture;
- package professional review;
- fresh evaluation;
- approval and final issue;
- release-exception governance;
- current/stale evidence ledger visibility.

The previous illustrative release rows and KPI values were removed.

## Verification

- Production migrations `0042`, `0043` and `0044` applied successfully.
- Supabase security advisor returns zero findings after the Release Assurance migrations.
- Pack-28 RLS policies use transaction-local phase guards without adding new RLS init-plan warnings.
- Pack-28 foreign-key paths have covering indexes; new indexes show only expected unused-index notices while release tables remain empty.
- Vercel preview and GitHub CI must pass on the complete feature head before merge to `main`.

## Safety boundary

Release is an evidence state, not an administrative action. Neither AI output, engineering validation, professional approval nor elevated application privilege can independently release a package. Issue is permitted only for the exact package hash whose complete current evidence set survives a fresh final evaluation with zero critical escape.
