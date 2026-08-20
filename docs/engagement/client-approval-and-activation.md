# Client Approval and Engagement Activation Standard

Concept Spaces separates client choice, commercial acceptance and technical/professional authority.

## Client approvals

Clients may approve requirements, design directions, scope modules, commercial proposals, milestone deliverables and other matters allocated to them by contract. A client approval does not substitute for statutory approval, professional sign-off or technical validation where those controls are independently required.

## Negotiation history

Proposal negotiations are append-only events tied to explicit proposal versions. Counter-offers, scope changes, commercial notes, acceptances and rejections must remain traceable. Accepted terms become a contract snapshot rather than rewriting negotiation history.

## Activation gates

A commercial opportunity may be marked won without automatically becoming an active project. Activation may require, according to configured policy:
- accepted proposal
- executed contract
- required KYC or client/entity checks
- initial/stage payment satisfaction
- required professional role setup
- mandatory site/intake inputs

If a required gate is incomplete, activation remains blocked with a visible reason.

## Scope control

Scope selections are versioned. Included, optional and excluded modules remain explicit. Dependencies are validated so removing an upstream service cannot silently leave a downstream responsibility unowned.

## Preview behavior

Before the isolated production database is connected, the interactive intake UI is intentionally non-persistent. It must not use browser local storage to create the appearance of a production client record.
