const SUPPORTED = new Set(["resend","razorpay","aisensy"]);
const MAX_BODY_BYTES = 1024 * 1024;

function noStore(body:unknown,status:number,requestId:string){
  return Response.json(body,{status,headers:{"Cache-Control":"no-store","X-Request-Id":requestId}});
}

export async function POST(request: Request, context: { params: Promise<{ provider: string }> }) {
  const { provider } = await context.params;
  const requestId = request.headers.get("x-request-id") || crypto.randomUUID();
  if (!SUPPORTED.has(provider)) return noStore({ error: "unsupported_provider" },404,requestId);

  const length = Number(request.headers.get("content-length") || "0");
  if (length > MAX_BODY_BYTES) return noStore({ error: "payload_too_large" },413,requestId);

  const rawBody = await request.text();
  if (!rawBody) return noStore({ error: "empty_payload" },400,requestId);
  if (new TextEncoder().encode(rawBody).byteLength > MAX_BODY_BYTES) return noStore({ error: "payload_too_large" },413,requestId);

  // Fail closed until the provider-specific verifier, persistence and idempotency store are configured.
  // Activation sequence: verify signature against the raw body -> hash payload -> persist idempotent receipt
  // -> acknowledge within provider SLA -> enqueue asynchronous domain processing. Never process a payment,
  // communication or other side effect directly from an unverified inbound payload.
  return noStore({ error: "provider_not_configured", provider, requestId },503,requestId);
}
