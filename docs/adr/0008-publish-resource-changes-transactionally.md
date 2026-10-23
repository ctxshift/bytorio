# Publish typed resource changes transactionally

Represent runtime-owned graphics and audio resources with typed, session-scoped
generation handles rather than exposing their storage addresses to games.
Snapshot submitted data and validate ordered resource packets before publishing
their effects, so stale handles and rejected packets cannot leave partially
applied resource changes.
Explicit lifetimes, staging copies and transactional bookkeeping are the cost of
predictable ownership and failure behavior across both SDKs and hosts.

Ownership and commit rules: [resource specification](../resource-av-spec.md).
