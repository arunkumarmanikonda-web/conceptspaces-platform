# Concept Spaces V1.0 Frozen Scope Completion Matrix

**Contract basis:** Concept Spaces Master Scope v4.0 and PRD + System Architecture v1.0, both dated 20 August 2026.

This matrix is an implementation and acceptance-evidence ledger. `PASS` means the required control is implemented and can be exercised in the product/runtime. `PASS WITH EXTERNAL DEPENDENCY` means the implementation is complete but the frozen P0 acceptance criterion requires real external/human evidence that must not be fabricated (for example a real cross-tenant penetration exercise, restore drill, or manual screen-reader session). `BLOCK` means an executable product defect remains.

The Master Scope requires every major feature to decompose through data, validation, authority, workflow, failure mode, audit and test/acceptance semantics. Engineering-critical capabilities additionally require source of truth, calculation method, tolerance, validation engine, benchmark dataset, professional owner, exclusions and release gate. This repository implements those concerns through forward-only migrations, RLS/RPC transaction phases, immutable hashes, audit events, governed UI workspaces, deterministic/registered engines, and release assurance.

## PRD F01–F31

| ID | Frozen PRD domain | Primary implementation evidence | P0 / authority closure | Status |
|---|---|---|---|---|
| F01 | Organisation, Identity & Access | `/app/admin/access`; core organisations/memberships/policies/professional credentials; RLS; access simulation and suspension/credential guards; 0105–0106 hardening | Tenant/project access is server-enforced; expired credentials block controlled professional authority while history/read policy remains separate. A genuine cross-tenant penetration exercise requires independent test identities/tenant data and is not fabricated. | PASS WITH EXTERNAL DEPENDENCY |
| F02 | Super Admin, Configuration & CMS | `/app/admin`, `/app/admin/system-config`, `/app/admin/cms`, `/app/admin/templates`, `/app/admin/workflows`; effective-dated configuration/version history; 0107–0108 | Business configuration publishes through maker-checker, effective time and rollback-as-new-version; workflow validation rejects invalid/dead-end definitions. | PASS |
| F03 | CRM, Sales & Remarketing | `/app/crm`; CRM/contact/opportunity/activity/attribution runtime; consent and role masking; 0105–0106 | Source/UTM attribution, merge-with-history, structured loss/remarketing and financial visibility policy are governed server-side. | PASS |
| F04 | Proposal, Scope & Commercial Negotiation | `/app/scope`, `/app/commercial`; modular scope/dependency/pricing/proposal version/counter-offer runtime; 0109 | Controlled recalculation, complete negotiation history, immutable accepted proposal and exact accepted scope payload are enforced. | PASS |
| F05 | Contract Lifecycle, Legal Execution & Obligations | `/app/commercial`; contract/clause/signature/obligation runtime; immutable execution hash and amendment workflow; 0109 | Accepted proposal reproduces contract scope/fee/milestones; failed signature cannot execute; obligations preserve clause provenance. | PASS |
| F06 | Finance, Accounting, Tax, Billing & Payments | `/app/finance`, `/app/admin/tax-rules`; journals, periods, invoices, receipts, AP, tax resolution and project P&L; 0110 | Balanced journals, maker-checker posting, closed-period protection, effective-dated tax source/version, immutable invoice history and reconciliation controls. | PASS |
| F07 | Project Creation, Activation & Stage Orchestration | `/app/projects/new`, `/app/projects/[id]`, `/app/programme`; live intake/activation/stage baseline runtime; 0111 | Activation prerequisites, lead authority, stage dependencies and future-plan change without rewriting prior baseline are enforced. | PASS |
| F08 | Site, Parcel, Survey & Project Truth | `/app/site-truth`; geometry validator, survey/fact evidence, conflict/version/blast-radius runtime; 0111 | Four-side-only boundary remains preliminary; CRS/evidence required for verified facts; geometry change invalidates affected compilation. | PASS |
| F09 | REGULA™ Regulatory Intelligence | `/app/regula`; source/rule-pack/effective-date/applicability/findings/impact runtime; 0112 | Published rule retains authority/source/clause/date; history pins rule versions; ambiguity becomes human review; new rules identify impacted projects. | PASS |
| F10 | Brief, Requirements, Typology & Precedent Intelligence | `/app/brief`, `/app/programme`; structured brief, requirement versions/traces, typology packs and precedent principles; 0113 | AI/raw brief remains draft until confirmation; approved requirement changes create downstream impact; traceability and typology-specific questionnaires are preserved. | PASS |
| F11 | Generative Architecture, Climate & Development Economics | `/app/design`, `/app/climate`, `/app/economics`, `compiler-run` Edge Function v1.1.0; design intent, fixed seed, metric-set version and deterministic candidate IDs; 0114/0114a | Same pinned inputs/seed reproduce configured deterministic benchmark; infeasible hard constraints return reasons; metrics are version-pinned; branches do not mutate approved main. | PASS |
| F12 | Architect Review, Voice-to-Design & Object Versioning | `/app/design-review`, `/app/branches`, `/app/change-impact`; change interpretation, object diff, branches/merge and immutable revisions; 0114/0114a | Structured interpretation precedes execution; object/version diffs and downstream blast radius are explicit; published revisions remain retrievable. | PASS |
| F13 | Interior Design DNA, Visualisation & Shop Drawings | `/app/interiors`; design genome/DNA, room/render/source revision, material substitution and issue controls; 0115 | DNA/revision provenance, material impact comparison, critical coordination gate and render revision metadata are enforced. | PASS |
| F14 | Structural Engineering | `/app/structure`, `/app/engineering`, `/app/admin/engineering-engines`; certified engine registry, assumptions, analyses, invalidation and safety case; 0116 | Uncertified/non-converged runs cannot support C3/C4 release; architecture change invalidates dependent analysis; input/result/checker hashes enter release evidence. | PASS |
| F15 | MEPF, ELV & Specialist Engineering | `/app/mep`, `/app/engineering`; basis/load/routing/equipment/package and professional sign-off runtime; 0117/0117a | Infeasible routing fails with reason; schedules reconcile to calculations/model; dependent routes/loads invalidate on change; C4 designated authority enforced. | PASS |
| F16 | BIM, CDE, CAD & Drawing Production | `/app/models`, `/app/documents`, `/app/coordination`; model registry/validation, CDE revisions, CAD jobs, drawings/transmittals; 0052–0053 and 0118 | Published revisions immutable/retrievable; validation failures create linked structured issues; failed adapters do not corrupt source state; issued drawing retains source model/approver. | PASS |
| F17 | QA, Design Linter, Release Safety & Proof Before Publish | `/app/design-linter`, `/app/releases`, `/app/approvals`; safety cases, findings, waivers, evidence hashes and idempotent issue; 0119 | Open critical findings block publication; waivers are explicit evidence; release reproduces rule/engine/check/input versions; duplicate evidence is idempotent. | PASS |
| F18 | QTO, BOQ, Cost, Materials & Value Engineering | `/app/cost`, `/app/admin/qto-benchmarks`; QTO/quantity/BOQ/cost/VE runtime; 0054–0055, 0122/0122a/0122b | Exact engine/version + measurement rule set requires independently approved passing golden benchmark; quantities retain object/formula/revision provenance; design changes create revisions/deltas; VE records capex/performance/lifecycle/lead-time. | PASS |
| F19 | Tendering, Procurement & Procure-to-Pay | `/app/procurement`, `/vendor/procurement`; sealed bids, opening, evaluations, award, PO, GRN and invoice match; 0056–0057 | Vendor RLS prevents competitor bid visibility pre-opening; configured opening/authority enforced; PO pins award decision; quantity/value discrepancy becomes exception before posting. | PASS |
| F20 | PMC, Construction Intelligence & Offline Site | `/app/site`; programme, diary, RFI/submittal, ITP/inspection/NCR, measurement/variation/claim and `SiteOfflineQueueClient`; 0058–0059 | Device-side queue persists while offline; sync pins downloaded package hash and fails stale changes as `STALE_SITE_PACKAGE`; field records retain evidence/revision provenance; certification respects BOQ/variation authority. | PASS |
| F21 | Reality Verification & Construction-to-Model Comparison | `/app/reality`, `/app/site`; reality capture/comparison/deviation review; 0060 | Exact model revision/checksum, coordinate/tolerance/provenance are pinned; low-confidence candidates require accountable review; verified deviations create linked issue/NCR evidence. | PASS |
| F22 | Handover, Building Passport & Digital Twin | `/app/twin`, `/app/asset-operations`, `/app/commissioning`; handover items/exceptions, asset/material passports, commissioning, Building Passport, maintenance/twin; 0061+ hardening | Building Passport re-hashes current snapshot and blocks mandatory gaps/unverified assets/incomplete commissioning; assets link system/location/docs; post-handover maintenance appends history without rewriting handover evidence. | PASS |
| F23 | AI Gateway, Self-Learning, Design Genome & Model Governance | `/app/admin/ai-control`, `/app/learning`; model/agent/prompt/evaluation/run/learning control plane; 0120–0121 | Runtime rejects unapproved/under-ceiling models; authoritative no-source state is `not_verified`; regressed model cannot promote; global learning follows privacy → expert → benchmark → shadow/controlled production gates. | PASS |
| F24 | Client Portal, Ask Your Project™ & Communications | `/client`, `/client/ask`, `/app/client-portal`, `/app/ask`; permission-aware portal/approval/payment/grounded assistant runtime | Approval recomputes current resource hash and rejects superseded submission; Ask evidence is Project Graph-grounded and client-filtered; internal notes/WIP excluded; payment/approval actions audit immediately. | PASS |
| F25 | Communication & Meeting Intelligence | `/app/communications`; communication approval/queue and meeting transcript/minutes/decision/action runtime | AI extraction is draft only; human-reviewed published minutes create linked durable objects; sensitive outbound messages require independent approval and recipient policy/consent. | PASS |
| F26 | Professional Network, Assignment & Performance | `/app/professionals`; credential/conflict/capacity eligibility, assignment replacement history and governed outcome evidence selector; 0123 | Expired/conflicted candidates excluded; replacement preserves prior history; performance source must resolve to same-project governed outcome and exact recomputed hash. | PASS |
| F27 | Risk, Early Warning, Portfolio & Executive Analytics | `/app/risk`, `/app/analytics`, command centre; governed metrics, risks/signals and role-masked portfolio runtime | Metrics are projections from source domains, not transaction truth; warning carries evidence/confidence and requires human action; sensitive finance metrics mask by role. | PASS |
| F28 | Security, Privacy, Classification & Audit | `/app/admin/security`, `/app/audit`; classification/download/export, privacy DSR, incident/audit chain and RLS policies | Restricted download requires policy/export authority and audits allow/deny; DSR completion requires verified identity/evidence; audit chain is tamper-evident. A genuine cross-tenant penetration exercise requires independent tenant identities/data and is not fabricated. | PASS WITH EXTERNAL DEPENDENCY |
| F29 | Observability, SRE, Job Control & Disaster Recovery | `/app/reliability`, `/app/incidents`; idempotent compute jobs, trace/correlation IDs, provider health, incidents and restore-drill runtime | Failed compute is isolated from project/finance state; trace links downstream work; restore drill computes pass/fail against target RPO/RTO and requires integrity/evidence. Production currently has no completed real restore-drill evidence, so that P0 acceptance proof remains external. | PASS WITH EXTERNAL DEPENDENCY |
| F30 | Integrations, API Platform & Data Contracts | `/app/admin/integrations`, `/app/admin/api-access`, `/app/integration-monitor`; provider secret boundary, scoped credentials, idempotent messages/jobs and schema registry | Repeated idempotent create returns same resource or conflict; revoked credential fails validation immediately; breaking change requires major schema version/deprecation path; raw provider secrets remain outside ordinary config. | PASS |
| F31 | Design System, Accessibility & Human Factors | global shell, `AccessibilityRuntime`, `accessibility.css`, `/app/admin/design-system`, separate simplified `/client`, real offline site queue; `scripts/accessibility-gate.mjs` | Source/automated accessibility contracts enforce semantic controls, skip link, focus/reduced-motion/mobile nav, no forbidden illustrative UI; form/accessibility audit runtime requires independent evidence. Frozen P0 also requires real manual keyboard/screen-reader checks. No completed real audit evidence exists yet, so human acceptance proof is explicitly external. | PASS WITH EXTERNAL DEPENDENCY |

