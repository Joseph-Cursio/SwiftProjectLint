[← Back to Rules](RULES.md)

## Non-Idempotent In Retry Context

**Identifier:** `Non-Idempotent In Retry Context`
**Category:** Idempotency
**Severity:** Error

### Rationale
A function declared `/// @lint.context replayable` or `/// @lint.context retry_safe` runs under at-least-once semantics. Upstream retries, webhook redeliveries, message-queue replays, or scheduled-job re-runs can invoke the function multiple times with the same input. Calling a `/// @lint.effect non_idempotent` function from such a body is the defining bug this rule catches: on replay, the non-idempotent call fires again, and whatever it does — sends an email, creates a database row without an idempotency key, charges a payment method, publishes a message — happens twice.

### Discussion
`NonIdempotentInRetryContextVisitor` walks each function declaration whose doc comment carries a `@lint.context` annotation, then inspects every direct call in its body. Callees annotated `/// @lint.effect non_idempotent` trigger the rule; everything else (idempotent, observational, unannotated, or a callee whose symbol-table entry was withdrawn by a collision) passes silently.

The visitor descends into non-escaping closure bodies but stops at escaping-closure boundaries (`Task { }`, `withTaskGroup`, `Task.detached`, SwiftUI's `.task { }` modifier). Those boundaries are retry contexts in their own right, and Phase 1 does not chain them.

Both `replayable` and `retry_safe` are semantically equivalent to this rule — both impose "callees must not be non-idempotent" on the body. Only the documentation intent differs: `replayable` emphasises upstream-retry semantics (webhooks, queues), `retry_safe` emphasises explicit in-code retry wrappers.

### Violating Examples
```swift
/// @lint.effect non_idempotent
func applyCharge(_ amount: Int) async throws {}

/// @lint.context replayable
/// Stripe webhook delivery is at-least-once; this handler may be invoked more
/// than once for the same event.
func handleStripeWebhook(event: StripeEvent) async throws {
    try await applyCharge(event.amount)      // flagged
}

/// @lint.effect non_idempotent
func sendConfirmationEmail(to user: User) async throws {}

/// @lint.context retry_safe
/// Invoked by a background task queue with automatic retry.
func deliverWelcome(_ user: User) async throws {
    try await sendConfirmationEmail(to: user)    // flagged
}
```

### Non-Violating Examples
```swift
// Route through an idempotency-keyed alternative
/// @lint.effect idempotent
/// Applies a charge keyed by an idempotency token. Replay with the same token
/// converges to the same outcome.
func applyChargeIdempotent(
    idempotencyKey: String,
    amount: Int
) async throws {}

/// @lint.context replayable
func handleStripeWebhook(event: StripeEvent) async throws {
    try await applyChargeIdempotent(
        idempotencyKey: event.id,
        amount: event.amount
    )                                        // no diagnostic — idempotent callee
}

// Observational calls are always acceptable in a replayable body
/// @lint.effect observational
func logWebhook(_ event: StripeEvent) {}

/// @lint.context replayable
func handleStripeWebhook(event: StripeEvent) async throws {
    logWebhook(event)                        // observational callee, no diagnostic
}

// Escaping-closure boundary — Phase 1 does not chain through it
/// @lint.effect non_idempotent
func insert(_ record: Record) async throws {}

/// @lint.context replayable
func handleWebhook() async throws {
    Task {
        try await insert(record)             // inside Task { }; not flagged by THIS rule
    }
}
```

### Annotation Placement
The `/// @lint.context` doc comment can appear either before or after attributes on the function declaration. Both are read equivalently:

```swift
/// @lint.context replayable
@available(macOS 13.0, *)
func handleWebhook(event: Event) async throws {}

@available(macOS 13.0, *)
/// @lint.context replayable
func handleWebhook(event: Event) async throws {}
```

### Typical Application
The rule targets handlers that are externally retry-exposed: webhook endpoints (Stripe, GitHub, Slack), queue workers (SQS, SNS, Lambda event sources, RabbitMQ), scheduled-job retries, and middleware in any at-least-once delivery pipeline.

### Interpretation of Zero Findings
This rule is annotation-gated: it can fire only when a function carries a `@lint.context` declaration *and* its direct callee carries a `@lint.effect non_idempotent` declaration. On un-annotated source it produces nothing. A zero-finding result on an un-annotated codebase means no `@lint.context` declarations are in scope — it does not mean the codebase is free of retry-hazard bugs. Findings accumulate as the annotation campaign progresses, starting with handlers whose retry semantics are objectively fixed (webhook endpoints, queue consumers).

### Remediation
- **Swap the callee.** Replace a `non_idempotent` call with an idempotent alternative keyed by a stable upstream identifier.
- **Route through an idempotency key.** Use the callee's idempotency-key parameter, with the key derived from a stable upstream identifier (Stripe event ID, SQS message ID, webhook delivery ID).
- **Add a deduplication guard.** Check a persistent dedup store before the call site; skip the non-idempotent work when the guard indicates a replay.
- **Weaken the annotation.** If the function is not actually replayable — e.g. it only runs once per process lifecycle — remove `@lint.context replayable`; misuse of the annotation is itself a bug worth correcting.

---
