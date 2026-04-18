[← Back to Rules](RULES.md)

## Idempotency Violation

**Identifier:** `Idempotency Violation`
**Category:** Idempotency
**Severity:** Error

### Rationale
A function can declare its effect contract via `/// @lint.effect` in its doc comment. Once declared, callers depend on that contract — a function trusted as idempotent is trusted because of its annotation, and silent violations of the annotation undermine the entire annotation layer. This rule verifies that a function's body respects the effect it claims.

### Discussion
`IdempotencyViolationVisitor` walks each function declaration in the project, reads its `@lint.effect` annotation, and — for callers declared `idempotent` or `observational` — checks every direct call in the body against the project-wide `EffectSymbolTable`. The visitor resolves callees by full function signature (name + argument labels), so overloads that Swift distinguishes resolve independently. Unannotated callees are silent (Phase 1 does not infer); callees whose symbol-table entry was withdrawn by a collision are also silent.

The rule covers five combinations:

| Caller effect | Callee effect | Fires? |
|---|---|:-:|
| `idempotent` | `non_idempotent` | ✓ |
| `observational` | `idempotent` | ✓ |
| `observational` | `non_idempotent` | ✓ |
| `observational` | `externally_idempotent` | ✓ (Phase 2) |
| `externally_idempotent` | `non_idempotent` | ✓ (Phase 2) |

All other combinations are permissible. In particular, `idempotent` can freely call `observational` (logging inside an idempotent function is fine), and either can call unannotated callees without a diagnostic.

**A note on `externally_idempotent` callees.** The tier models functions that are idempotent *only* when routed through a caller-supplied deduplication key (Stripe, SES, Mailgun, SNS). When an `idempotent`, `externally_idempotent`, or retry-context caller calls an `externally_idempotent` function, this rule stays silent — it trusts the caller to route the key. Whether the key actually reaches the callee is a separate check that a future rule (`missingIdempotencyKey`) will verify. Until then, the keyed path is trusted at the point it's declared.

The two `externally_idempotent` rows the rule *does* fire on capture the cases where key routing doesn't rescue the situation:

- **`observational → externally_idempotent`.** Observational functions must not mutate business state. A Stripe charge with an idempotency key is still a state mutation — the key only ensures the mutation converges under replay, not that it did not happen. Observational is stricter than both sides of the keyed bargain.
- **`externally_idempotent → non_idempotent`.** Any unconditionally non-idempotent work inside a keyed operation's body re-fires on replay regardless of the caller's idempotency key. An audit-log append inside `stripeCharge(idempotencyKey:)` runs twice on webhook redelivery; the key does not protect it. The keyed guarantee is only as strong as its weakest uninstrumented call.

### Violating Examples
```swift
/// @lint.effect non_idempotent
func send(_ email: String) async throws {}

/// @lint.effect idempotent
func notify(_ user: User) async throws {
    try await send(user.email)        // idempotent caller, non_idempotent callee — flagged
}

/// @lint.effect idempotent
func upsert(_ user: User) async throws {}

/// @lint.effect observational
func logUser(_ user: User) async throws {
    try await upsert(user)            // observational must not mutate business state — flagged
}

// Phase 2 — observational caller into a keyed external operation
/// @lint.effect externally_idempotent
func charge(idempotencyKey: String, amount: Int) async throws {}

/// @lint.effect observational
func reportChargeMetric(orderID: String, amount: Int) async throws {
    try await charge(idempotencyKey: orderID, amount: amount)   // flagged
}

// Phase 2 — keyed external caller with a non-idempotent helper inside
/// @lint.effect non_idempotent
func appendAudit(_ event: String) async throws {}

/// @lint.effect externally_idempotent
func chargeWithAudit(idempotencyKey: String, amount: Int) async throws {
    try await appendAudit("charge \(idempotencyKey)")           // flagged
    try await charge(idempotencyKey: idempotencyKey, amount: amount)
}
```

### Non-Violating Examples
```swift
// idempotent → observational is fine
/// @lint.effect observational
func logMetric(_ name: String) {}

/// @lint.effect idempotent
func upsert(_ user: User) async throws {
    logMetric("upsert.called")        // observational callee, no diagnostic
}

// Unannotated callee — Phase 1 does not infer
func opaqueHelper(_ user: User) async throws {}

/// @lint.effect idempotent
func process(_ user: User) async throws {
    try await opaqueHelper(user)      // no annotation on callee, no diagnostic
}

// Observational caller calling another observational callee — fine
/// @lint.effect observational
func logEvent(_ name: String) {}

/// @lint.effect observational
func trace(_ event: String) {
    logEvent("traced.\(event)")       // observational → observational, no diagnostic
}

// Phase 2 — idempotent caller routing a key through externally_idempotent
/// @lint.effect externally_idempotent
func stripeCharge(idempotencyKey: String, amount: Int) async throws {}

/// @lint.effect idempotent
func process(orderID: String, amount: Int) async throws {
    try await stripeCharge(idempotencyKey: orderID, amount: amount)   // no diagnostic
}

// Phase 2 — externally_idempotent wrapper that delegates to another keyed op
/// @lint.effect externally_idempotent
func billCustomer(idempotencyKey: String, amount: Int) async throws {
    try await stripeCharge(idempotencyKey: idempotencyKey, amount: amount)
    // composition holds; key is carried through
}
```

