export type Discipline = "architecture" | "interiors" | "structure" | "mep" | "fire" | "vertical_transport" | "elv" | "landscape" | "sustainability";
export type CalculationStatus = "draft" | "queued" | "running" | "completed" | "failed" | "superseded";
export type EngineCertificationStatus = "uncertified" | "benchmarking" | "conditionally_approved" | "approved" | "suspended" | "retired";
export type ReviewDecision = "pending" | "accepted" | "accepted_with_comments" | "rejected";

export interface EngineeringEngine {
  id:string;
  code:string;
  name:string;
  discipline:Discipline;
  engineType:"deterministic" | "parametric" | "physics_simulation" | "rules" | "optimisation" | "adapter";
  vendor?:string;
  version:string;
  executableRef?:string;
  supportedStandards:string[];
  supportedUnits:string[];
  certificationStatus:EngineCertificationStatus;
  maximumCriticality:"C0" | "C1" | "C2" | "C3" | "C4";
  checksum?:string;
}

export interface EngineBenchmarkCase {
  id:string;
  engineId:string;
  suiteCode:string;
  name:string;
  standardReference?:string;
  inputRef:string;
  expectedResultRef:string;
  tolerance:Record<string,number>;
  criticality:"C0" | "C1" | "C2" | "C3" | "C4";
}

export interface EngineBenchmarkResult {
  id:string;
  benchmarkCaseId:string;
  engineId:string;
  engineVersion:string;
  passed:boolean;
  deviation:Record<string,number>;
  evidenceRefs:string[];
  executedAt:string;
}

export interface CalculationRun {
  id:string;
  projectId:string;
  discipline:Discipline;
  calculationType:string;
  engineId:string;
  engineVersion:string;
  status:CalculationStatus;
  inputSnapshotRef:string;
  assumptions:string[];
  standardReferences:string[];
  unitSystem:string;
  outputRef?:string;
  resultSummary?:Record<string,unknown>;
  evidenceRefs:string[];
  inputHash:string;
  outputHash?:string;
  startedAt?:string;
  finishedAt?:string;
}

export interface ProfessionalReview {
  id:string;
  projectId:string;
  resourceType:"calculation" | "drawing" | "model" | "design_package" | "material_package";
  resourceId:string;
  resourceHash:string;
  discipline:Discipline;
  reviewerUserId:string;
  credentialId:string;
  decision:ReviewDecision;
  comments?:string;
  reviewedAt?:string;
}

export interface ArchitecturePackage {
  id:string;
  projectId:string;
  stage:string;
  version:number;
  spaceProgrammeRef:string;
  circulationStrategy?:Record<string,unknown>;
  zoningStrategy?:Record<string,unknown>;
  drawingRefs:string[];
  modelRefs:string[];
  requirementCoveragePercent:number;
  designOptionId?:string;
  status:"draft" | "coordinating" | "for_review" | "approved" | "issued";
}

export interface InteriorDesignDNA {
  id:string;
  projectId:string;
  version:number;
  language:string[];
  emotionalAttributes:string[];
  spatialPrinciples:string[];
  materialPreferences:string[];
  materialExclusions:string[];
  colourDirection:string[];
  lightingDirection:string[];
  furnitureDirection:string[];
  craftReferences:string[];
  sustainabilityPreferences:string[];
  budgetBand?:string;
  sourceBriefRefs:string[];
}

export interface MaterialSelection {
  id:string;
  category:string;
  material:string;
  finish?:string;
  manufacturer?:string;
  productCode?:string;
  fireRating?:string;
  slipRating?:string;
  embodiedCarbon?:number;
  costBand?:string;
  sourceReference?:string;
  approvalState:"proposed" | "sample_requested" | "approved" | "rejected" | "substituted";
}

export interface InteriorRoomPackage {
  id:string;
  projectId:string;
  roomType:string;
  roomCode?:string;
  designDnaId:string;
  materialSelections:MaterialSelection[];
  drawingRefs:string[];
  renderRefs:string[];
  joineryRefs:string[];
  lightingRefs:string[];
  furnitureRefs:string[];
  status:"brief" | "concept" | "design_development" | "shop_drawing" | "approved" | "installed";
}

export interface StructuralScheme {
  id:string;
  projectId:string;
  version:number;
  system:string;
  materialSystem:string;
  gridStrategy?:Record<string,unknown>;
  loadAssumptions:Record<string,unknown>;
  designStandards:string[];
  analysisModelRef?:string;
  calculationRunIds:string[];
  modelRefs:string[];
  drawingRefs:string[];
  status:"concept" | "analysis" | "coordination" | "for_review" | "approved" | "issued";
}

export interface MepSystem {
  id:string;
  projectId:string;
  discipline:"mechanical" | "electrical" | "plumbing" | "fire" | "elv" | "bms" | "vertical_transport";
  systemCode:string;
  name:string;
  designCriteria:Record<string,unknown>;
  loadCalculationRunIds:string[];
  equipmentSelections:Record<string,unknown>[];
  modelRefs:string[];
  drawingRefs:string[];
  status:"criteria" | "sizing" | "coordination" | "for_review" | "approved" | "issued";
}

export interface CoordinationMatrixItem {
  id:string;
  projectId:string;
  sourceDiscipline:Discipline;
  targetDiscipline:Discipline;
  subject:string;
  requirementRef?:string;
  issueRef?:string;
  state:"open" | "coordinating" | "resolved" | "accepted_deviation";
  ownerUserId?:string;
}

export function calculationEligibleForProfessionalReview(run:CalculationRun, engine:EngineeringEngine){
  if(run.status !== "completed" || !run.outputHash) return false;
  if(engine.id !== run.engineId || engine.version !== run.engineVersion) return false;
  return engine.certificationStatus === "approved" || engine.certificationStatus === "conditionally_approved";
}

export function professionalReviewStillValid(review:ProfessionalReview, currentResourceHash:string){
  return review.decision !== "pending" && review.resourceHash === currentResourceHash;
}
