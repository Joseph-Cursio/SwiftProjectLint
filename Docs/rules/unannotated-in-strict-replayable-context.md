[← Back to Rules](RULES.md)

## Unannotated In Strict Replayable Context

**Identifier:** `Unannotated In Strict Replayable Context`
**Category:** Idempotency
**Severity:** Error *(opt-in via `strict_replayable` annotation)*

### Rationale
The default `/// @lint.context replayable` rule (`nonIdempotentInRetryContext`) only fires when a callee is *positively* known to be non-idempotent — by declaration, upward inference, or the name-based heuristic. Callees with no evidence either way pass silently. That's the right precision profile for incremental adoption: a Swift codebase rarely has effect annotations on every transitive callee, and a noisy retry-context check would be ignored.

`strict_replayable` is the opt-in variant for handlers where that lenient default is the wrong call — payment flows, exactly-once queue consumers, financial postings, anything where an unproven callee on a retry path is itself a finding worth investigating. Annotating with `/// @lint.context strict_replayable` flips the default: callees must be *proven safe* (idempotent, observational, or externally-idempotent) rather than merely *not proven dangerous*.

### Discussion
`UnannotatedInStrictReplayableContextVisitor` walks each function declaration whose doc comment carries `/// @lint.context strict_replayable`, then inspects every direct call in its body. A callee fires the rule iff **none** of the following hold:

1. **Declared effect** in the symbol table — any tier (`idempotent`, `observational`, `externally_idempotent(by:)`, or even `non_idempotent`).
2. **Upward-inferred effect** — the callee's body is analysed and yields a classification.
3. **Heuristic classification** — the prefix-matching name heuristic returns either a positive tier or `non_idempotent`.
4. **Symbol-table collision** — two conflicting `@lint.effect` annotations for the same signature; the OI-4 collision policy withdraws the entry and no inference runs.

Only callees that reach the fall-through "no evidence" branch fire this rule. That's the exact gap strict mode closes.

The visitor descends into non-escaping closure bodies but stops at escaping-closure boundaries (`Task { }`, `withTaskGroup`, `Task.detached`, SwiftUI's `.task { }` modifier). Those boundaries are retry contexts in their own right, and Phase 1 does not chain them.

### Relationship to `nonIdempotentInRetryContext`
This rule does **not** replicate the existing rule's diagnostic on `non_idempotent` callees in a `strict_replayable` body — that firing comes from `nonIdempotentInRetryContext`, which already treats `strict_replayable` as a retry-context caller (identical label plumbing). Strict mode only *adds* the unannotated-callee case. A `non_idempotent` callee in a `strict_replayable` body produces exactly one diagnostic, from the existing rule.

### Violating Examples
```swift
// 1. Plain unannotated callee — strict mode flags it
func mystery(_ id: Int) async throws {}

/// @lint.context strict_replayable
/// Stripe webhook handler; mistakes here cost real money.
func handle(_ id: Int) async throws {
    try await mystery(id)                       // flagged: no proven effect
}

// 2. Multiple unannotated callees — each one fires
func alpha() {}
func beta() {}
func gamma() {}

/// @lint.context strict_replayable
func dispatch() async throws {
    alpha()                                     // flagged
    beta()                                      // flagged
    gamma()                                     // flagged
}
```

### Non-Violating Examples
```swift
// Declared idempotent — passes silently
/// @lint.effect idempotent
func upsert(_ id: Int) async throws {}

/// @lint.context strict_replayable
func handle(_ id: Int) async throws {
    try await upsert(id)                        // declared safe, no diagnostic
}

// Declared observational — passes silently
/// @lint.effect observational
func audit(_ message: String) {}

/// @lint.context strict_replayable
func handle() async throws {
    audit("hello")                              // observational, no diagnostic
}

// Declared externally_idempotent — caller-routed key, passes silently
/// @lint.effect externally_idempotent(by: "key")
func sendEmail(idempotencyKey: String) async throws {}

/// @lint.context strict_replayable
func handle() async throws {
    try await sendEmail(idempotencyKey: "evt_1")    // keyed external, no diagnostic
}

// Upward inference — wrapper's body only calls idempotent primitives
/// @lint.effect idempotent
func leaf(_ id: Int) async throws {}

func wrapper(_ id: Int) async throws {
    try await leaf(id)                          // body classified upward
}

/// @lint.context strict_replayable
func handle(_ id: Int) async throws {
    try await wrapper(id)                       // inferred safe, no diagnostic
}
```

### Annotation Placement
The `/// @lint.context strict_replayable` doc comment can appear either before or after attributes on the function declaration. Both are read equivalently:

```swift
/// @lint.context strict_replayable
@available(macOS 13.0, *)
func handlePayment(event: Event) async throws {}

@available(macOS 13.0, *)
/// @lint.context strict_replayable
func handlePayment(event: Event) async throws {}
```

Closure-binding attachment works identically to `replayable` — see the `nonIdempotentInRetryContext` rule for details.

### Typical Application
`strict_replayable` is the right annotation when the cost of a single missed call hazard is high enough that "no evidence" is itself a problem worth surfacing:

- **Payment flows** — Stripe / PayPal / Adyen webhook handlers, charge-capture callbacks, refund processors.
- **Financial postings** — ledger writes, balance adjustments, settlement reconciliation.
- **Exactly-once queue consumers** — Kafka exactly-once handlers, dedup-keyed SQS consumers, idempotent event processors where every external call must be proven safe.
- **Compliance-sensitive paths** — KYC writes, audit-log appenders that must not double-write under replay.

For ordinary at-least-once handlers (general webhook endpoints, retry-tolerant background jobs), the default `replayable` rule is the right tool — `strict_replayable` would force annotation work on every transitive callee for diminishing returns.

### Remediation
- **Annotate the callee.** Attach `/// @lint.effect idempotent`, `/// @lint.effect observational`, or `/// @lint.effect externally_idempotent(by: <key>)` to declare the effect explicitly. This is the canonical fix and the one the diagnostic prompts for.
- **Use the SwiftIdempotency attribute forms.** When inline doc comments are not appropriate (generated code, third-party-derived stubs), the attribute form `@LintEffect(.idempotent)` is read equivalently.
- **Refactor through a classified wrapper.** If the callee is third-party and cannot be annotated, wrap it in a thin local function that *is* annotated, and call the wrapper.
- **Weaken to `replayable`.** If the strict mode is producing more noise than insight on a particular handler, downgrade to `/// @lint.context replayable` — the unannotated-callee case stops firing, and you keep coverage on the `non_idempotent`-callee case.

---
