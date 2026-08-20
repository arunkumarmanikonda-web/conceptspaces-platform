const SUPPORTED = new Set(["resend","razorpay","aisensy"]);

export async function POST(request: Request, context: { params: Promise<{ provider: string }> }) {
  const { provider } = await context.params;
  if (!SUPPORTED.has(provider)) {
    return Response.json({ error: "unsupported_provider" }, { status: 404 });
  }

  const rawBody = await request.text();
  if (!rawBody) {
    return Response.json({ error: "empty_payload" }, { status: 400 });
  }

  // Fail closed until the provider-specific verifier is configured.
  // Each adapter must verify its signature using the raw body before parsing JSON,
  // persist an idempotent receipt, then enqueue asynchronous processing.
  return Response.json(
    { error: "provider_not_configured", provider },
    { status: 503, headers: { "Cache-Control": "no-store" } }
  );
}
