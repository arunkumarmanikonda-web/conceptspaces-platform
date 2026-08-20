export type Typology = "residential" | "hotel" | "resort" | "hospital" | "clinic" | "retail" | "mall" | "high_street" | "office" | "coworking" | "mixed_use" | "school" | "university" | "industrial" | "warehouse" | "data_center" | "parking" | "convention" | "cinema" | "restaurant" | "club" | "other";
export type SourceConfidence = "A" | "B" | "C" | "D";
export type StudyState = "draft" | "running" | "complete" | "failed" | "superseded";

export interface TypologyKnowledgePack {
  id:string;
  code:string;
  name:string;
  typology:Typology;
  version:number;
  jurisdictionScope?:string[];
  programmeCategories:string[];
  amenityPatterns:string[];
  planningPrinciples:string[];
  operationalPrinciples:string[];
  engineeringConsiderations:string[];
  sustainabilityConsiderations:string[];
  commercialDrivers:string[];
  benchmarkSources:string[];
  state:"draft" | "review" | "published" | "retired";
}

export interface ProgrammeItem {
  id:string;
  code:string;
  name:string;
  category:string;
  quantity:number;
  unitArea:number;
  unit:"sqm" | "sqft";
  netArea:number;
  grossingFactor?:number;
  grossArea?:number;
  adjacencyTags:string[];
  mandatory:boolean;
  sourceRef?:string;
  confidence:SourceConfidence;
}

export interface ProgrammeBrief {
  id:string;
  projectId:string;
  typologyPackId?:string;
  version:number;
  items:ProgrammeItem[];
  clientPriorities:string[];
  exclusions:string[];
  targetEfficiency?:number;
  targetBuiltUpArea?:number;
  budgetBand?:string;
  status:"draft" | "client_review" | "approved" | "superseded";
}

export interface ClimateContext {
  id:string;
  projectId:string;
  latitude:number;
  longitude:number;
  elevationM?:number;
  climateZone?:string;
  weatherDatasetRef?:string;
  designDryBulbC?:number;
  designWetBulbC?:number;
  annualRainfallMm?:number;
  prevailingWindDirections?:string[];
  solarExposureNotes?:string[];
  floodRiskClass?:string;
  heatRiskClass?:string;
  airQualityContext?:string;
  sourceRefs:string[];
  confidence:SourceConfidence;
}

export interface EnvironmentalStudy {
  id:string;
  projectId:string;
  studyType:"solar" | "daylight" | "shadow" | "wind" | "energy" | "thermal" | "water" | "flood" | "embodied_carbon" | "operational_carbon" | "air_quality";
  state:StudyState;
  engineRef?:string;
  engineVersion?:string;
  inputSnapshotRef:string;
  assumptions:string[];
  resultRef?:string;
  keyMetrics:Record<string,number | string | boolean>;
  evidenceRefs:string[];
  confidence:SourceConfidence;
}

export interface PrecedentPrinciple {
  id:string;
  projectId:string;
  typology:Typology;
  sourceRef:string;
  geography?:string;
  principle:string;
  rationale:string;
  transferable:boolean;
  copyingProhibited:boolean;
  evidenceRefs:string[];
}

export interface DevelopmentScenario {
  id:string;
  projectId:string;
  code:string;
  name:string;
  programmeBriefId:string;
  designOptionId?:string;
  saleableArea?:number;
  leasableArea?:number;
  builtUpArea:number;
  farConsumed?:number;
  groundCoveragePercent?:number;
  parkingCount?:number;
  capexEstimate?:number;
  revenueEstimate?:number;
  currency:string;
  durationMonths?:number;
  assumptionsRef:string;
  status:"draft" | "evaluated" | "shortlisted" | "selected" | "rejected";
}

export interface EconomicAssumption {
  id:string;
  scenarioId:string;
  category:"land" | "construction" | "professional_fees" | "statutory" | "finance" | "marketing" | "operations" | "sales" | "rent" | "absorption" | "escalation" | "tax" | "other";
  key:string;
  value:number;
  unit:string;
  sourceRef?:string;
  confidence:SourceConfidence;
  effectiveDate?:string;
}

export interface ScenarioMetrics {
  id:string;
  scenarioId:string;
  totalDevelopmentCost?:number;
  grossDevelopmentValue?:number;
  netOperatingIncome?:number;
  developmentMarginPercent?:number;
  irrPercent?:number;
  npv?:number;
  paybackMonths?:number;
  residualLandValue?:number;
  costPerBuiltUpArea?:number;
  valuePerBuiltUpArea?:number;
  sensitivityRef?:string;
  calculatedAt:string;
}

export interface ValueEngineeringOption {
  id:string;
  projectId:string;
  scenarioId?:string;
  discipline?:string;
  proposal:string;
  reason:string;
  capexImpact:number;
  opexImpact?:number;
  programmeImpactDays?:number;
  qualityImpact:"positive" | "neutral" | "negative";
  carbonImpact?:"positive" | "neutral" | "negative";
  requirementImpactRefs:string[];
  decisionState:"proposed" | "review" | "accepted" | "rejected";
}

export function calculateProgrammeAreas(items:ProgrammeItem[]){
  const netArea=items.reduce((sum,item)=>sum+item.netArea,0);
  const grossArea=items.reduce((sum,item)=>sum+(item.grossArea ?? item.netArea*(item.grossingFactor ?? 1)),0);
  return {netArea,grossArea,efficiency:grossArea>0?netArea/grossArea:0};
}

export function calculateNpv(discountRate:number,cashFlows:number[]){
  if(discountRate <= -1) throw new Error("discountRate must be greater than -1");
  return cashFlows.reduce((npv,cashFlow,index)=>npv+cashFlow/Math.pow(1+discountRate,index),0);
}

export function scenarioHasCriticalUnknowns(scenario:DevelopmentScenario, assumptions:EconomicAssumption[]){
  const scenarioAssumptions=assumptions.filter(a=>a.scenarioId===scenario.id);
  return scenarioAssumptions.some(a=>a.confidence === "D") || scenario.builtUpArea<=0 || !scenario.assumptionsRef;
}
