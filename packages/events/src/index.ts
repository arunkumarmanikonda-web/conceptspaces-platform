export type EventCriticality = "C0" | "C1" | "C2" | "C3" | "C4";
export type EventDeliveryStatus = "pending" | "processing" | "delivered" | "failed" | "dead_letter" | "cancelled";
export type WebhookReceiptStatus = "received" | "verified" | "rejected" | "duplicate" | "processed" | "failed";

export interface DomainEvent<T=Record<string,unknown>> {
  id:string;
  type:string;
  version:number;
  occurredAt:string;
  organisationId:string;
  projectId?:string;
  actorRef?:string;
  correlationId:string;
  causationId?:string;
  criticality:EventCriticality;
  payload:T;
  payloadHash:string;
}

export interface EventDefinition {
  type:string;
  latestVersion:number;
  ownerDomain:string;
  description:string;
  piiClassification:"none" | "limited" | "sensitive";
  defaultCriticality:EventCriticality;
  retentionDays:number;
  replayable:boolean;
}

export interface OutboxRecord {
  id:string;
  event:DomainEvent;
  status:"pending" | "published" | "failed";
  attemptCount:number;
  availableAt:string;
  publishedAt?:string;
  lastError?:string;
}

export interface EventSubscription {
  id:string;
  organisationId:string;
  subscriberKey:string;
  eventPattern:string;
  endpointRef?:string;
  enabled:boolean;
  maxAttempts:number;
  backoffSeconds:number[];
  allowedCriticalities:EventCriticality[];
}

export interface EventDelivery {
  id:string;
  eventId:string;
  subscriptionId:string;
  status:EventDeliveryStatus;
  attemptCount:number;
  idempotencyKey:string;
  nextAttemptAt?:string;
  deliveredAt?:string;
  responseCode?:number;
  errorCode?:string;
}

export interface WebhookReceipt {
  id:string;
  provider:string;
  providerEventId?:string;
  receivedAt:string;
  rawBodyHash:string;
  signaturePresent:boolean;
  signatureVerified:boolean;
  status:WebhookReceiptStatus;
  idempotencyKey:string;
  correlationId:string;
  errorCode?:string;
}

export interface ApiCredential {
  id:string;
  organisationId:string;
  name:string;
  prefix:string;
  secretHash:string;
  scopes:string[];
  allowedIpCidrs:string[];
  expiresAt?:string;
  revokedAt?:string;
  createdBy:string;
}

export interface ApiRequestAudit {
  id:string;
  credentialId?:string;
  organisationId?:string;
  method:string;
  route:string;
  statusCode:number;
  requestId:string;
  correlationId?:string;
  durationMs:number;
  ipHash?:string;
  userAgentHash?:string;
  occurredAt:string;
}

export interface ProviderHealth {
  providerKey:string;
  status:"not_configured" | "healthy" | "degraded" | "down" | "disabled";
  checkedAt:string;
  latencyMs?:number;
  consecutiveFailures:number;
  lastErrorCode?:string;
}

export const CORE_EVENT_DEFINITIONS:EventDefinition[] = [
  {type:"project.created",latestVersion:1,ownerDomain:"project",description:"A governed project root was created.",piiClassification:"limited",defaultCriticality:"C1",retentionDays:2555,replayable:true},
  {type:"project.truth.changed",latestVersion:1,ownerDomain:"project",description:"A project fact, assumption or decision changed.",piiClassification:"limited",defaultCriticality:"C2",retentionDays:2555,replayable:true},
  {type:"regulation.impact.detected",latestVersion:1,ownerDomain:"regula",description:"A regulatory change may affect project compliance.",piiClassification:"none",defaultCriticality:"C3",retentionDays:3650,replayable:true},
  {type:"design.release.requested",latestVersion:1,ownerDomain:"assurance",description:"A controlled release entered assurance review.",piiClassification:"limited",defaultCriticality:"C3",retentionDays:3650,replayable:true},
  {type:"design.release.issued",latestVersion:1,ownerDomain:"assurance",description:"An approved controlled release was issued.",piiClassification:"limited",defaultCriticality:"C4",retentionDays:3650,replayable:true},
  {type:"commercial.proposal.accepted",latestVersion:1,ownerDomain:"commercial",description:"A proposal was accepted by the client.",piiClassification:"limited",defaultCriticality:"C2",retentionDays:2920,replayable:true},
  {type:"finance.invoice.issued",latestVersion:1,ownerDomain:"finance",description:"A controlled invoice was issued.",piiClassification:"limited",defaultCriticality:"C2",retentionDays:3650,replayable:true},
  {type:"payment.captured",latestVersion:1,ownerDomain:"finance",description:"A payment provider confirmed capture.",piiClassification:"limited",defaultCriticality:"C2",retentionDays:3650,replayable:false},
  {type:"site.observation.created",latestVersion:1,ownerDomain:"delivery",description:"A field observation entered the project graph.",piiClassification:"limited",defaultCriticality:"C2",retentionDays:2555,replayable:true},
  {type:"risk.critical.opened",latestVersion:1,ownerDomain:"operations",description:"A critical risk was opened.",piiClassification:"limited",defaultCriticality:"C4",retentionDays:3650,replayable:true}
];

export function mayReplayEvent(definition:EventDefinition, criticality:EventCriticality){
  if(!definition.replayable) return false;
  return criticality !== "C4";
}

export function webhookCanProcess(receipt:WebhookReceipt){
  return receipt.status === "verified" && receipt.signatureVerified && !!receipt.rawBodyHash && !!receipt.idempotencyKey;
}

export function deliveryExhausted(delivery:EventDelivery, subscription:EventSubscription){
  return delivery.attemptCount >= subscription.maxAttempts && delivery.status !== "delivered";
}
