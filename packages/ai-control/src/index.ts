export type ModelProvider = "openai" | "anthropic" | "google" | "azure_openai" | "local" | string;
export type AgentCriticality = "C0" | "C1" | "C2" | "C3" | "C4";
export type AgentRunStatus = "queued" | "running" | "awaiting_approval" | "succeeded" | "failed" | "cancelled";
export type PromotionStage = "observation" | "evidence" | "privacy_review" | "expert_review" | "benchmark" | "shadow" | "controlled_production" | "retired";

export interface ModelProfile {
  id:string;
  provider:ModelProvider;
  model:string;
  purpose:string;
  enabled:boolean;
  maxCriticality:AgentCriticality;
  supportsStructuredOutput:boolean;
  supportsVision:boolean;
  supportsToolUse:boolean;
  dataResidency?:string;
  costPolicy?:Record<string,number>;
  latencyTargetMs?:number;
  evaluationThreshold?:number;
}

export interface PromptVersion {
  id:string;
  agentCode:string;
  version:number;
  template:string;
  outputSchemaRef?:string;
  systemPolicyRef?:string;
  status:"draft" | "review" | "active" | "retired";
  createdBy:string;
  approvedBy?:string;
  createdAt:string;
}

export interface AgentDefinition {
  code:string;
  name:string;
  purpose:string;
  maxCriticality:AgentCriticality;
  allowedAutonomy:"human_only" | "ai_advisory" | "ai_draft" | "execute_after_approval" | "bounded_autonomous";
  allowedTools:string[];
  prohibitedActions:string[];
  noHallucinationZones:string[];
  requiresGrounding:boolean;
  requiresHumanApprovalFor:string[];
}

export interface AgentRun {
  id:string;
  agentCode:string;
  projectId?:string;
  modelProfileId:string;
  promptVersionId:string;
  status:AgentRunStatus;
  criticality:AgentCriticality;
  inputRef?:string;
  outputRef?:string;
  evidenceRefs:string[];
  toolCalls:Record<string,unknown>[];
  tokenUsage?:{input:number;output:number};
  estimatedCost?:number;
  startedAt?:string;
  finishedAt?:string;
  correlationId:string;
}

export interface EvaluationCase {
  id:string;
  suiteCode:string;
  name:string;
  input:Record<string,unknown>;
  expectedAssertions:Record<string,unknown>[];
  criticality:AgentCriticality;
  active:boolean;
}

export interface EvaluationResult {
  id:string;
  caseId:string;
  modelProfileId:string;
  promptVersionId:string;
  score:number;
  passed:boolean;
  findings:string[];
  runAt:string;
}

export interface LearningCandidate {
  id:string;
  sourceProjectId?:string;
  sourceType:string;
  sourceRef:string;
  stage:PromotionStage;
  privacyState:"pending" | "approved" | "rejected";
  evidenceQuality:"low" | "medium" | "high";
  benchmarkDelta?:number;
  expertReviewers:string[];
  rollbackRef?:string;
}

export interface GroundedAnswer {
  answer:string;
  citations:{label:string;resourceType:string;resourceId:string;version?:string}[];
  confidence:"A" | "B" | "C" | "D";
  unresolvedQuestions:string[];
  criticality:AgentCriticality;
}

export function agentMayRun(definition:AgentDefinition, criticality:AgentCriticality){
  const rank={C0:0,C1:1,C2:2,C3:3,C4:4};
  return rank[criticality] <= rank[definition.maxCriticality];
}

export function groundedAnswerIsPublishable(answer:GroundedAnswer){
  if(answer.criticality === "C3" || answer.criticality === "C4") return false;
  if(answer.confidence === "D") return false;
  return answer.citations.length > 0 && answer.unresolvedQuestions.length === 0;
}
