export type CostConfidence = "A" | "B" | "C" | "D";
export type ProcurementStatus = "draft" | "rfq" | "bid_received" | "evaluation" | "awarded" | "contracted" | "closed";
export type SiteProgressState = "not_started" | "in_progress" | "blocked" | "complete";

export interface QuantityItem {
  id:string;
  projectId:string;
  code:string;
  description:string;
  discipline:string;
  unit:string;
  quantity:number;
  source:"model" | "drawing" | "manual" | "hybrid";
  sourceReference?:string;
  confidence:CostConfidence;
}

export interface BoqLine extends QuantityItem {
  rate:number;
  currency:string;
  materialAmount:number;
  labourAmount:number;
  equipmentAmount:number;
  wastagePercent?:number;
  taxAmount?:number;
  total:number;
}

export interface CostPlan {
  id:string;
  projectId:string;
  version:number;
  stage:string;
  currency:string;
  lines:BoqLine[];
  contingencies:number;
  professionalFees:number;
  taxes:number;
  total:number;
  confidence:CostConfidence;
  basisDate:string;
}

export interface TenderPackage {
  id:string;
  projectId:string;
  packageCode:string;
  title:string;
  scopeRefs:string[];
  boqLineIds:string[];
  status:ProcurementStatus;
  invitedVendorIds:string[];
  bidDueAt?:string;
}

export interface BidLine { boqLineId:string; quantity:number; rate:number; total:number; exclusions?:string[]; }
export interface Bid {
  id:string;
  tenderPackageId:string;
  vendorId:string;
  currency:string;
  lines:BidLine[];
  commercialDeviations:string[];
  technicalDeviations:string[];
  total:number;
  submittedAt:string;
}

export interface SiteActivity {
  id:string;
  projectId:string;
  wbsCode:string;
  title:string;
  state:SiteProgressState;
  plannedStart?:string;
  plannedFinish?:string;
  actualStart?:string;
  actualFinish?:string;
  progressPercent:number;
  contractorId?:string;
  evidenceRefs:string[];
}

export interface SiteObservation {
  id:string;
  projectId:string;
  type:"progress" | "quality" | "safety" | "material" | "non_conformance" | "inspection";
  title:string;
  description:string;
  locationRef?:string;
  mediaRefs:string[];
  relatedModelObjectRefs:string[];
  criticality:"C0" | "C1" | "C2" | "C3" | "C4";
  status:"open" | "actioned" | "verified" | "closed";
  observedAt:string;
}

export interface RealityCaptureComparison {
  id:string;
  projectId:string;
  captureType:"photo" | "360" | "drone" | "point_cloud" | "lidar";
  captureRef:string;
  modelRef?:string;
  comparisonStatus:"queued" | "processing" | "review_required" | "accepted" | "failed";
  deviations:Record<string,unknown>[];
  capturedAt:string;
}

export interface AssetPassport {
  id:string;
  projectId:string;
  assetCode:string;
  assetType:string;
  manufacturer?:string;
  model?:string;
  serialNumber?:string;
  installLocation?:string;
  warrantyFrom?:string;
  warrantyUntil?:string;
  maintenancePlan?:Record<string,unknown>;
  documentRefs:string[];
  commissioningRefs:string[];
}

export function costPlanVariance(current: CostPlan, baseline: CostPlan){
  const delta=current.total-baseline.total;
  return {delta, percent: baseline.total === 0 ? 0 : (delta/baseline.total)*100};
}