### Annotation Placement
The `/// @lint.effect` doc comment can appear either before or after attributes on the function declaration. Both are read equivalently:

```swift
/// @lint.effect idempotent
@available(macOS 13.0, *)
func upsert(_ user: User) async throws {}

@available(macOS 13.0, *)
/// @lint.effect idempotent
func upsert(_ user: User) async throws {}
```

### Inference Fallbacks (Phase 2.2 and 2.3)

When a callee has no `@lint.effect` annotation in the project-wide symbol table, the rule consults two inference sources in order:

1. **Upward inference (Phase 2.3).** Before emitting diagnostics, the linter walks every un-annotated function body and computes the lattice lub of that body's direct callees' effects (using declared and heuristic-downward results). If one non-idempotent call appears, the enclosing function is inferred non-idempotent; if all calls are observational, the function is observational; and so on. Upward is **one hop only** — inferred effects do not chain further within a single pass.
2. **Heuristic-downward inference (Phase 2.2).** If no upward inference ran (the callee wasn't defined in this project, or its body had no recognised calls), the rule consults a small name-based whitelist.

Declared annotations always win; inference fires **only** for un-annotated callees, and in the precedence order: `declared > collision-withdraw (silent) > upward-inferred > heuristic-downward > silent`.

#### Heuristic-downward whitelist

The whitelist is intentionally small:

- **Non-idempotent** (by bare callee name): `create`, `insert`, `append`, `publish`, `enqueue`, `post`, `send`.
- **Idempotent** (by bare callee name): `upsert`, `setIfAbsent`, `replace`.
- **Observational** (requires both receiver shape *and* level name): receiver name contains `log` (case-insensitive) — e.g. `logger`, `Logger`, `requestLogger`, `os_log` — and the method is one of `trace`/`debug`/`info`/`notice`/`warning`/`error`/`critical`/`fault`/`log`.

Names deliberately out of scope include `save`, `put`, `update`, `write` — each has too many idempotent interpretations to classify by name alone.

**Receiver-type gating (stdlib exclusions).** The bare-name heuristic is silenced when the receiver syntactically resolves to a stdlib-collection type whose `(type, method)` pair is known to be a local mutation: `Array.append`/`insert`/`remove*`, `String.append`/`insert`, `Set.insert`/`remove`/`removeAll` (semantically idempotent), and `Dictionary.updateValue`/`removeValue`. This catches the common false-positive shape `users.append(contentsOf: teammates)` where `users` is a local `[User]`. Resolution is syntactic (parameter annotations, local bindings, stored-property types, literals) — when the resolver can't determine the receiver's type lexically it falls through to the bare-name behaviour unchanged.

**CamelCase-gated prefix matching.** The non-idempotent whitelist also matches prefix-style names — `sendEmail`, `createUser`, `publishEvent`, `insertRow`, `enqueueJob`, `appendUnique`, `postMessage` — when: (1) the callee name is strictly longer than the matched prefix, (2) the next character after the prefix is uppercase (Swift word boundary), and (3) the receiver is not a stdlib-collection. This deliberately does NOT match `sending`, `sender`, `publisher`, `postponed`, `creator`, `inserted`, `appending` — the lowercase-next-character rule identifies those as non-mutation forms. Diagnostic prose distinguishes prefix matches explicitly: "from the callee-name prefix `send` (in `sendEmail`)".

**Diagnostic prose makes inference visible.** Inference-driven diagnostics distinguish their provenance:

- Upward: "whose effect is inferred `non_idempotent` from its body"
- Heuristic-downward: "whose effect is inferred `non_idempotent` from the callee name `insert`"
- Declared: "which is declared `@lint.effect non_idempotent`"

All three variants suggest annotating the callee explicitly with `/// @lint.effect <tier>` as the override mechanism when the inference is wrong.

**Collision-withdrawn entries skip BOTH inference paths.** When the symbol table withdraws a callee's entry because of multiple conflicting annotations (the OI-4 collision policy), neither upward nor downward inference runs on that callee. The user's conflicting annotations already express ambiguity; substituting a third interpretation would paper over it.

**Two-hop chains** (A → B → C with A and B un-annotated, C declared non-idempotent) are a known Phase-2.3 first-slice limitation. Upward inference picks up B (one hop from C) but does not propagate further within the same pass. Users annotating the entry point (A) directly, or adding a declared effect on B, closes the gap.

### Interpretation of Zero Findings
This rule was annotation-gated in Phase 1; Phase 2's heuristic inference adds a fallback for un-annotated callees. Zero findings on un-annotated source now has a narrower meaning: "no caller annotated with `@lint.effect idempotent/observational/externally_idempotent` calls a callee either declared non-idempotent (or inferred non-idempotent by the whitelist)." A zero-finding result still tells you about annotation coverage on the caller side — the inference fallback does not itself produce diagnostics without an annotated caller context.

### Remediation
- **Swap the callee.** Replace a `non_idempotent` function with an idempotent alternative (e.g. `create` → `upsert`, `insert` → `setIfAbsent`).
- **Weaken the caller's annotation.** If the function genuinely does not guarantee idempotency, `@lint.effect non_idempotent` is the correct declaration.
- **Suppress with a reason.** Use `// swiftprojectlint:disable:next idempotency-violation` on the offending line when the violation is intentional and documented.

---
