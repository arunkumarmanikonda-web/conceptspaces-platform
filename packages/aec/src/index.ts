export type VerificationState = "unverified" | "source_verified" | "professionally_verified" | "authority_verified";
export type RegulatoryDisposition = "green" | "amber" | "red";
export type DesignOptionStatus = "generated" | "validated" | "shortlisted" | "client_selected" | "superseded";

export interface GeoPoint { lat:number; lng:number; elevation?:number; }
export interface BoundaryVertex { id:string; x:number; y:number; z?:number; sourceRef?:string; verification:VerificationState; }
export interface BoundaryEdge { id:string; fromVertexId:string; toVertexId:string; length?:number; bearing?:number; verification:VerificationState; }

export interface SiteGeometry {
  id:string;
  projectId:string;
  coordinateSystem?:string;
  georeferenced:boolean;
  vertices:BoundaryVertex[];
  edges:BoundaryEdge[];
  area?:number;
  unit:"m" | "ft";
  sourceType:"survey" | "cadastral" | "dwg" | "dxf" | "point_cloud" | "lidar" | "manual";
  sourceReference?:string;
  verification:VerificationState;
}

export interface SiteConstraint {
  id:string;
  projectId:string;
  code:string;
  label:string;
  value:unknown;
  unit?:string;
  sourceReference?:string;
  verification:VerificationState;
  critical:boolean;
}

export interface RegulationPack {
  id:string;
  jurisdictionCountry:string;
  jurisdictionState?:string;
  jurisdictionCity?:string;
  authority?:string;
  code:string;
  title:string;
  effectiveFrom:string;
  effectiveUntil?:string;
  supersedesPackId?:string;
  publicationStatus:"draft" | "technical_review" | "legal_review" | "published" | "retired";
}

export interface RegulatoryRule {
  id:string;
  packId:string;
  ruleCode:string;
  subject:string;
  expression?:string;
  narrative:string;
  sourceReference:string;
  effectiveFrom:string;
  disposition:RegulatoryDisposition;
  requiresProfessionalInterpretation:boolean;
}

export interface ComplianceFinding {
  id:string;
  projectId:string;
  ruleId:string;
  disposition:RegulatoryDisposition;
  status:"pass" | "fail" | "not_verified" | "requires_interpretation";
  observedValue?:unknown;
  requiredValue?:unknown;
  evidenceRefs:string[];
  explanation:string;
}

export interface DesignIntent {
  projectId:string;
  typology:string;
  optimisationMode:"commercial_yield" | "environmental" | "architecture" | "capex" | "balanced";
  programme:Record<string,unknown>;
  mandatoryRequirements:string[];
  preferences:Record<string,unknown>;
  exclusions:string[];
}

export interface DesignMetric {
  code:string;
  label:string;
  value:number | string;
  unit?:string;
  confidence:"A" | "B" | "C" | "D";
}

export interface DesignOption {
  id:string;
  projectId:string;
  branchId:string;
  name:string;
  status:DesignOptionStatus;
  generatedBy:"human" | "ai" | "hybrid";
  geometryArtifactRef?:string;
  metrics:DesignMetric[];
  complianceFindings:ComplianceFinding[];
  assumptions:string[];
  createdAt:string;
}

export interface ValidationCheck {
  code:string;
  discipline:"architecture" | "structure" | "mep" | "fire" | "interiors" | "cost" | "regulatory" | "coordination";
  criticality:"C0" | "C1" | "C2" | "C3" | "C4";
  state:"pass" | "fail" | "not_run" | "not_verified";
  evidenceRefs:string[];
  message:string;
}

export interface ReleaseSafetyCase {
  releaseId:string;
  projectId:string;
  packageType:string;
  checks:ValidationCheck[];
  unresolvedCriticalDefects:number;
  professionalApprovals:string[];
  clientApprovalRef?:string;
  contentHash?:string;
  state:"draft" | "blocked" | "ready_for_review" | "approved" | "issued";
}

export function canIssueRelease(safetyCase: ReleaseSafetyCase){
  if(safetyCase.unresolvedCriticalDefects > 0) return false;
  if(safetyCase.checks.some(c => (c.criticality === "C3" || c.criticality === "C4") && c.state !== "pass")) return false;
  return safetyCase.state === "approved" && safetyCase.professionalApprovals.length > 0;
}
