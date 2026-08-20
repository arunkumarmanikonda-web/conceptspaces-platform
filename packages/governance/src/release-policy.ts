import type { AuthorityContext, Criticality, ReleaseEvidence, ReleaseGate } from "@conceptspaces/domain";

export interface ReleasePolicyResult {
  allowed: boolean;
  blockers: string[];
  warnings: string[];
}

const requiredPermissionForCriticality: Record<Criticality, string[]> = {
  C0: ["release.review"],
  C1: ["release.review"],
  C2: ["release.approve"],
  C3: ["release.approve", "discipline.signoff"],
  C4: ["release.approve", "discipline.signoff", "release.issue"]
};

export function evaluateReleasePolicy(
  gate: ReleaseGate,
  evidence: ReleaseEvidence[],
  authority: AuthorityContext
): ReleasePolicyResult {
  const blockers: string[] = [];
  const warnings: string[] = [];

  if (gate.unresolvedCriticalDefects > 0) blockers.push("Unresolved critical defects exist.");
  if (gate.state !== "approved") blockers.push("Release gate is not professionally approved.");

  const passed = new Set(
    evidence.filter(item => item.gateId === gate.id && item.passed).map(item => item.evidenceType)
  );
  for (const required of gate.requiredEvidenceTypes) {
    if (!passed.has(required)) blockers.push(`Missing passing evidence: ${required}.`);
  }

  for (const permission of requiredPermissionForCriticality[gate.criticality]) {
    if (!authority.permissions.includes(permission)) blockers.push(`Missing authority: ${permission}.`);
  }

  if ((gate.criticality === "C3" || gate.criticality === "C4") && !authority.disciplineCredentials?.length) {
    blockers.push("No verified discipline credential is present for a critical release.");
  }

  if (gate.criticality === "C4") {
    warnings.push("C4 release requires human professional accountability. Autonomous AI issue is prohibited.");
  }

  return { allowed: blockers.length === 0, blockers, warnings };
}

export const NO_HALLUCINATION_ZONES = [
  "regulatory_applicability",
  "engineering_calculation",
  "quantity_takeoff",
  "boq_financial_total",
  "invoice_posting",
  "payment_release",
  "contract_execution"
] as const;

export function verificationRequired(domain: string): boolean {
  return (NO_HALLUCINATION_ZONES as readonly string[]).includes(domain);
}
