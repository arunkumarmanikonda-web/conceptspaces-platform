# Integration & Secrets Security Standard

## Principle
Concept Spaces treats third-party providers as untrusted external dependencies behind governed adapters. Provider credentials are never stored in client-side code, browser storage, source control, logs, analytics payloads or public configuration.

## Credential lifecycle
1. A Super Admin selects a provider and environment.
2. Configuration metadata is saved separately from secrets.
3. Secret values are written only to the deployment/runtime secret store.
4. The application stores an opaque secret reference, never the recovered secret.
5. A provider health check must succeed before the integration can become `verified`.
6. Secret rotation creates a new secret version and audit event.
7. Disabling a provider prevents new outbound activity immediately.

## Environments
- Sandbox/test credentials are mandatory where the provider supports them.
- Production credentials cannot be copied into preview deployments.
- Webhook endpoints are environment-specific.
- Payment and contract execution providers require explicit production activation.

## Webhook security
Every webhook-capable adapter must implement:
- raw-body signature verification before JSON parsing when the provider requires it;
- event ID deduplication/idempotency;
- timestamp/replay-window validation where supported;
- durable receipt before asynchronous processing;
- provider and environment allowlisting;
- correlation IDs and append-only audit evidence;
- no trust in event payload instructions beyond the documented provider schema.

Webhook handlers fail closed. Unknown providers, missing signatures, invalid signatures and unconfigured environments are rejected.

## Payments
Payment workflows must never infer settlement from a browser redirect. Financial state changes require a verified server-side provider event or a trusted provider API reconciliation result. Posting, refunds, settlement and payment release remain maker-checker governed.

## Messaging
- Email: transactional templates and sending identities are versioned.
- WhatsApp: only approved provider templates may be sent when the channel requires template approval.
- SMS: sender IDs/templates are governed according to the provider and jurisdiction.
- Every outbound communication records template/version, recipient, purpose, provider ID and delivery state.

## DNS
DNS changes are treated as privileged infrastructure changes. Production changes require:
- domain allowlist;
- maker-checker approval;
- before/after record capture;
- TTL-aware rollback plan;
- audit evidence.

## AI providers
AI API keys are secret-store only. Each model is registered by purpose, maximum autonomy, allowed project criticalities, data-handling classification and fallback policy. C4 work cannot be autonomously issued by any AI provider.

## Initial provider targets
- GoDaddy: DNS/domain management
- Resend: transactional email
- Razorpay: payments (when registration is active)
- AiSensy: WhatsApp
- Fast2SMS: SMS
- AI providers: configured through the governed model registry rather than hard-coded in application logic
