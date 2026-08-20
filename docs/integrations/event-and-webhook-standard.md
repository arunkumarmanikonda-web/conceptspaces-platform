# Event, Webhook and Provider Safety Standard

## Domain events
Domain events are immutable facts about completed state transitions. Every event carries a stable event type, schema version, organisation, optional project, actor/correlation/causation references, criticality and payload hash.

## Transactional outbox
Business-state mutation and outbox creation must occur in the same database transaction. The publisher may retry safely. Consumers must not infer that a state transition happened solely because an external provider acknowledged a message.

## Idempotency
Every external side effect requires a stable idempotency key. Duplicate webhook receipts and duplicate outbound delivery attempts must not create duplicate payments, messages, invoices, approvals or project mutations.

## Webhooks
1. Read the raw request body within a defined maximum size.
2. Verify provider signature before parsing or acting on data.
3. Compute and persist a raw-body hash and provider idempotency identity.
4. Reject invalid signatures and record the rejection without sensitive payload logging.
5. Acknowledge valid receipts within provider expectations.
6. Process domain effects asynchronously.

## Retry and dead letter
Retries use bounded exponential backoff. Exhausted deliveries enter a dead-letter state. C4 events and non-replayable financial events never replay automatically; an authorised operator must inspect cause, current state and duplication risk first.

## Provider activation
A provider may move from configured to verified only when credentials, endpoint ownership, webhook verification, sandbox/production separation, health checks and least-privilege permissions are confirmed. Secrets are represented by secret references and never returned to user interfaces.

## API credentials
Machine credentials are scoped, expiring and revocable. Raw secrets are shown once. Request audit records route, request ID, status and performance while storing only privacy-safe client fingerprints.
