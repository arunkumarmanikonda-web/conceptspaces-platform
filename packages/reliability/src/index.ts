export type Severity = "info" | "low" | "medium" | "high" | "critical";
export type GateStatus = "pending" | "pass" | "fail" | "waived";
export type IncidentStatus = "declared" | "mitigating" | "monitoring" | "resolved" | "postmortem" | "closed";

export interface QualityGateDefinition {
  id:string; code:string; name:string; stage:"commit" | "pull_request" | "preview" | "production" | "release";
  description:string; blocking:boolean; criticalities:Array<"C0"|"C1"|"C2"|"C3"|"C4">; evidenceRequired:string[];
}

export interface QualityGateRun {
  id:string; gateCode:string; releaseRef:string; status:GateStatus; evidenceRefs:string[]; automated:boolean;
  executedAt:string; executedBy?:string; waiverId?:string; details?:Record<string,unknown>;
}

export interface TestCase {
  id:string; suite:string; code:string; title:string; type:"unit" | "integration" | "contract" | "e2e" | "security" | "performance" | "accessibility" | "restore";
  criticality:"C0"|"C1"|"C2"|"C3"|"C4"; requirementRefs:string[]; automated:boolean; expectedResult:string;
}

export interface TestExecution {
  id:string; testCaseId:string; releaseRef:string; status:"pass" | "fail" | "blocked" | "skipped"; durationMs?:number;
  evidenceRefs:string[]; errorCode?:string; executedAt:string;
}

export interface Defect {
  id:string; projectOrProductRef:string; title:string; severity:Severity; source:"test" | "production" | "security" | "user" | "audit";
  affectedRoutes:string[]; affectedCriticalities:string[]; status:"open" | "triage" | "fixing" | "verification" | "closed" | "accepted_risk";
  ownerUserId?:string; dueAt?:string; evidenceRefs:string[];
}

export interface ServiceLevelObjective {
  id:string; service:string; indicator:string; target:number; unit:"percent" | "milliseconds" | "count"; windowDays:number;
  errorBudgetPolicy:string; criticality:"C1"|"C2"|"C3"|"C4";
}

export interface SloMeasurement {
  id:string; sloId:string; windowStart:string; windowEnd:string; achieved:number; errorBudgetRemainingPercent:number; evidenceRef:string;
}

export interface Incident {
  id:string; number:string; title:string; severity:"SEV0" | "SEV1" | "SEV2" | "SEV3"; status:IncidentStatus;
  serviceRefs:string[]; startedAt:string; detectedAt:string; mitigatedAt?:string; resolvedAt?:string;
  commanderUserId?:string; customerImpact:string; regulatoryImpact?:string; timelineRefs:string[]; postmortemRef?:string;
}

export interface SecurityFinding {
  id:string; source:"sast" | "dependency" | "secret_scan" | "penetration_test" | "configuration" | "advisory";
  title:string; severity:Severity; cwe?:string; affectedComponent:string; status:"open" | "remediating" | "verified" | "accepted_risk" | "false_positive";
  detectedAt:string; dueAt?:string; ownerUserId?:string; evidenceRefs:string[]; riskAcceptanceId?:string;
}

export interface RiskAcceptance {
  id:string; findingOrDefectRef:string; rationale:string; compensatingControls:string[]; expiresAt:string;
  approvedBy:string; approvedAt:string; reviewFrequencyDays:number;
}

export interface BackupRestoreDrill {
  id:string; service:string; backupRef:string; environment:"test" | "staging"; startedAt:string; completedAt?:string;
  rpoMinutesTarget:number; rtoMinutesTarget:number; achievedRpoMinutes?:number; achievedRtoMinutes?:number;
  integrityChecks:string[]; status:"running" | "pass" | "fail"; evidenceRefs:string[];
}

export interface FeatureFlag {
  id:string; key:string; description:string; ownerDomain:string; enabled:boolean; environment:string;
  percentage?:number; allowListRefs:string[]; expiresAt?:string; killSwitch:boolean;
}

export const RELEASE_GATES:QualityGateDefinition[] = [
  {id:"gate-type",code:"TYPECHECK",name:"Type safety",stage:"pull_request",description:"All configured TypeScript workspaces compile.",blocking:true,criticalities:["C0","C1","C2","C3","C4"],evidenceRequired:["ci_run"]},
  {id:"gate-test",code:"TESTS",name:"Automated tests",stage:"pull_request",description:"Applicable automated tests pass.",blocking:true,criticalities:["C0","C1","C2","C3","C4"],evidenceRequired:["test_report"]},
  {id:"gate-sec",code:"SECURITY",name:"Security quality",stage:"pull_request",description:"No committed secrets and no unapproved critical security finding.",blocking:true,criticalities:["C1","C2","C3","C4"],evidenceRequired:["security_scan"]},
  {id:"gate-build",code:"PROD_BUILD",name:"Production build",stage:"pull_request",description:"Production artifact builds successfully.",blocking:true,criticalities:["C0","C1","C2","C3","C4"],evidenceRequired:["build_log"]},
  {id:"gate-runtime",code:"RUNTIME_SMOKE",name:"Production smoke",stage:"production",description:"Health, readiness and critical routes respond correctly after deployment.",blocking:true,criticalities:["C1","C2","C3","C4"],evidenceRequired:["smoke_report"]}
];

export function releaseGatePassed(gate:QualityGateRun){ return gate.status === "pass" || gate.status === "waived"; }
export function canAcceptCriticalRisk(acceptance:RiskAcceptance, now=new Date()){
  return new Date(acceptance.expiresAt).getTime() > now.getTime() && acceptance.compensatingControls.length > 0 && !!acceptance.approvedBy;
}
export function backupDrillPasses(drill:BackupRestoreDrill){
  return drill.status === "pass" && drill.achievedRpoMinutes !== undefined && drill.achievedRtoMinutes !== undefined && drill.achievedRpoMinutes <= drill.rpoMinutesTarget && drill.achievedRtoMinutes <= drill.rtoMinutesTarget;
}
