export type IntegrationCategory =
  | "dns"
  | "email"
  | "payments"
  | "whatsapp"
  | "sms"
  | "ai"
  | "storage"
  | "maps"
  | "esign"
  | "analytics"
  | "bim_cad"
  | "accounting";

export type IntegrationEnvironment = "sandbox" | "production";
export type IntegrationStatus = "not_configured" | "configured" | "verified" | "degraded" | "disabled";

export interface IntegrationProviderDefinition {
  key: string;
  name: string;
  category: IntegrationCategory;
  supportsSandbox: boolean;
  webhookCapable: boolean;
  documentationUrl?: string;
  credentialFields: Array<{
    key: string;
    label: string;
    secret: boolean;
    required: boolean;
  }>;
}

export interface IntegrationInstance {
  id: string;
  organisationId: string;
  providerKey: string;
  environment: IntegrationEnvironment;
  status: IntegrationStatus;
  enabled: boolean;
  config: Record<string, string | number | boolean | null>;
  secretRefs: Record<string, string>;
  verifiedAt?: string;
  lastHealthCheckAt?: string;
}

export interface OutboundMessage {
  idempotencyKey: string;
  channel: "email" | "whatsapp" | "sms";
  to: string;
  templateKey?: string;
  subject?: string;
  body?: string;
  variables?: Record<string, string | number | boolean>;
}

export interface MessageDeliveryResult {
  provider: string;
  providerMessageId?: string;
  accepted: boolean;
  status: "queued" | "sent" | "delivered" | "failed" | "unknown";
  raw?: unknown;
}

export interface MessagingAdapter {
  send(message: OutboundMessage): Promise<MessageDeliveryResult>;
  verifyWebhook?(headers: Headers, rawBody: string): Promise<boolean>;
}

export interface PaymentIntentInput {
  idempotencyKey: string;
  amountMinor: number;
  currency: string;
  reference: string;
  customer?: { name?: string; email?: string; phone?: string };
  metadata?: Record<string, string>;
}

export interface PaymentIntentResult {
  provider: string;
  providerPaymentId: string;
  status: "created" | "authorized" | "captured" | "failed";
  checkoutUrl?: string;
}

export interface PaymentAdapter {
  createPaymentIntent(input: PaymentIntentInput): Promise<PaymentIntentResult>;
  verifyWebhook(headers: Headers, rawBody: string): Promise<boolean>;
}

export interface DnsRecordInput {
  type: "A" | "AAAA" | "CNAME" | "TXT" | "MX" | "CAA";
  name: string;
  value: string;
  ttl?: number;
  priority?: number;
}

export interface DnsAdapter {
  listRecords(domain: string): Promise<DnsRecordInput[]>;
  upsertRecord(domain: string, record: DnsRecordInput): Promise<void>;
  deleteRecord(domain: string, record: DnsRecordInput): Promise<void>;
}

export interface AiModelProfile {
  providerKey: string;
  model: string;
  purpose: "orchestration" | "vision" | "reasoning" | "speech" | "embedding" | "rendering" | "document" | "code";
  enabled: boolean;
  maxAutonomy: "human_only" | "ai_advisory" | "ai_draft" | "execute_after_approval" | "bounded_autonomous";
  allowedCriticalities: Array<"C0" | "C1" | "C2" | "C3" | "C4">;
}

export const CORE_PROVIDER_CATALOG: IntegrationProviderDefinition[] = [
  {
    key: "godaddy",
    name: "GoDaddy",
    category: "dns",
    supportsSandbox: false,
    webhookCapable: false,
    credentialFields: [
      { key: "apiKey", label: "API Key", secret: true, required: true },
      { key: "apiSecret", label: "API Secret", secret: true, required: true }
    ]
  },
  {
    key: "resend",
    name: "Resend",
    category: "email",
    supportsSandbox: true,
    webhookCapable: true,
    credentialFields: [
      { key: "apiKey", label: "API Key", secret: true, required: true },
      { key: "fromDomain", label: "Verified Sending Domain", secret: false, required: true }
    ]
  },
  {
    key: "razorpay",
    name: "Razorpay",
    category: "payments",
    supportsSandbox: true,
    webhookCapable: true,
    credentialFields: [
      { key: "keyId", label: "Key ID", secret: true, required: true },
      { key: "keySecret", label: "Key Secret", secret: true, required: true },
      { key: "webhookSecret", label: "Webhook Secret", secret: true, required: true }
    ]
  },
  {
    key: "aisensy",
    name: "AiSensy",
    category: "whatsapp",
    supportsSandbox: false,
    webhookCapable: true,
    credentialFields: [
      { key: "apiKey", label: "API Key", secret: true, required: true },
      { key: "campaignNamespace", label: "Campaign / Template Namespace", secret: false, required: false }
    ]
  },
  {
    key: "fast2sms",
    name: "Fast2SMS",
    category: "sms",
    supportsSandbox: false,
    webhookCapable: false,
    credentialFields: [
      { key: "apiKey", label: "API Key", secret: true, required: true },
      { key: "senderId", label: "Sender ID", secret: false, required: false }
    ]
  }
];

export function redactIntegration(instance: IntegrationInstance) {
  return {
    ...instance,
    secretRefs: Object.fromEntries(Object.keys(instance.secretRefs).map(key => [key, "••••••••"]))
  };
}
