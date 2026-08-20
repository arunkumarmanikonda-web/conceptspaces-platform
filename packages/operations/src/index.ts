export type WorkflowState="draft"|"published"|"retired";
export type WorkflowInstanceState="queued"|"running"|"waiting"|"completed"|"failed"|"cancelled";
export type TaskState="open"|"in_progress"|"submitted"|"approved"|"rejected"|"cancelled";
export type RiskLevel="low"|"medium"|"high"|"critical";
export type ControlState="designed"|"implemented"|"tested"|"ineffective"|"retired";
export type ComplianceState="not_assessed"|"compliant"|"partial"|"non_compliant"|"not_applicable";

export interface WorkflowDefinition{
  id:string; code:string; name:string; version:number; domain:string; state:WorkflowState;
  triggerType:"manual"|"event"|"schedule"|"condition";
  steps:WorkflowStepDefinition[];
  slaMinutes?:number; escalationPolicyRef?:string;
}

export interface WorkflowStepDefinition{
  code:string; name:string; sequence:number;
  actorType:"user"|"role"|"agent"|"system"|"integration";
  actorRef?:string;
  action:string;
  makerChecker:boolean;
  requiredEvidenceTypes:string[];
  timeoutMinutes?:number;
  onSuccess?:string;
  onFailure?:string;
}

export interface WorkflowInstance{
  id:string; definitionId:string; definitionVersion:number; organisationId:string; projectId?:string;
  subjectType:string; subjectId?:string; state:WorkflowInstanceState; currentStepCode?:string;
  correlationId:string; startedAt?:string; completedAt?:string;
}

export interface WorkTask{
  id:string; workflowInstanceId?:string; organisationId:string; projectId?:string;
  title:string; taskType:string; state:TaskState; priority:"low"|"normal"|"high"|"urgent";
  assigneeUserId?:string; assigneeRoleCode?:string; dueAt?:string; slaBreached:boolean;
  makerUserId?:string; checkerUserId?:string; evidenceRefs:string[];
}

export interface MakerCheckerDecision{
  id:string; subjectType:string; subjectId:string; action:string;
  makerUserId:string; checkerUserId?:string;
  makerSubmittedAt:string; checkerDecision?:"approved"|"rejected";
  checkerReason?:string; checkerDecidedAt?:string;
}

export interface RiskRecord{
  id:string; organisationId:string; projectId?:string; code:string; title:string;
  category:string; description:string; probability:number; impact:number; inherentLevel:RiskLevel;
  ownerUserId?:string; treatment:string; residualLevel?:RiskLevel; status:"open"|"mitigating"|"accepted"|"closed";
  sourceRefs:string[]; reviewDueAt?:string;
}

export interface ControlRecord{
  id:string; code:string; name:string; domain:string; objective:string; state:ControlState;
  ownerRoleCode?:string; frequency?:string; evidenceRequired:string[];
  linkedRiskCodes:string[]; linkedObligationCodes:string[];
}

export interface ComplianceObligation{
  id:string; code:string; jurisdiction:string; authority?:string; domain:string;
  title:string; description:string; sourceRef:string; effectiveFrom:string; effectiveUntil?:string;
  applicabilityExpression?:string; ownerRoleCode?:string; evidenceRequirements:string[];
}

export interface ComplianceAssessment{
  id:string; obligationId:string; organisationId:string; projectId?:string;
  state:ComplianceState; rationale:string; evidenceRefs:string[]; assessedBy:string; assessedAt:string;
  nextReviewAt?:string;
}

export interface AuditFinding{
  id:string; auditCode:string; organisationId:string; projectId?:string;
  findingType:"observation"|"minor"|"major"|"critical"; title:string; description:string;
  controlCode?:string; obligationCode?:string; ownerUserId?:string;
  correctiveAction?:string; dueAt?:string; state:"open"|"actioned"|"verified"|"closed";
}

export interface KpiDefinition{
  id:string; code:string; name:string; domain:string; unit:string;
  direction:"higher_is_better"|"lower_is_better"|"target_band";
  target?:number; warningThreshold?:number; criticalThreshold?:number;
  calculationRef:string; refreshCadence:string;
}

export interface KpiObservation{
  id:string; kpiId:string; organisationId:string; projectId?:string;
  observedAt:string; value:number; sourceRef:string; confidence:"A"|"B"|"C"|"D";
}

export interface PlatformIncident{
  id:string; code:string; severity:"SEV0"|"SEV1"|"SEV2"|"SEV3"; title:string;
  state:"open"|"mitigating"|"resolved"|"postmortem"; service:string;
  detectedAt:string; resolvedAt?:string; ownerUserId?:string; customerImpact?:string;
  timelineRefs:string[]; rootCause?:string; correctiveActions:string[];
}

export function requiresIndependentChecker(step:WorkflowStepDefinition){
  return step.makerChecker;
}

export function riskScore(probability:number,impact:number){
  if(probability<1||probability>5||impact<1||impact>5) throw new Error("probability and impact must be 1..5");
  return probability*impact;
}

export function scoreToRiskLevel(score:number):RiskLevel{
  if(score>=20) return "critical";
  if(score>=12) return "high";
  if(score>=6) return "medium";
  return "low";
}