## Master Scope A–AB coverage

The Master Scope map defines the complete product architecture as follows. Every part is represented by one or more PRD domains/runtime surfaces above.

| Part | Frozen Master Scope | Primary PRD/runtime coverage | Status |
|---|---|---|---|
| A | Product doctrine and non-negotiables | Cross-cutting Project Graph, deterministic/verified outputs, professional authority, immutable audit/release gates | PASS |
| B | Digital project foundation and Building Compiler | F07, F11, F12; Project Configuration/Truth, compiler-run v1.1.0, branches/change impact | PASS |
| C | Site intake, survey and Project Truth | F08 | PASS |
| D | India regulatory operating system - REGULA | F09 | PASS |
| E | Typology intelligence and global precedent research | F10 | PASS |
| F | Generative architecture and development economics | F11 | PASS |
| G | Architect review, voice-to-design and version control | F12 | PASS |
| H | Interior Design DNA and execution documentation | F13 | PASS |
| I | Structural engineering | F14 | PASS |
| J | MEPF/ELV and specialist engineering | F15 | PASS |
| K | BIM, CDE, CAD and open standards | F16 | PASS |
| L | Quality, validation, Proof Before Publish and Release Safety Case | F17 | PASS |
| M | Quantities, costing, materials and value engineering | F18 | PASS |
| N | Tendering, procurement and procure-to-pay | F19 | PASS |
| O | PMC, construction intelligence and reality capture | F20–F21 | PASS |
| P | Handover, digital twin and facility operations | F22 | PASS |
| Q | Self-learning, AI governance and model certification | F23 | PASS |
| R | CRM, sales, proposal and remarketing ERP | F03–F04 | PASS |
| S | Contract lifecycle and legal execution engine | F05 | PASS |
| T | India finance, accounting, tax, billing and payments | F06 | PASS |
| U | CMS, configuration, Super Admin and authority model | F01–F02 | PASS WITH EXTERNAL DEPENDENCY (cross-tenant acceptance evidence) |
| V | Client portal, communication and meeting intelligence | F24–F25 | PASS |
| W | Professional network and marketplace | F26 | PASS |
| X | Portfolio, risk, analytics and executive intelligence | F27 | PASS |
| Y | Security, privacy, SRE, DR, accessibility and non-functional requirements | F28–F29, F31 | PASS WITH EXTERNAL DEPENDENCY (penetration, real DR, manual accessibility evidence) |
| Z | Integrations, APIs, data contracts and global expansion | F30; versioned provider/region/jurisdiction configuration | PASS |
| AA | Brand and experience design brief | Role-specific design system, global shell, client/expert separation, responsive/accessibility contracts | PASS WITH EXTERNAL DEPENDENCY (manual accessibility evidence) |
| AB | Delivery roadmap, certification gates, KPIs and final freeze criteria | CI quality/security/accessibility/type/test/build gates; PR exact-head preview and pinned merge procedure; this matrix | PENDING FINAL RELEASE GATE |

