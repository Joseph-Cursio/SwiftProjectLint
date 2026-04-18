[← Back to Rules](RULES.md)

## Once Contract Violation

**Identifier:** `Once Contract Violation`
**Category:** Idempotency
**Severity:** Error

### Rationale
The `/// @lint.context once` annotation is the inverse of `replayable` / `retry_safe`: the function asserts that it must run **at most once** across all replays, retries, or iterations. Common shapes are app bootstrap (`registerCrashReporter`), one-time migrations (`runDatabaseMigration_v3`), one-shot allocations (`reserveSlot`), and idempotency-key issuers (`mintNewIdempotencyKey`). The damage from a second invocation is typically silent — duplicate metric registration, two crash reporters racing, a second migration row, a fresh idempotency key that breaks dedup downstream. This rule flags call sites where the once-callee will obviously fire more than once.

### Discussion
`OnceContractViolationVisitor` walks every function body in the project and inspects every direct `FunctionCallExprSyntax`. For each call whose callee's symbol-table entry is `/// @lint.context once`, it checks two trigger conditions:

1. **Loop ancestry.** Walking the parent chain from the call up to (but not including) the enclosing function body, any node that is the `body` member of a `ForStmtSyntax`, `WhileStmtSyntax`, or `RepeatWhileStmtSyntax` triggers the loop case. Iteration sources (`for x in source()`) and loop conditions (`while cond()`, `repeat { ... } while cond()`) are NOT counted as in-loop — they evaluate once per loop entry, not per iteration.
2. **Caller context.** If the enclosing function declaration carries `/// @lint.context replayable` or `/// @lint.context retry_safe`, the call fires the replayable case.

When both triggers apply (a once-callee inside a loop inside a replayable body), a single combined diagnostic is emitted that mentions both factors and notes that they compound.

The rule resolves callees cross-file via the shared `EffectSymbolTable`, subject to the table's collision policy: two annotated declarations of the same signature with conflicting contexts withdraw the entry, and the rule then sees nothing for that signature.

### Phase 1 Scope

This is the direct-call-site check. The rule fires only when the call to the `@context once` callee is **lexically** inside the trigger position. Transitive propagation through un-annotated helpers — e.g. a `replayable` body calls `helper()` which itself calls a `@context once` function — is **not** detected. The multi-hop upward-inference call graph could be extended to track context propagation in a follow-up; until then, intermediate helpers between the trigger and the once-callee should be annotated explicitly.

### Violating Examples
```swift
/// @lint.context once
func registerCrashReporter() {}

/// @lint.context once
func runDatabaseMigration() {}

// Loop: registerCrashReporter fires per iteration
func bootEachShard(_ shards: [Shard]) {
    for _ in shards {
        registerCrashReporter()        // ← flagged
    }
}

// Replayable caller: runDatabaseMigration fires on every replay
/// @lint.context replayable
func handleStartupWebhook() {
    runDatabaseMigration()             // ← flagged
}

// Compound: loop within a replayable
/// @lint.context replayable
func handleBatch(_ items: [Item]) {
    for _ in items {
        registerCrashReporter()        // ← flagged with both-trigger message
    }
}
```

### Non-Violating Examples
```swift
/// @lint.context once
func registerCrashReporter() {}

/// @lint.context once
func loadInitialState() -> [Item] { [] }

// Plain straight-line call — once contract honoured
func main() {
    registerCrashReporter()
}

// Iteration source evaluates once per loop entry, not per iteration
func displayItems() {
    for item in loadInitialState() {   // not flagged: loadInitialState() runs once
        print(item)
    }
}

// While-condition evaluates as the loop control, treated as not-in-loop
func runUntilDone() {
    while shouldRetry() {              // not flagged even if shouldRetry is @once
        try? doWork()
    }
}
```

### Known Limitations

These shapes pass silently by design; deeper analysis to flag them lives in a future phase.

- **Transitive chains.** A `replayable` body calling an un-annotated helper that calls a `@context once` function is invisible. Annotate intermediate helpers explicitly until context propagation joins the multi-hop call graph.
- **Escaping closures.** `for x in xs { Task { onceCall() } }` does not fire — the closure-escape policy stops at `Task { }` / `withTaskGroup` / `Task.detached` / SwiftUI `.task { }`, mirroring the other idempotency visitors. The Task body still re-runs whenever the loop re-spawns it; detecting this cleanly requires cross-construct reasoning that the broader idempotency feature also defers.
- **Callback-style iteration.** `xs.forEach { onceCall() }` and `xs.map { onceCall() }` do not fire — the closure runs N times per call to `forEach` / `map`, but recognising those callees as iteration constructs requires a name list and risks false positives on user-defined methods that share those names. Use a `for-in` loop if you want the diagnostic to fire.
- **Nested function declarations.** A `@context once` call inside a nested `func` declaration is checked relative to the nested function's own body, not the outer function's. If the nested function is invoked in a loop in the outer body, the call is invisible.

### Interaction with Other Idempotency Rules

- **`nonIdempotentInRetryContext`** also fires on calls from `replayable` / `retry_safe` bodies, but its trigger is the *callee's effect* (`@lint.effect non_idempotent`). The two rules are independent: a function can be `@context once` without being `non_idempotent` (e.g. a one-time observation that's expensive), and vice versa. Adopt both annotations together when a function is both side-effecting and at-most-once.
- **`idempotencyViolation`** is concerned with the lattice of `@lint.effect`, not `@lint.context`. Once-contract violations are orthogonal.

### Remediation

- **Hoist out of the loop.** A one-shot setup belongs before the loop, not inside it.
- **Guard with a one-shot flag.** `dispatch_once`-style guards (`once.lock { … }`, `if !registered { register(); registered = true }`) make a second call a no-op. The annotation can stay because the guarded body is genuinely at-most-once.
- **Move out of the replayable body.** Bootstrap work that should run once per process belongs at process-init time, not inside a webhook handler that may replay.
- **Weaken the annotation.** If the function is actually safe to call multiple times, `@lint.context once` is the wrong claim. Remove it, or replace with `@lint.effect idempotent` if that's the honest contract.

---
