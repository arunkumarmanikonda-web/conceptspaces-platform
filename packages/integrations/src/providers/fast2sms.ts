import type { MessagingAdapter, MessageDeliveryResult, OutboundMessage } from "../index";

export interface Fast2SmsConfig {
  apiKey: string;
  route: "q" | "dlt_manual";
  senderId?: string;
  templateId?: string;
  entityId?: string;
  baseUrl?: string;
}

type Fast2SmsResponse = {
  return?: boolean;
  request_id?: string;
  message?: string | string[];
};

function normalizeIndianNumber(input: string): string {
  const digits = input.replace(/\D/g, "");
  if (digits.length === 12 && digits.startsWith("91")) return digits.slice(2);
  if (digits.length === 10) return digits;
  throw new Error("Fast2SMS requires a valid 10-digit Indian mobile number");
}

export class Fast2SmsAdapter implements MessagingAdapter {
  private readonly baseUrl: string;

  constructor(private readonly config: Fast2SmsConfig) {
    this.baseUrl = config.baseUrl ?? "https://www.fast2sms.com/dev/bulkV2";
  }

  async send(message: OutboundMessage): Promise<MessageDeliveryResult> {
    if (message.channel !== "sms") throw new Error("Fast2SMS adapter only supports SMS messages");
    if (!message.body) throw new Error("SMS body is required");

    const body: Record<string, string> = {
      route: this.config.route,
      numbers: normalizeIndianNumber(message.to),
      message: message.body,
      sms_details: "1",
      udf1: message.idempotencyKey.slice(0, 100)
    };

    if (this.config.route === "dlt_manual") {
      if (!this.config.senderId) throw new Error("DLT-approved sender ID is required for dlt_manual route");
      body.sender_id = this.config.senderId;
      if (this.config.templateId) body.template_id = this.config.templateId;
      if (this.config.entityId) body.entity_id = this.config.entityId;
    }

    const response = await fetch(this.baseUrl, {
      method: "POST",
      headers: {
        Authorization: this.config.apiKey,
        Accept: "application/json",
        "Content-Type": "application/json"
      },
      body: JSON.stringify(body)
    });

    const payload = await response.json().catch(() => ({})) as Fast2SmsResponse;
    const accepted = response.ok && payload.return !== false;
    return {
      provider: "fast2sms",
      providerMessageId: payload.request_id,
      accepted,
      status: accepted ? "queued" : "failed",
      raw: payload
    };
  }
}
