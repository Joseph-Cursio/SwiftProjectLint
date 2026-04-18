[← Back to Rules](RULES.md)

## Non-Idempotent In Retry Context

**Identifier:** `Non-Idempotent In Retry Context`
**Category:** Idempotency
**Severity:** Error

### Rationale
A function declared `/// @lint.context replayable` or `/// @lint.context retry_safe` runs under at-least-once semantics. Upstream retries, webhook redeliveries, message-queue replays, or scheduled-job re-runs can invoke the function multiple times with the same input. Calling a `/// @lint.effect non_idempotent` function from such a body is the defining bug this rule catches: on replay, the non-idempotent call fires again, and whatever it does — sends an email, creates a database row without an idempotency key, charges a payment method, publishes a message — happens twice.

### Discussion
`NonIdempotentInRetryContextVisitor` walks each function declaration whose doc comment carries a `@lint.context` annotation, then inspects every direct call in its body. Callees annotated `/// @lint.effect non_idempotent` trigger the rule; everything else (idempotent, observational, externally_idempotent, unannotated, or a callee whose symbol-table entry was withdrawn by a collision) passes silently.

**Note on `externally_idempotent` callees.** These are functions idempotent only when routed through a caller-supplied deduplication key (Stripe, SES, Mailgun, SNS). The rule trusts the caller to route the key and stays silent. Whether the key actually reaches the callee is a separate check that a future rule (`missingIdempotencyKey`) will verify. Until then, a keyed external operation inside a `replayable` body is not flagged — the happy path for webhook handlers using idempotency tokens.

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

### Annotation attachment — function declarations **and** closure bindings

`/// @lint.context replayable` / `retry_safe` / `once` attaches to either:

- a function declaration (`func handle(event:context:) async throws { ... }`), or
- a variable binding whose initialiser is a closure literal (`let handler: @Sendable (Event, Context) -> Void = { ... }` — single binding, both top-level and stored-property forms).

Closure-binding annotations were added after round 6, motivated by modern Swift-server handler idioms where the Lambda entry point is a closure stored in a `let`-binding rather than a method declaration. Inline trailing-closure arguments (`LambdaRuntime { event, ctx in ... }`) remain out of scope — they have no binding site to attach the annotation to. Users who want coverage refactor to a named `let handler = { ... }` binding.

### Inference Fallbacks (Phase 2.2 and 2.3)

When a callee reached from a `@lint.context replayable` or `@lint.context retry_safe` body has no `@lint.effect` annotation, the rule consults two inference sources in precedence order:

1. **Upward inference** — the callee's own body is analysed; if it calls any non-idempotent function directly, the callee is itself inferred non-idempotent. One hop only; chains deeper than one level are a documented limitation.
2. **Heuristic-downward inference** — a small name-based whitelist (`create`, `insert`, `append`, `publish`, `enqueue`, `post`, `send`) classifies callees whose bodies produced no upward result. The whitelist matches both **exact bare names** (`send`, `insert`, …) and **camelCase-composed prefix names** (`sendEmail`, `insertRow`, `publishEvent`, `createUser`). Prefix matching requires the next character after the prefix to be uppercase (Swift word boundary), so `sending`, `publisher`, `appending`, `postponed`, `creator`, `inserted` stay silent — those are participle / noun forms, not mutation verbs. **Receiver-type gated:** the match is suppressed when the receiver syntactically resolves to a stdlib-collection type — for exact names the suppression is (type, method)-specific (e.g. `Array.append`, `Set.insert` which is set-idempotent, `Dictionary.updateValue`); for prefix matches the suppression is blanket (stdlib-collection receivers never trigger prefix heuristics). Resolution is syntactic only — unresolvable receivers fall through unchanged.

Declared annotations always win. The rule fires whenever an inferred-non-idempotent callee is reached from a retry context, treating inference the same as declaration for firing purposes.

**Diagnostic prose** distinguishes each provenance:

- Upward: "whose effect is inferred `non_idempotent` from its body"
- Heuristic-downward: "whose effect is inferred `non_idempotent` from the callee name …"
- Declared: "which is declared `@lint.effect non_idempotent`"

All variants instruct the user on how to override by annotating the callee explicitly with `/// @lint.effect <tier>`.

**Collision-withdrawn entries skip both inference paths.** When the OI-4 collision policy withdraws an annotated callee's entry (two conflicting `@lint.effect` declarations for the same signature), neither upward nor downward inference runs. The ambiguity is the user's to resolve.

### Interpretation of Zero Findings
The caller side still requires `@lint.context replayable` / `retry_safe` — the rule cannot fire without that annotation. Once a caller is annotated, the callee can be annotated OR inferred. A zero-finding result on a corpus with no `@lint.context` declarations means no `replayable` bodies are in scope — not that no retry-hazard bugs exist. Findings accumulate as the annotation campaign progresses, starting with handlers whose retry semantics are objectively fixed (webhook endpoints, queue consumers).

### Remediation
- **Swap the callee.** Replace a `non_idempotent` call with an idempotent alternative keyed by a stable upstream identifier.
- **Route through an idempotency key.** Use the callee's idempotency-key parameter, with the key derived from a stable upstream identifier (Stripe event ID, SQS message ID, webhook delivery ID).
- **Add a deduplication guard.** Check a persistent dedup store before the call site; skip the non-idempotent work when the guard indicates a replay.
- **Weaken the annotation.** If the function is not actually replayable — e.g. it only runs once per process lifecycle — remove `@lint.context replayable`; misuse of the annotation is itself a bug worth correcting.

---
