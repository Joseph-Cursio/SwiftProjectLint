[← Back to Rules](RULES.md)

## Missing Idempotency Key

**Identifier:** `Missing Idempotency Key`
**Category:** Idempotency
**Severity:** Error

### Rationale
The `/// @lint.effect externally_idempotent(by: paramName)` annotation declares that a function is idempotent *only if* the caller supplies a stable deduplication key at parameter `paramName`. The other idempotency rules trust that this key is routed correctly at every call site. This rule is the verifier for that trust: it flags call sites whose argument at `paramName` is obviously non-stable — a fresh UUID, a timestamp, a random number. When the key varies per invocation, retries don't converge on the same outcome, and the keyed guarantee collapses.

### Discussion
`MissingIdempotencyKeyVisitor` walks each function body and, for every direct call whose callee's symbol-table entry is `/// @lint.effect externally_idempotent(by: P)`, looks up the argument with label `P`. If that argument's expression is a direct call to a known per-invocation generator (`UUID()`, `Date()`, `arc4random()`, `arc4random_uniform()`, `CFUUIDCreate()`) or a member access derived from one (`UUID().uuidString`, `Date.now`), the rule fires.

The rule is **deliberately narrow and high-precision.** It does not trace data flow — a local constant holding `UUID()` or a property that returns a fresh value each time remains invisible. The trade-off is intentional: false positives on idempotency keys would be worse than the known false negatives, because a diagnostic on a genuinely-stable key would force users to either rewrite working code or disable the rule. Deeper data-flow analysis belongs to a future phase.

### Violating Examples
```swift
/// @lint.effect externally_idempotent(by: idempotencyKey)
func stripeCharge(idempotencyKey: String, amount: Int) async throws {}

/// @lint.context replayable
func handleWebhook(amount: Int) async throws {
    // UUID().uuidString is fresh per invocation — flagged
    try await stripeCharge(idempotencyKey: UUID().uuidString, amount: amount)
}

/// @lint.effect externally_idempotent(by: key)
func charge(key: Date, amount: Int) async throws {}

/// @lint.context replayable
func process(amount: Int) async throws {
    // Date.now is a fresh timestamp per invocation — flagged
    try await charge(key: Date.now, amount: amount)
}

/// @lint.effect externally_idempotent(by: key)
func send(key: UInt32, message: String) async throws {}

func notify(message: String) async throws {
    // arc4random() produces a different value per call — flagged
    try await send(key: arc4random(), message: message)
}
```

### Non-Violating Examples
```swift
/// @lint.effect externally_idempotent(by: idempotencyKey)
func stripeCharge(idempotencyKey: String, amount: Int) async throws {}

struct WebhookEvent { let id: String; let amount: Int }

// Stable upstream identifier — the whole point of the tier
/// @lint.context replayable
func handleWebhook(event: WebhookEvent) async throws {
    try await stripeCharge(idempotencyKey: event.id, amount: event.amount)
}

// Property access — the rule assumes potentially stable, passes silently
/// @lint.context replayable
func process(request: Request) async throws {
    try await stripeCharge(idempotencyKey: request.messageID, amount: request.amount)
}

// Local let-binding — the rule does not follow bindings; silent even when
// the binding's right-hand side is UUID(). Known limitation below.
/// @lint.context replayable
func handle(amount: Int) async throws {
    let key = UUID().uuidString
    try await stripeCharge(idempotencyKey: key, amount: amount)  // NOT flagged
}
```

### Known Limitations

These shapes pass silently by design; deeper analysis to flag them lives in a future phase.

- **Let-bindings.** A local constant holding a fresh-per-call value is invisible. `let k = UUID(); call(key: k)` does not fire.
- **String interpolation.** A key like `"\(UUID())-\(event.id)"` is a string literal expression at the AST level, not a direct generator call. The rule does not inspect interpolation contents.
- **Wrapper functions.** A helper `makeKey() -> String { UUID().uuidString }` called as `call(key: makeKey())` passes silently; the rule sees an opaque function call and does not follow it.
- **Missing labelled argument.** If the keyed parameter has a default value and the call site omits it, the rule has nothing to inspect. A future enhancement could cross-reference the callee's declaration to distinguish "defaulted and stable" from "omitted and broken."
- **Key-parameter overloading.** Two overloads that both carry `(by:)` with different parameter names work correctly; one that carries `(by:)` and one that does not is intentional documentation-only on the latter.

### Interaction with Other Idempotency Rules

- **`idempotencyViolation`** fires on the caller/callee lattice rows that don't fit the keyed story (`observational → externally_idempotent`, `externally_idempotent → non_idempotent`). It is orthogonal to this rule.
- **`nonIdempotentInRetryContext`** stays silent on `externally_idempotent` callees — it trusts the key routing. This rule is the check that makes that trust defensible. If this rule fires, the implicit trust granted by `nonIdempotentInRetryContext` is invalid for that specific call site.

### Remediation

- **Use the upstream identifier.** Stripe webhook redeliveries carry the same `event.id`; SQS messages carry the same `MessageId`; Mailgun events carry the same `Message-Id`. These are the canonical stable keys.
- **Derive stably from request input.** A request-scoped idempotency key that is the same on replay — such as a client-supplied `X-Idempotency-Key` header — is valid.
- **Weaken the callee annotation.** If the function genuinely cannot be routed idempotently, `@lint.effect non_idempotent` is the honest declaration and callers will see the appropriate `nonIdempotentInRetryContext` diagnostics instead.
- **Introduce a deduplication guard at the site.** A persistent dedup store (Redis, DynamoDB item) can absorb the non-stability at the cost of an extra lookup.

---
