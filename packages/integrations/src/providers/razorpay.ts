import { createHmac, timingSafeEqual } from "node:crypto";
import type { PaymentAdapter, PaymentIntentInput, PaymentIntentResult } from "../index";

export interface RazorpayConfig {
  keyId: string;
  keySecret: string;
  webhookSecret?: string;
  baseUrl?: string;
}

type RazorpayOrder = {
  id: string;
  entity: "order";
  amount: number;
  amount_paid: number;
  amount_due: number;
  currency: string;
  receipt?: string;
  status: "created" | "attempted" | "paid";
  attempts: number;
  notes?: Record<string, string> | string[];
  created_at: number;
};

function secureHexEqual(expected: string, received: string): boolean {
  try {
    const a = Buffer.from(expected, "hex");
    const b = Buffer.from(received, "hex");
    return a.length === b.length && timingSafeEqual(a, b);
  } catch {
    return false;
  }
}

export class RazorpayPaymentAdapter implements PaymentAdapter {
  private readonly baseUrl: string;

  constructor(private readonly config: RazorpayConfig) {
    this.baseUrl = config.baseUrl ?? "https://api.razorpay.com";
  }

  private authorization(): string {
    return `Basic ${Buffer.from(`${this.config.keyId}:${this.config.keySecret}`).toString("base64")}`;
  }

  async createPaymentIntent(input: PaymentIntentInput): Promise<PaymentIntentResult> {
    if (!Number.isSafeInteger(input.amountMinor) || input.amountMinor < 1) throw new Error("Payment amount must be a positive integer in minor currency units");
    if (!/^[A-Z]{3}$/.test(input.currency)) throw new Error("Payment currency must be an ISO-style three-letter uppercase code");

    const notes = { ...(input.metadata ?? {}), conceptspaces_idempotency_key: input.idempotencyKey };
    const response = await fetch(`${this.baseUrl}/v1/orders`, {
      method: "POST",
      headers: {
        Authorization: this.authorization(),
        "Content-Type": "application/json",
        Accept: "application/json"
      },
      body: JSON.stringify({
        amount: input.amountMinor,
        currency: input.currency,
        receipt: input.reference.slice(0, 40),
        notes
      })
    });

    if (!response.ok) {
      const raw = await response.text();
      throw new Error(`Razorpay order creation failed (${response.status}): ${raw.slice(0, 500)}`);
    }

    const order = await response.json() as RazorpayOrder;
    return {
      provider: "razorpay",
      providerPaymentId: order.id,
      status: order.status === "paid" ? "captured" : "created"
    };
  }

  async verifyWebhook(headers: Headers, rawBody: string): Promise<boolean> {
    if (!this.config.webhookSecret) return false;
    const signature = headers.get("x-razorpay-signature");
    if (!signature) return false;
    const expected = createHmac("sha256", this.config.webhookSecret).update(rawBody, "utf8").digest("hex");
    return secureHexEqual(expected, signature);
  }
}

export function razorpayEventId(headers: Headers): string | null {
  return headers.get("x-razorpay-event-id");
}
