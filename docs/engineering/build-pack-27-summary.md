# Build Pack 27 — Engineering Verification & Validation Runtime

## Objective

Activate the engineering trust layer without representing generative text or unverified arithmetic as engineering truth. Build Pack 27 governs engine identity, benchmark evidence, calculation provenance and professional accountability.

## Delivered

### Engine registry and certification

Migrations `0040` and `0041` add and harden:

- `engineering.engine_governance_events` for append-only registry and certification decisions.
- `register_engine_version(...)` for disabled, uncertified engine-version registration.
- `add_engine_benchmark_case(...)` and `record_engine_benchmark_result(...)` for reproducible benchmark evidence.
- `set_engine_certification(...)` for controlled certification and enablement.
- indexed current-version benchmark lookup and exact-hash professional review lookup.
- RLS mutation phases so direct authenticated table writes cannot bypass governed RPC paths.

Conditional or full certification requires checksum/build identity, supported standards and unit systems, an active benchmark suite, a latest passing result for every active benchmark at the exact engine version, and benchmark criticality coverage at least equal to the requested maximum. Conditional approval is capped at C2.

### Project engineering evidence

- `register_mep_system(...)` records project-authorised MEPF, ELV, BMS and vertical-transport criteria.
- `record_engineering_calculation(...)` records immutable provenance from an already executed engineering calculation.
- The calculation record retains exact engine/version, input snapshot reference and hash, assumptions, standards, unit system, output reference and hash, result summary and execution evidence references.
- The database rejects uncertified/disabled engines, criticality beyond engine certification, discipline mismatch, unsupported standards, unsupported or missing unit systems, missing hashes/references and missing execution evidence.

This runtime records evidence; it does not fabricate or silently execute an engineering solver.

### Professional review

`review_engineering_calculation(...)` requires:

- project access;
- a completed hashed calculation output;
- a verified credential owned by the reviewer;
- currently valid credential dates;
- discipline compatibility;
- a valid review decision;
- independent review when the project is C3/C4 and the reviewer created the calculation record.

The review is permanently bound to the exact calculation output hash. A changed output requires a new review.

### Verification state

`list_engineering_validation_workspace()` derives conservative states:

- `NOT_VERIFIED` when engine/version/criticality/output prerequisites fail;
- `AUTOMATED_VALIDATED` when calculation provenance is internally valid but exact-hash professional review is absent;
- `PROFESSIONALLY_REVIEWED` when a current verified credential has accepted the exact output hash;
- `ELIGIBLE_FOR_RELEASE_GATE` only when both engineering provenance and exact-hash professional review remain valid.

Eligibility does not itself issue or release a package. Final issue remains governed by Release Assurance.

## Workspace activation

- `/app/admin/engineering-engines` is now a live engine registry and benchmark/certification console.
- `/app/mep` is now a live project engineering verification workspace for system criteria, calculation provenance and professional review.
- Illustrative engine and MEP rows were removed from these operating screens.

## Verification

- Production migrations `0040` and `0041` applied successfully.
- Supabase security advisor returns zero findings after the new engineering runtime and hardening migration.
- New browser-callable engineering RPCs use `SECURITY INVOKER` and RLS-governed mutation phases.
- Build-Pack-specific provenance indexes were added for current benchmark evidence, exact-hash reviews and engine-version calculation history.

## Safety boundary

Engineering calculations are a no-hallucination zone. The platform may orchestrate, register and validate deterministic/physics-based execution evidence, but it must not convert plausible prose or an unverified numeric response into engineering truth. Professional authority remains explicit, credential-bound, version-bound and hash-bound.
