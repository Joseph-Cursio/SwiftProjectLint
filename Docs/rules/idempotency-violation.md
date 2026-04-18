[← Back to Rules](RULES.md)

## Idempotency Violation

**Identifier:** `Idempotency Violation`
**Category:** Idempotency
**Severity:** Error

### Rationale
A function can declare its effect contract via `/// @lint.effect` in its doc comment. Once declared, callers depend on that contract — a function trusted as idempotent is trusted because of its annotation, and silent violations of the annotation undermine the entire annotation layer. This rule verifies that a function's body respects the effect it claims.

### Discussion
`IdempotencyViolationVisitor` walks each function declaration in the project, reads its `@lint.effect` annotation, and — for callers declared `idempotent` or `observational` — checks every direct call in the body against the project-wide `EffectSymbolTable`. The visitor resolves callees by full function signature (name + argument labels), so overloads that Swift distinguishes resolve independently. Unannotated callees are silent (Phase 1 does not infer); callees whose symbol-table entry was withdrawn by a collision are also silent.

The rule covers three combinations:

| Caller effect | Callee effect | Fires? |
|---|---|:-:|
| `idempotent` | `non_idempotent` | ✓ |
| `observational` | `idempotent` | ✓ |
| `observational` | `non_idempotent` | ✓ |

All other combinations are permissible under the Phase-1 lattice. In particular, `idempotent` can freely call `observational` (logging inside an idempotent function is fine), and either can call unannotated callees without a diagnostic.

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

### Interpretation of Zero Findings
This rule is annotation-gated: it can fire only when both caller and callee carry `@lint.effect` declarations visible to the project-wide symbol table. On un-annotated source it produces nothing — that is neither a safety signal nor a defect. Diagnostics accumulate as the annotation campaign progresses. A zero-finding result on an un-annotated codebase tells you about annotation coverage, not about whether the code contains the class of bug the rule targets.

### Remediation
- **Swap the callee.** Replace a `non_idempotent` function with an idempotent alternative (e.g. `create` → `upsert`, `insert` → `setIfAbsent`).
- **Weaken the caller's annotation.** If the function genuinely does not guarantee idempotency, `@lint.effect non_idempotent` is the correct declaration.
- **Suppress with a reason.** Use `// swiftprojectlint:disable:next idempotency-violation` on the offending line when the violation is intentional and documented.

---
