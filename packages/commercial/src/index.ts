export type CurrencyCode = "INR" | "USD" | "EUR" | "GBP" | string;
export type LeadStatus = "new" | "qualified" | "nurture" | "won" | "lost";
export type OpportunityStage = "discovery" | "briefing" | "proposal" | "negotiation" | "contracting" | "won" | "lost";
export type ProposalStatus = "draft" | "internal_review" | "sent" | "countered" | "accepted" | "rejected" | "expired";
export type ContractStatus = "draft" | "negotiation" | "signature_pending" | "active" | "suspended" | "completed" | "terminated";
export type InvoiceStatus = "draft" | "issued" | "part_paid" | "paid" | "overdue" | "void";
export type PaymentStatus = "created" | "authorized" | "captured" | "failed" | "refunded" | "part_refunded";

export interface ContactRef {
  id: string;
  name: string;
  organisation?: string;
  email?: string;
  phone?: string;
}

export interface Lead {
  id: string;
  organisationId: string;
  source: string;
  status: LeadStatus;
  contact: ContactRef;
  projectTypology?: string;
  location?: string;
  estimatedProjectValue?: number;
  currency?: CurrencyCode;
  ownerUserId?: string;
  nextActionAt?: string;
  createdAt: string;
}

export interface Opportunity {
  id: string;
  leadId?: string;
  organisationId: string;
  contact: ContactRef;
  projectName: string;
  stage: OpportunityStage;
  probability: number;
  expectedFee?: number;
  currency: CurrencyCode;
  scopeModules: string[];
  decisionDueAt?: string;
}

export interface ProposalLine {
  id: string;
  title: string;
  scopeCode: string;
  pricingModel: "fixed" | "percent" | "sqft" | "per_key" | "hourly" | "retainer" | "milestone" | "subscription" | "hybrid";
  quantity: number;
  rate: number;
  taxCode?: string;
  amount: number;
  optional: boolean;
}

export interface Proposal {
  id: string;
  opportunityId: string;
  version: number;
  status: ProposalStatus;
  currency: CurrencyCode;
  lines: ProposalLine[];
  subtotal: number;
  tax: number;
  total: number;
  validUntil?: string;
  commercialNotes?: string[];
  clientCounterOffer?: number;
  approvedBy?: string;
}

export interface ContractObligation {
  id: string;
  party: "client" | "concept_spaces" | "consultant" | "contractor";
  obligation: string;
  dueAt?: string;
  evidenceRequired?: string;
  status: "open" | "met" | "waived" | "breached";
}

export interface Contract {
  id: string;
  proposalId: string;
  projectId?: string;
  version: number;
  status: ContractStatus;
  effectiveAt?: string;
  expiresAt?: string;
  signatureEnvelopeId?: string;
  obligations: ContractObligation[];
}

export interface InvoiceLine {
  id: string;
  description: string;
  quantity: number;
  rate: number;
  taxableAmount: number;
  gstRate?: number;
  taxAmount: number;
  total: number;
}

export interface Invoice {
  id: string;
  projectId?: string;
  contractId?: string;
  invoiceNumber: string;
  status: InvoiceStatus;
  currency: CurrencyCode;
  issueDate: string;
  dueDate: string;
  lines: InvoiceLine[];
  subtotal: number;
  tax: number;
  total: number;
  amountPaid: number;
  tdsReceivable?: number;
}

export interface PaymentTransaction {
  id: string;
  invoiceId?: string;
  provider: "razorpay" | string;
  providerPaymentId?: string;
  amount: number;
  currency: CurrencyCode;
  status: PaymentStatus;
  idempotencyKey: string;
  createdAt: string;
}

export interface CommunicationIntent {
  id: string;
  channel: "email" | "whatsapp" | "sms" | "in_app";
  recipient: string;
  templateCode: string;
  locale?: string;
  projectId?: string;
  commercialObjectType?: "lead" | "proposal" | "contract" | "invoice" | "payment";
  commercialObjectId?: string;
  payload: Record<string, unknown>;
  consentBasis?: string;
  sendAfter?: string;
}

export function proposalTotals(lines: ProposalLine[], taxRate = 0) {
  const subtotal = lines.reduce((sum, line) => sum + line.amount, 0);
  const tax = Number((subtotal * taxRate).toFixed(2));
  return { subtotal, tax, total: subtotal + tax };
}
