export type IntakeStatus = "draft" | "client_review" | "submitted" | "qualified" | "converted" | "cancelled";
export type IntakeStepCode = "client" | "site" | "geometry" | "regulation" | "use" | "programme" | "interiors" | "scope" | "review";
export type ScopeState = "included" | "optional" | "excluded";
export type AssignmentState = "proposed" | "invited" | "accepted" | "active" | "completed" | "declined" | "removed";

export interface ClientIdentityInput {
  fullName:string;
  organisation?:string;
  email:string;
  phone?:string;
  address?:string;
  countryCode?:string;
}

export interface SiteIntakeInput {
  projectName:string;
  latitude?:number;
  longitude?:number;
  address?:string;
  facing?:string;
  plotArea?:number;
  plotAreaUnit?:"sqm" | "sqft" | "sqyd" | "acre" | "hectare";
  surveyReference?:string;
  cadastralReference?:string;
  sitePhotoRefs:string[];
}

export interface PlotGeometryInput {
  sideLengths:number[];
  sideUnit:"m" | "ft";
  cornerCoordinates?:Array<{lat:number;lng:number}>;
  bearings?:number[];
  diagonals?:number[];
  uploadedGeometryRef?:string;
  geometrySource:"client_estimate" | "survey" | "dwg" | "dxf" | "pdf" | "cadastral" | "point_cloud" | "lidar" | "other";
}

export interface RegulationInput {
  groundCoveragePercent?:number;
  farFsi?:number;
  heightLimitM?:number;
  frontSetbackM?:number;
  rearSetbackM?:number;
  sideSetbackLeftM?:number;
  sideSetbackRightM?:number;
  parkingRequirement?:string;
  authorityReference?:string;
  sourceRefs:string[];
  clientDeclared:boolean;
}

export interface UseProgrammeInput {
  typology:string;
  subTypologies:string[];
  unitMix?:Record<string,number>;
  keyCount?:number;
  bedCount?:number;
  retailComponents?:string[];
  foodAndBeverageComponents?:string[];
  eventComponents?:string[];
  amenityRequirements:string[];
  operationalRequirements:string[];
  priorityStatements:string[];
  exclusions:string[];
}

export interface InteriorPreferenceInput {
  designLanguages:string[];
  emotionalAttributes:string[];
  preferredMaterials:string[];
  excludedMaterials:string[];
  colourDirection:string[];
  lightingDirection:string[];
  furnitureDirection:string[];
  inspirationRefs:string[];
  budgetBand?:string;
}

export interface ScopeModule {
  code:string;
  name:string;
  category:string;
  description:string;
  dependencies:string[];
  pricingModels:Array<"fixed" | "percent" | "sqft" | "per_key" | "hourly" | "retainer" | "milestone" | "subscription" | "hybrid">;
  defaultState:ScopeState;
}

export interface ScopeSelection {
  moduleCode:string;
  state:ScopeState;
  pricingModel?:string;
  quotedAmount?:number;
  currency?:string;
  notes?:string;
}

export interface ProjectIntake {
  id:string;
  organisationId?:string;
  client:ClientIdentityInput;
  site:SiteIntakeInput;
  geometry:PlotGeometryInput;
  regulation:RegulationInput;
  programme:UseProgrammeInput;
  interiors:InteriorPreferenceInput;
  scope:ScopeSelection[];
  currentStep:IntakeStepCode;
  status:IntakeStatus;
  submittedAt?:string;
}

export interface ProfessionalRoleRequirement {
  roleCode:string;
  discipline:string;
  stage:string;
  required:boolean;
  credentialTypes:string[];
  capacityHours?:number;
  locationPreference?:string;
}

export interface ProjectProfessionalAssignment {
  id:string;
  projectId:string;
  roleCode:string;
  discipline:string;
  userId?:string;
  professionalProfileId?:string;
  state:AssignmentState;
  startsAt?:string;
  endsAt?:string;
  allocationPercent?:number;
  appointmentRef?:string;
}

export interface NegotiationEvent {
  id:string;
  proposalId:string;
  version:number;
  party:"client" | "concept_spaces";
  eventType:"sent" | "counter_offer" | "scope_change" | "commercial_note" | "accepted" | "rejected" | "expired";
  amount?:number;
  currency?:string;
  scopeDelta?:Record<string,ScopeState>;
  note?:string;
  createdAt:string;
}

export interface ClientPortalAccess {
  id:string;
  contactId:string;
  projectId?:string;
  opportunityId?:string;
  role:"client_owner" | "client_representative" | "client_finance" | "client_viewer";
  status:"invited" | "active" | "suspended" | "revoked";
  invitedAt?:string;
  activatedAt?:string;
}

export interface EngagementActivation {
  id:string;
  opportunityId:string;
  proposalId:string;
  contractId?:string;
  projectId?:string;
  prerequisites:{proposalAccepted:boolean;contractExecuted:boolean;initialPaymentSatisfied:boolean;requiredKycSatisfied:boolean};
  state:"pending" | "ready" | "activated" | "blocked";
  activatedAt?:string;
}

export function geometryEvidenceIsSufficient(input:PlotGeometryInput){
  if(input.uploadedGeometryRef && input.geometrySource !== "client_estimate") return true;
  if(input.cornerCoordinates && input.cornerCoordinates.length >= 3) return true;
  if(input.sideLengths.length >= 3 && input.bearings && input.bearings.length >= input.sideLengths.length) return true;
  return false;
}

export function fourSidesAloneAreNotVerified(input:PlotGeometryInput){
  return input.sideLengths.length === 4 && !input.cornerCoordinates?.length && !input.bearings?.length && !input.diagonals?.length && !input.uploadedGeometryRef;
}

export function scopeHasDependencyConflict(selections:ScopeSelection[],catalogue:ScopeModule[]){
  const active=new Set(selections.filter(s=>s.state!=="excluded").map(s=>s.moduleCode));
  return catalogue.some(module=>active.has(module.code) && module.dependencies.some(dep=>!active.has(dep)));
}

export function engagementCanActivate(activation:EngagementActivation){
  const p=activation.prerequisites;
  return p.proposalAccepted && p.contractExecuted && p.initialPaymentSatisfied && p.requiredKycSatisfied;
}
