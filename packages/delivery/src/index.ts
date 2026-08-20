export type CostConfidence = "A" | "B" | "C" | "D";
export type ProcurementStatus = "draft" | "rfq" | "bid_received" | "evaluation" | "awarded" | "contracted" | "closed";
export type SiteProgressState = "not_started" | "in_progress" | "blocked" | "complete";
export type Criticality = "C0" | "C1" | "C2" | "C3" | "C4";

export interface QuantityItem {
  id:string; projectId:string; code:string; description:string; discipline:string; unit:string; quantity:number;
  source:"model" | "drawing" | "manual" | "hybrid"; sourceReference?:string; confidence:CostConfidence;
}

export interface BoqLine extends QuantityItem {
  rate:number; currency:string; materialAmount:number; labourAmount:number; equipmentAmount:number;
  wastagePercent?:number; taxAmount?:number; total:number;
}

export interface CostPlan {
  id:string; projectId:string; version:number; stage:string; currency:string; lines:BoqLine[]; contingencies:number;
  professionalFees:number; taxes:number; total:number; confidence:CostConfidence; basisDate:string;
}

export interface TenderPackage {
  id:string; projectId:string; packageCode:string; title:string; scopeRefs:string[]; boqLineIds:string[];
  status:ProcurementStatus; invitedVendorIds:string[]; bidDueAt?:string;
}

export interface BidLine { boqLineId:string; quantity:number; rate:number; total:number; exclusions?:string[]; }
export interface Bid {
  id:string; tenderPackageId:string; vendorId:string; currency:string; lines:BidLine[]; commercialDeviations:string[];
  technicalDeviations:string[]; total:number; submittedAt:string;
}

export interface SiteActivity {
  id:string; projectId:string; wbsCode:string; title:string; state:SiteProgressState; plannedStart?:string; plannedFinish?:string;
  actualStart?:string; actualFinish?:string; progressPercent:number; contractorId?:string; evidenceRefs:string[];
}

export interface SiteObservation {
  id:string; projectId:string; type:"progress" | "quality" | "safety" | "material" | "non_conformance" | "inspection";
  title:string; description:string; locationRef?:string; mediaRefs:string[]; relatedModelObjectRefs:string[];
  criticality:Criticality; status:"open" | "actioned" | "verified" | "closed"; observedAt:string;
}

export interface InspectionTestPlan {
  id:string; projectId:string; code:string; workPackage:string; activity:string; acceptanceCriteria:string[];
  referenceDocuments:string[]; holdPoints:string[]; witnessPoints:string[]; responsibleParty:string; approvedBy?:string;
  status:"draft" | "approved" | "superseded";
}

export interface InspectionRecord {
  id:string; projectId:string; itpId:string; activityRef?:string; locationRef?:string; inspectedAt:string; inspectorUserId:string;
  result:"pass" | "pass_with_comments" | "fail"; measurements:Record<string,number|string>; mediaRefs:string[];
  evidenceRefs:string[]; nonConformanceId?:string; reviewerUserId?:string; verifiedAt?:string;
}

export interface NonConformance {
  id:string; projectId:string; number:string; title:string; description:string; criticality:Criticality; locationRef?:string;
  sourceObservationId?:string; sourceInspectionId?:string; affectedObjectRefs:string[]; contractorId?:string;
  disposition:"pending" | "repair" | "replace" | "use_as_is" | "redesign"; status:"open" | "corrective_action" | "verification" | "closed";
  rootCause?:string; correctiveAction?:string; approvedDeviationBy?:string; closedBy?:string; closedAt?:string;
}

export interface SiteChange {
  id:string; projectId:string; number:string; title:string; reason:string; source:string; affectedRequirementRefs:string[];
  affectedDocumentRefs:string[]; affectedModelObjectRefs:string[]; costImpact?:number; scheduleImpactDays?:number;
  criticality:Criticality; status:"raised" | "impact_assessment" | "approval" | "approved" | "rejected" | "implemented";
  approvedBy?:string;
}

export interface ProgressClaim {
  id:string; projectId:string; contractorId:string; periodFrom:string; periodTo:string; currency:string; grossClaim:number;
  certifiedWork:number; materialOnSite:number; retention:number; deductions:number; tax:number; certifiedPayable:number;
  evidenceRefs:string[]; status:"draft" | "submitted" | "review" | "certified" | "rejected" | "paid"; certifiedBy?:string;
}

