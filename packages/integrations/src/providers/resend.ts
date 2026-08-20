import { Webhook } from "svix";
import type { MessagingAdapter, MessageDeliveryResult, OutboundMessage } from "../index";

export interface ResendConfig {
  apiKey: string;
  from: string;
  webhookSecret?: string;
  baseUrl?: string;
  userAgent?: string;
}

type ResendEmailResponse = { id: string };

export class ResendEmailAdapter implements MessagingAdapter {
  private readonly baseUrl: string;

  constructor(private readonly config: ResendConfig) {
    this.baseUrl = config.baseUrl ?? "https://api.resend.com";
  }

  async send(message: OutboundMessage): Promise<MessageDeliveryResult> {
    if (message.channel !== "email") throw new Error("Resend adapter only supports email messages");
    if (!message.subject) throw new Error("Email subject is required");
    if (!message.body) throw new Error("Email body is required");
    if (!message.idempotencyKey || message.idempotencyKey.length > 256) throw new Error("Valid Resend idempotency key is required");

    const response = await fetch(`${this.baseUrl}/emails`, {
      method: "POST",
      headers: {
        Authorization: `Bearer ${this.config.apiKey}`,
        "Content-Type": "application/json",
        "User-Agent": this.config.userAgent ?? "conceptspaces-platform/0.1",
        "Idempotency-Key": message.idempotencyKey
      },
      body: JSON.stringify({
        from: this.config.from,
        to: [message.to],
        subject: message.subject,
        html: message.body
      })
    });

    if (!response.ok) {
      const raw = await response.text();
      return { provider: "resend", accepted: false, status: "failed", raw };
    }

    const payload = await response.json() as ResendEmailResponse;
    return {
      provider: "resend",
      providerMessageId: payload.id,
      accepted: true,
      status: "queued",
      raw: payload
    };
  }

  async verifyWebhook(headers: Headers, rawBody: string): Promise<boolean> {
    if (!this.config.webhookSecret) return false;
    const id = headers.get("svix-id");
    const timestamp = headers.get("svix-timestamp");
    const signature = headers.get("svix-signature");
    if (!id || !timestamp || !signature) return false;

    try {
      const webhook = new Webhook(this.config.webhookSecret);
      webhook.verify(rawBody, {
        "svix-id": id,
        "svix-timestamp": timestamp,
        "svix-signature": signature
      });
      return true;
    } catch {
      return false;
    }
  }
}