## External acceptance evidence that must not be fabricated

1. **F01/F28 cross-tenant penetration:** the PRD requires a real Org A → Org B negative retrieval/penetration benchmark. Server-side RLS/policy enforcement is implemented; final independent penetration evidence requires controlled distinct tenant identities/data.
2. **F29 disaster recovery:** the runtime requires a real backup reference, restoration into test/staging, integrity checks and measured achieved RPO/RTO. No fake backup or evidence record is created merely to satisfy a checkbox.
3. **F31 accessibility:** the PRD explicitly requires automated accessibility **plus manual keyboard/screen-reader checks**. CI covers the automated/static source gate; a human assistive-technology session must supply the manual evidence references before an accessibility audit can be marked pass.

These are acceptance-evidence dependencies, not hidden product implementation gaps. The platform intentionally fails closed rather than manufacturing evidence.

## Final release gate

V1.0 may be declared released only after all of the following are true for one exact immutable feature head:

1. Supabase production migrations are current and Security Advisor has no blocking finding.
2. GitHub PR CI passes dependency vulnerability gate, repository/migration gate, accessibility source gate, TypeScript, tests and production build.
3. Vercel Preview is `READY` for the exact tested feature-head SHA.
4. Merge is executed with `expected_head_sha` pinned to that tested head.
5. Vercel Production is `READY` for the exact merged `main` SHA.
6. Any external acceptance evidence above remains explicitly recorded as external rather than silently converted to PASS.

Until those release proofs are recorded, Master Scope Part AB remains `PENDING FINAL RELEASE GATE`.