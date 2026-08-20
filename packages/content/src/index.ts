export type ContentStatus = "draft" | "review" | "approved" | "published" | "archived";
export type ContentType = "public_page" | "product_page" | "help_article" | "knowledge_article" | "seo_landing" | "legal_notice" | "email_template";
export type TemplateKind = "proposal" | "contract" | "client_presentation" | "design_report" | "feasibility_report" | "drawing_cover" | "drawing_register" | "transmittal" | "meeting_minutes" | "invoice" | "progress_report" | "handover_pack";
export type ArtifactFormat = "pdf" | "docx" | "xlsx" | "pptx" | "html" | "json" | "csv" | "zip";
export type GenerationStatus = "queued" | "running" | "completed" | "failed" | "cancelled";
export type ArtifactStatus = "draft" | "for_review" | "approved" | "issued" | "superseded" | "withdrawn";

export interface ContentEntry {
  id:string;
  organisationId:string;
  key:string;
  type:ContentType;
  locale:string;
  title:string;
  slug?:string;
  status:ContentStatus;
  currentVersion:number;
  seo?:{title?:string;description?:string;canonical?:string;robots?:string;structuredData?:Record<string,unknown>};
  ownerUserId?:string;
}

export interface ContentVersion {
  id:string;
  contentEntryId:string;
  version:number;
  body:Record<string,unknown>;
  sourceRefs:string[];
  changeReason?:string;
  createdBy:string;
  approvedBy?:string;
  createdAt:string;
  approvedAt?:string;
}

export interface BrandProfile {
  id:string;
  organisationId:string;
  name:string;
  logoAssetRef:string;
  palette:Record<string,string>;
  typography:Record<string,string>;
  footerText?:string;
  legalEntityName?:string;
  website?:string;
}

export interface DocumentTemplate {
  id:string;
  organisationId:string;
  code:string;
  name:string;
  kind:TemplateKind;
  outputFormats:ArtifactFormat[];
  requiredDataPaths:string[];
  currentVersion:number;
  active:boolean;
}

export interface TemplateVersion {
  id:string;
  templateId:string;
  version:number;
  schemaVersion:string;
  templateRef:string;
  checksum:string;
  requiredDataPaths:string[];
  locked:boolean;
  createdBy:string;
  approvedBy?:string;
  createdAt:string;
}

export interface ProjectReportSnapshot {
  id:string;
  projectId:string;
  reportType:string;
  asOf:string;
  projectTruthHash:string;
  requirementSnapshotHash?:string;
  regulatorySnapshotHash?:string;
  commercialSnapshotHash?:string;
  documentSnapshotHash?:string;
  sourceRefs:string[];
  createdBy:string;
}

export interface GenerationJob {
  id:string;
  organisationId:string;
  projectId?:string;
  templateVersionId:string;
  format:ArtifactFormat;
  status:GenerationStatus;
  snapshotId?:string;
  inputHash:string;
  outputHash?:string;
  requestedBy:string;
  errorCode?:string;
  createdAt:string;
  completedAt?:string;
}

export interface GeneratedArtifact {
  id:string;
  generationJobId:string;
  projectId?:string;
  title:string;
  format:ArtifactFormat;
  objectRef:string;
  checksum:string;
  status:ArtifactStatus;
  revision:string;
  sourceSnapshotId?:string;
  templateVersionId:string;
  issuedBy?:string;
  issuedAt?:string;
}

export interface PublicationSetItem {
  artifactId:string;
  purpose:"information" | "review" | "approval" | "tender" | "construction" | "record" | "handover";
  sequence:number;
}

export interface PublicationSet {
  id:string;
  projectId:string;
  number:string;
  title:string;
  revision:string;
  items:PublicationSetItem[];
  status:"draft" | "for_review" | "approved" | "issued" | "superseded";
  approvedBy?:string;
  issuedBy?:string;
  issuedAt?:string;
}

export function canPublishContent(entry:ContentEntry, version?:ContentVersion){
  return entry.status === "approved" && !!version?.approvedBy && version.version === entry.currentVersion;
}

export function templateVersionCanGenerate(version:TemplateVersion){
  return version.locked && !!version.approvedBy && version.requiredDataPaths.length > 0 && version.checksum.length > 0;
}

export function artifactCanIssue(artifact:GeneratedArtifact, job:GenerationJob, unresolvedCriticalDefects:number){
  if(job.status !== "completed" || !job.outputHash) return false;
  if(artifact.checksum !== job.outputHash) return false;
  if(artifact.status !== "approved") return false;
  return unresolvedCriticalDefects === 0;
}
