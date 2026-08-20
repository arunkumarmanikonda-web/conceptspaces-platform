export type CdeState = "work_in_progress" | "shared" | "published" | "archived";
export type DocumentStatus = "draft" | "for_review" | "for_approval" | "approved" | "issued" | "superseded" | "withdrawn";
export type IssueType = "coordination" | "design" | "rfi" | "quality" | "regulatory" | "commercial" | "site";
export type IssueStatus = "open" | "in_progress" | "answered" | "resolved" | "closed";
export type ApprovalDecision = "pending" | "approved" | "approved_with_comments" | "rejected";

export interface FileVersion {
  id:string;
  documentId:string;
  version:number;
  objectKey:string;
  mimeType:string;
  sizeBytes:number;
  checksum:string;
  createdBy:string;
  createdAt:string;
}

export interface DocumentRecord {
  id:string;
  projectId:string;
  number:string;
  title:string;
  discipline:string;
  documentType:string;
  cdeState:CdeState;
  status:DocumentStatus;
  currentVersionId?:string;
  revision:string;
  scale?:string;
  authoredBy?:string;
  checkedBy?:string;
  approvedBy?:string;
  metadata:Record<string,unknown>;
}

export interface ModelRecord {
  id:string;
  projectId:string;
  discipline:string;
  format:"IFC" | "RVT" | "DWG" | "DXF" | "BCF" | "IDS" | string;
  schemaVersion?:string;
  objectKey:string;
  checksum:string;
  coordinateSystem?:string;
  status:DocumentStatus;
  createdAt:string;
}

export interface IssueRecord {
  id:string;
  projectId:string;
  type:IssueType;
  title:string;
  description:string;
  status:IssueStatus;
  priority:"low" | "medium" | "high" | "critical";
  criticality:"C0" | "C1" | "C2" | "C3" | "C4";
  assigneeId?:string;
  dueAt?:string;
  relatedDocumentIds:string[];
  relatedModelIds:string[];
  bcfTopicRef?:string;
  createdBy:string;
  createdAt:string;
}

export interface ApprovalRequest {
  id:string;
  projectId:string;
  resourceType:"document" | "model" | "design_option" | "release" | "commercial" | "change";
  resourceId:string;
  requestedFrom:string;
  roleRequired?:string;
  criticality:"C0" | "C1" | "C2" | "C3" | "C4";
  decision:ApprovalDecision;
  comments?:string;
  requestedAt:string;
  decidedAt?:string;
}

export interface TransmittalItem {
  documentId?:string;
  modelId?:string;
  purpose:"information" | "review" | "approval" | "construction" | "record";
}

export interface Transmittal {
  id:string;
  projectId:string;
  transmittalNumber:string;
  senderId:string;
  recipientRefs:string[];
  items:TransmittalItem[];
  message?:string;
  issuedAt?:string;
  acknowledgementRequired:boolean;
}

export function canPublishDocument(document: DocumentRecord, unresolvedCriticalIssues: IssueRecord[], approval?: ApprovalRequest){
  if(document.cdeState === "published" && document.status !== "issued") return false;
  if(unresolvedCriticalIssues.some(issue => issue.status !== "closed" && (issue.criticality === "C3" || issue.criticality === "C4"))) return false;
  if(approval && approval.criticality !== "C0" && approval.decision !== "approved" && approval.decision !== "approved_with_comments") return false;
  return true;
}
