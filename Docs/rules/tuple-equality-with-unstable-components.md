[← Back to Rules](RULES.md)

## Tuple Equality With Unstable Components

**Identifier:** `Tuple Equality With Unstable Components`
**Category:** Idempotency
**Severity:** Warning

### Rationale
Tuple equality is structural: `(a, b) == (c, d)` succeeds only when *every* positional element is `==`. When one of those elements is produced by a time source, a randomness source, or a per-call identity source, the comparison can never converge on a replay — the clock has moved, the UUID has changed, the random draw has re-rolled. This is the hidden hazard behind caching guards, memoisation checks, and idempotency guards that "sometimes work" in production and fail mysteriously under retry.

```swift
// Looks like a cache hit test. It is actually unconditionally false on replay.
if (input, Date()) == previousInput {
    return cachedResult
}
```

Either the guard is dead code (the `Date()` side always differs, so the `==` always fails), or the guard is live but tests the wrong thing (the author probably meant to compare `input` alone, and the `Date()` slipped in as a habit of "include everything relevant"). Either way, there's no defensible semantic reading of a structural tuple that carries an unstable field.

### Discussion
`TupleEqualityWithUnstableComponentsVisitor` is a file-local SyntaxVisitor. It inspects every `SequenceExprSyntax` of the shape `[TupleExpr, ==/!=, TupleExpr]` — literal tuples on both sides — and flags the comparison when any element on either side matches one of the unstable heuristics below.

The rule is deliberately scoped narrow:

- **Literal tuples only.** `tupleA == tupleB` where the tuples are stored in variables would require type resolution to reach through the reference. The rule doesn't do that; variable-ref tuple equality is silently skipped.
- **Arity ≥ 2.** `(x) == (y)` is a single-element parenthesised expression, not a tuple. Not flagged.
- **`==` and `!=` only.** Tuple ordering operators (`<`, `<=`, etc.) have a different semantic — lexicographic comparison — and are out of scope.
- **Stable constructor forms pass.** `Date(timeIntervalSince1970: value)` is value-driven and produces the same `Date` for the same input. Only the zero-argument `Date()` / `UUID()` reads external state.

### Unstable markers
The following are recognised as unstable on read:

- **Zero-argument constructors:** `Date()`, `UUID()`
- **Zero-argument functions:** `CFAbsoluteTimeGetCurrent()`, `mach_absolute_time()`
- **Typed clock reads:** `Date.now`, `Date.now()`, `DispatchTime.now()`, `ContinuousClock.now`, `SuspendingClock.now`
- **Explicit randomness:** `Int.random(in:)`, `Double.random(in:)`, `Bool.random()`, and the other numeric `.random(...)` forms
- **Conventionally unstable identifiers (exact match):** `now`, `timestamp`, `nonce`

The identifier list is deliberately short. Names like `date`, `time`, and `id` are too ambiguous — they often label *stable stored values* rather than reads-from-now — and are intentionally **not** flagged. If a stored `date: Date` field is in fact a live clock read, that's a separate modelling problem the linter can't see through.

### Violating Examples

```swift
// Hidden retry hazard in a cache guard
func handle(userID: String, prev: (String, Date)) -> Cached {
    if (userID, Date()) == prev {              // flagged: Date()
        return cached
    }
    return compute()
}

// Memoisation keyed on a per-call nonce — never hits
func memo(value: Int, nonce: UUID, prev: UUID) -> Int {
    if (value, UUID()) == (value, prev) {      // flagged: UUID()
        return cachedValue
    }
    return recompute(value)
}

// Randomness in an equality check
func isEqual(_ a: Int, _ b: Int) -> Bool {
    (a, Int.random(in: 0..<100)) == (b, 50)    // flagged: Int.random
}

// Named identifiers that are nonces by convention
func sameRequest(
    id: String,
    nonce: String,
    prev: (id: String, nonce: String)
) -> Bool {
    (id, nonce) == (prev.id, prev.nonce)       // flagged: 'nonce'
}
```

### Non-Violating Examples

```swift
// Stable identity — no unstable field
func isSame(_ lhs: (String, Int), _ rhs: (String, Int)) -> Bool {
    lhs == rhs                                  // no diagnostic — not a literal tuple
}

// Coordinate pairs are fine
func isAtOrigin(_ point: (Int, Int)) -> Bool {
    point == (0, 0)                             // no diagnostic — stable literal
}

// Value-driven Date init is stable
func hasSameWindow(_ a: Int, _ b: Int, epoch: TimeInterval) -> Bool {
    (a, Date(timeIntervalSince1970: epoch))
        == (b, Date(timeIntervalSince1970: epoch))   // no diagnostic
}

// Tuple creation, not equality — fine
func latestSnapshot() -> (Int, Date) {
    return (counter, Date())                    // no diagnostic
}

// Ordering comparisons are out of scope
func precedes(_ a: Int, _ b: Int) -> Bool {
    (a, Date()) < (b, Date())                   // no diagnostic — not == / !=
}

// Ambiguous identifier name — might be a stable stored value
func isSame(_ a: Int, _ b: Int, date: Date, prev: Date) -> Bool {
    (a, date) == (b, prev)                      // no diagnostic — 'date' not flagged
}
```

### Typical Application
High-value targets for this rule are anywhere tuple equality is used as a *control-flow guard* — caching layers, memoisation tables, change-detection hooks, idempotency guards in retry-prone handlers, and dedup logic in queue workers. The surface is small but the findings almost always represent real bugs: if you see this warning fire, the equality check either does not work, or does not check what you think it checks.

The rule does not require annotations. It runs on every file and fires on the shape alone, so it's effective without an idempotency-annotation campaign.

### Remediation
- **Drop the unstable field.** If the intent was to compare the stable subset, do so: `input == previousInput.input`.
- **Promote to a struct with tailored `Equatable`.** When the comparison really does need to span multiple fields, define a struct and give it an `Equatable` implementation that reflects semantic identity rather than structural identity:

  ```swift
  struct CacheKey: Equatable {
      let userID: String
      // no timestamp field — that's diagnostic metadata, not identity
  }
  ```

- **Compare against a stable snapshot.** If time or randomness really is load-bearing, hoist the unstable read to a single capture point and compare against the stored value on both sides:

  ```swift
  let snapshot = Date()
  if (input, snapshot) == previousInput { ... }   // previousInput.1 is a stored Date
  ```

  In this form the rule still fires (shape heuristic), but the argument that the comparison is well-posed is now at least coherent; a `swiftprojectlint:disable` annotation is appropriate.

### Suppression
For cases where you have confirmed the shape is intentional, suppress with:

```swift
// swiftprojectlint:disable tuple-equality-with-unstable-components
if (input, snapshot) == previousInput { ... }
```

### Interpretation of Zero Findings
A zero-finding result on a corpus is the expected outcome — tuple equality is uncommon in idiomatic Swift, and its combination with unstable reads is narrower still. When the rule does fire, the finding is high-confidence.

---
