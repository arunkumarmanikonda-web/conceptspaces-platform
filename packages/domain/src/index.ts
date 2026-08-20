export type UUID = string;

export type Criticality = "C0" | "C1" | "C2" | "C3" | "C4";
export type ConfidenceGrade = "A" | "B" | "C" | "D";
export type AutonomyLevel = "human_only" | "ai_advisory" | "ai_draft" | "execute_after_approval" | "bounded_autonomous";
export type ProjectStage = "intake" | "site_truth" | "brief" | "concept" | "schematic" | "design_development" | "construction_documents" | "tender" | "construction" | "handover" | "operations";
export type TruthRecordKind = "fact" | "assumption" | "decision" | "requirement" | "constraint" | "evidence";
export type TruthRecordStatus = "draft" | "verified" | "superseded" | "rejected" | "expired";
export type ReleaseGateState = "not_ready" | "ready_for_review" | "approved" | "blocked" | "released";

export interface Organisation {
  id: UUID;
  name: string;
  code: string;
  status: "active" | "suspended";
}

export interface Project {
  id: UUID;
  organisationId: UUID;
  code: string;
  name: string;
  typology: string;
  stage: ProjectStage;
  criticality: Criticality;
  jurisdictionCountry: string;
  jurisdictionState?: string;
  jurisdictionCity?: string;
  createdAt: string;
  updatedAt: string;
}

export interface ProjectTruthRecord {
  id: UUID;
  projectId: UUID;
  kind: TruthRecordKind;
  key: string;
  value: unknown;
  unit?: string;
  sourceType?: "client" | "survey" | "authority" | "professional" | "calculation" | "system" | "contract" | "sensor";
  sourceReference?: string;
  confidence: ConfidenceGrade;
  status: TruthRecordStatus;
  criticality: Criticality;
  validFrom?: string;
  validUntil?: string;
  supersedesId?: UUID;
  createdBy: UUID;
  verifiedBy?: UUID;
  createdAt: string;
  verifiedAt?: string;
}

export interface Requirement {
  id: UUID;
  projectId: UUID;
  code: string;
  statement: string;
  category: string;
  sourceTruthRecordId?: UUID;
  acceptanceCriteria: string[];
  status: "open" | "satisfied" | "waived" | "rejected";
  criticality: Criticality;
}

export interface ReleaseEvidence {
  id: UUID;
  projectId: UUID;
  gateId: UUID;
  evidenceType: "truth_snapshot" | "regulatory_check" | "engineering_check" | "coordination_check" | "professional_approval" | "client_approval" | "document_hash";
  reference: string;
  passed: boolean;
  producedAt: string;
  producedBy: UUID;
}

export interface ReleaseGate {
  id: UUID;
  projectId: UUID;
  name: string;
  discipline: string;
  criticality: Criticality;
  state: ReleaseGateState;
  requiredEvidenceTypes: ReleaseEvidence["evidenceType"][];
  unresolvedCriticalDefects: number;
  approvedBy?: UUID;
  approvedAt?: string;
  releasedAt?: string;
}

export interface AuditEvent {
  id: UUID;
  organisationId: UUID;
  projectId?: UUID;
  actorId?: UUID;
  actorType: "user" | "agent" | "system" | "integration";
  action: string;
  resourceType: string;
  resourceId?: UUID;
  before?: unknown;
  after?: unknown;
  reason?: string;
  correlationId?: UUID;
  createdAt: string;
}

export interface AuthorityContext {
  userId: UUID;
  organisationId: UUID;
  projectId?: UUID;
  roles: string[];
  permissions: string[];
  disciplineCredentials?: string[];
}

export const CRITICAL_ACTIONS = [
  "regulation.publish",
  "engineering.approve",
  "release.issue",
  "contract.execute",
  "invoice.post",
  "payment.release",
  "rule.override"
] as const;

export function canAiActAutonomously(criticality: Criticality, autonomy: AutonomyLevel): boolean {
  if (criticality === "C4") return false;
  if (criticality === "C3") return autonomy === "ai_advisory" || autonomy === "ai_draft";
  return autonomy !== "human_only";
}

export function releaseGateCanIssue(gate: ReleaseGate, evidence: ReleaseEvidence[]): boolean {
  if (gate.unresolvedCriticalDefects > 0) return false;
  const passed = new Set(evidence.filter(item => item.gateId === gate.id && item.passed).map(item => item.evidenceType));
  return gate.requiredEvidenceTypes.every(type => passed.has(type)) && gate.state === "approved";
}