export interface RealityCaptureComparison {
  id:string; projectId:string; captureType:"photo" | "360" | "drone" | "point_cloud" | "lidar"; captureRef:string;
  modelRef?:string; coordinateSystem?:string; comparisonStatus:"queued" | "processing" | "review_required" | "accepted" | "failed";
  deviations:Record<string,unknown>[]; capturedAt:string; reviewedBy?:string; reviewedAt?:string;
}

export interface RealityDeviation {
  id:string; comparisonId:string; projectId:string; modelObjectRef?:string; locationRef?:string;
  deviationType:"position" | "dimension" | "missing" | "unexpected" | "finish" | "progress" | "quality";
  measuredValue?:number; permittedTolerance?:number; unit?:string; severity:"informational" | "minor" | "major" | "critical";
  status:"detected" | "review" | "accepted" | "ncr_raised" | "resolved"; evidenceRefs:string[]; dispositionBy?:string;
}

export interface CommissioningRecord {
  id:string; projectId:string; systemCode:string; assetCode?:string; testType:string; procedureRef:string;
  testDate:string; result:"pass" | "conditional" | "fail"; readings:Record<string,number|string>; witnessUserIds:string[];
  evidenceRefs:string[]; defects:string[]; acceptedBy?:string; acceptedAt?:string;
}

export interface AssetPassport {
  id:string; projectId:string; assetCode:string; assetType:string; manufacturer?:string; model?:string; serialNumber?:string;
  installLocation?:string; warrantyFrom?:string; warrantyUntil?:string; maintenancePlan?:Record<string,unknown>;
  documentRefs:string[]; commissioningRefs:string[]; modelObjectRef?:string; operationalStatus?:"planned" | "installed" | "commissioned" | "active" | "retired";
}

export interface MaterialPassport {
  id:string; projectId:string; materialCode:string; name:string; manufacturer?:string; productCode?:string; batchRef?:string;
  installLocations:string[]; quantity?:number; unit?:string; embodiedCarbon?:number; recycledContentPercent?:number;
  warrantyUntil?:string; maintenanceRequirements:string[]; endOfLifeRoute?:string; evidenceRefs:string[];
}

export interface TwinBinding {
  id:string; projectId:string; assetPassportId:string; providerKey:string; externalAssetRef:string;
  telemetrySchema:Record<string,string>; status:"configured" | "verified" | "degraded" | "disabled"; lastSeenAt?:string;
}

export interface MaintenanceWorkOrder {
  id:string; projectId:string; assetPassportId?:string; title:string; type:"preventive" | "predictive" | "corrective" | "statutory";
  priority:"low" | "medium" | "high" | "critical"; dueAt?:string; assigneeRef?:string;
  status:"open" | "scheduled" | "in_progress" | "verification" | "closed"; evidenceRefs:string[]; closedAt?:string;
}

export interface OfflineSiteMutation {
  localId:string; deviceId:string; actorUserId:string; projectId:string; entityType:string; operation:"create" | "update";
  payload:Record<string,unknown>; capturedAt:string; baseVersion?:number; mediaLocalRefs:string[];
}

export interface OfflineSyncResult {
  localId:string; state:"accepted" | "conflict" | "rejected"; serverId?:string; conflictReason?:string; serverVersion?:number;
}

export function costPlanVariance(current: CostPlan, baseline: CostPlan){
  const delta=current.total-baseline.total;
  return {delta, percent: baseline.total === 0 ? 0 : (delta/baseline.total)*100};
}

export function nonConformanceCanClose(ncr:NonConformance){
  if(ncr.status !== "verification") return false;
  if((ncr.disposition === "use_as_is" || ncr.disposition === "redesign") && !ncr.approvedDeviationBy) return false;
  return !!ncr.correctiveAction;
}

export function progressClaimCanCertify(claim:ProgressClaim){
  return claim.status === "review" && claim.certifiedPayable >= 0 && claim.evidenceRefs.length > 0;
}

export function assetReadyForOperations(asset:AssetPassport, commissioning:CommissioningRecord[]){
  const applicable=commissioning.filter(r=>r.assetCode===asset.assetCode);
  return applicable.length>0 && applicable.every(r=>r.result !== "fail" && !!r.acceptedBy) && asset.documentRefs.length>0;
}
