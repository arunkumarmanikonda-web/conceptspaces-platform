export type Criticality = "C0" | "C1" | "C2" | "C3" | "C4";
export type Confidence = "A" | "B" | "C" | "D";
export type CompilerStage = "project_truth" | "regulatory_context" | "programme" | "feasibility" | "option_generation" | "architecture" | "structure" | "mepf" | "interiors" | "quantity_cost" | "coordination" | "assurance";
export type CompilationStatus = "queued" | "running" | "blocked" | "awaiting_review" | "completed" | "failed" | "superseded";

export interface IntentCommand {
  id:string; projectId:string; inputMode:"text" | "voice" | "sketch" | "markup"; rawInputRef:string;
  interpretedIntent:Record<string,unknown>; targetObjectRefs:string[]; constraints:string[]; ambiguityQuestions:string[];
  confidence:Confidence; interpretedBy:string; approvedBy?:string; createdAt:string;
}

export interface CompilerInputSnapshot {
  id:string; projectId:string; branchId:string; projectTruthHash:string; regulationHash:string; programmeHash:string;
  requirementHash:string; designStateHash?:string; costStateHash?:string; climateStateHash?:string; capturedAt:string;
  sourceRefs:string[];
}

export interface CompilerStageRun {
  id:string; compilationRunId:string; stage:CompilerStage; status:CompilationStatus; criticality:Criticality;
  engineRefs:string[]; agentRunRefs:string[]; inputHash:string; outputHash?:string; evidenceRefs:string[];
  assumptions:string[]; validationFindingRefs:string[]; startedAt?:string; completedAt?:string;
}

export interface CompilationRun {
  id:string; projectId:string; branchId:string; inputSnapshotId:string; objective:string; status:CompilationStatus;
  stages:CompilerStageRun[]; requestedBy:string; createdAt:string; completedAt?:string; finalArtifactRefs:string[];
}

export interface ParetoCandidate {
  id:string; compilationRunId:string; optionId:string; objectiveMetrics:Record<string,number>;
  dominated:boolean; constraintViolations:string[]; complianceState:"pass" | "conditional" | "fail" | "not_verified";
  humanShortlisted:boolean;
}

export interface ProjectBranch {
  id:string; projectId:string; name:string; parentBranchId?:string; parentCommitHash?:string; headCommitHash:string;
  purpose:string; status:"active" | "merged" | "abandoned" | "frozen"; createdBy:string; createdAt:string;
}

export interface ProjectCommit {
  id:string; projectId:string; branchId:string; parentCommitHashes:string[]; contentHash:string; message:string;
  changedObjectRefs:string[]; authorType:"human" | "ai" | "hybrid"; authorRef:string; createdAt:string;
}

export interface ChangeImpact {
  id:string; projectId:string; changeRef:string; sourceObjectRefs:string[]; affectedRequirements:string[];
  affectedRules:string[]; affectedDisciplines:string[]; affectedDocuments:string[]; affectedModelObjects:string[];
  affectedBoqLines:string[]; affectedContracts:string[]; estimatedCostDelta?:number; estimatedScheduleDeltaDays?:number;
  decisionReversalCost?:number; criticality:Criticality; confidence:Confidence; analysisEvidenceRefs:string[];
}

export interface DesignLintFinding {
  id:string; projectId:string; branchId:string; ruleCode:string; discipline:string; title:string; message:string;
  severity:"info" | "warning" | "error" | "critical"; criticality:Criticality; objectRefs:string[];
  sourceRef:string; status:"open" | "accepted" | "fixed" | "false_positive"; waiverRef?:string;
}

export interface AdversarialReview {
  id:string; projectId:string; resourceRef:string; reviewType:"design_council" | "red_team" | "constructability" | "operability" | "maintainability";
  reviewerAgentRefs:string[]; humanReviewerRefs:string[]; attackQuestions:string[]; findings:string[];
  unresolvedCriticalFindings:number; evidenceRefs:string[]; status:"running" | "review_required" | "accepted" | "rejected";
}

export interface OutcomeSignal {
  id:string; projectId:string; signalType:"client_approval" | "design_change" | "coordination_issue" | "site_ncr" | "cost_variance" | "schedule_variance" | "energy_outcome" | "maintenance_outcome" | "post_occupancy";
  sourceRef:string; value:Record<string,unknown>; confidence:Confidence; privacyState:"pending" | "approved" | "excluded"; capturedAt:string;
}

export interface DesignGenomeCandidate {
  id:string; patternCode:string; sourceSignalRefs:string[]; proposedPrinciple:string; applicableTypologies:string[];
  applicableClimates:string[]; stage:"observation" | "evidence" | "privacy_review" | "expert_review" | "benchmark" | "shadow" | "controlled_production" | "retired";
  evidenceScore:number; expertReviewerRefs:string[]; benchmarkRefs:string[]; rollbackRef?:string; promotedAt?:string;
}

export interface ProjectAnswer {
  answer:string; sourceRefs:string[]; sourceVersions:string[]; confidence:Confidence; criticality:Criticality;
  unresolvedQuestions:string[]; generatedAt:string;
}

export function intentReadyForExecution(intent:IntentCommand, criticality:Criticality){
  if(intent.confidence === "D" || intent.ambiguityQuestions.length>0) return false;
  if((criticality === "C3" || criticality === "C4") && !intent.approvedBy) return false;
  return true;
}

export function compilationCanComplete(run:CompilationRun){
  return run.stages.every(stage=>stage.status === "completed" && !!stage.outputHash && (stage.criticality === "C0" || stage.evidenceRefs.length>0));
}

export function adversarialReviewCanPass(review:AdversarialReview){
  return review.status === "accepted" && review.unresolvedCriticalFindings === 0 && review.evidenceRefs.length>0;
}

export function designGenomeCanPromote(candidate:DesignGenomeCandidate){
  return candidate.stage === "shadow" && candidate.evidenceScore >= 0.8 && candidate.expertReviewerRefs.length>0 && candidate.benchmarkRefs.length>0 && !!candidate.rollbackRef;
}

export function projectAnswerCanBeReliedOn(answer:ProjectAnswer){
  if(answer.confidence === "D" || answer.sourceRefs.length===0 || answer.unresolvedQuestions.length>0) return false;
  return answer.criticality !== "C4";
}
