[← Back to Rules](RULES.md)

## Non-Injected Nondeterminism

**Identifier:** `Non-Injected Nondeterminism`
**Category:** Testability
**Severity:** Warning

### Rationale
A property-based test re-runs logic against many randomized inputs and, when it finds a failure, replays the exact same case to shrink it. That contract breaks if the code under test reads a nondeterministic source inline — the current time, a fresh UUID, a random number. Two runs with identical inputs produce different results, so failures can't be reproduced and shrinking is meaningless. Injecting the source (a clock, a `RandomNumberGenerator`, a UUID provider) lets a test pin it to a fixed value.

### Discussion
`NonInjectedNondeterminismVisitor` flags inline nondeterministic sources used in logic:
- No-argument `Date()` and `UUID()` initializers
- `.random(in:)` / `.random()`, `.randomElement()`, `.shuffled()`
- The C RNG family: `arc4random`, `arc4random_uniform`, `drand48`, and `CFAbsoluteTimeGetCurrent`
- Ambient clock/locale reads: `Date.now`, `Locale.current`, `TimeZone.current`

Uses in a parameter *default value* position are exempt (a defaulted `clock: () -> Date = { Date() }` is itself the injection seam), as are test files.

### Two faults, one trigger

The same marker witnesses two different problems, and only one of them is about testability. The
rule reports both, with different messages.

**Cannot control the value.** A clock or an RNG read inline, feeding a bound, a branch or a retry
window. The value is real; a test cannot pin it. The discriminator this fault wants — does the
value feed a *decision*, or is it only stored and shown? — is not decidable from the expression's
own syntax (`lastRunDate = Date()` reads as a record until you find the later
`Date().timeIntervalSince(lastRunDate)` that makes it a bound), so the message carries it as advice
rather than applying it as a gate.

**Fabricates the value.** A nondeterministic source as the fallback of `??`, standing in for a
value that was absent:

```swift
id = model.id ?? UUID()
modifiedDate = attributes.contentModificationDate ?? Date()
lastOccurrence = result.finishedAt ?? Date()
```

Nothing computes with these in the sense above — they are stored and shown, exactly the shape the
first fault's advice waves through — and that advice is wrong here. Injecting a clock makes the
invention *reproducible*, not correct.

The harm is specific. `Date()` is the largest instant in the system and `UUID()` matches no row, so
an invented value does not merely differ from the real one: **it wins every comparison it enters.**
Three independent instances found across the corpus, one failure mode each time:

| Where | What the fabricated value did |
| --- | --- |
| A file whose modification date the file system did not report | Looked like the newest thing on disk, won every comparison, and silently uploaded over the server's copy |
| A CI run with no finish time | Won `max(existing.lastOccurrence, incoming)` and pinned the anti-pattern's last occurrence to poll time |
| A note with no recorded date | Never matched its search-index entry, so it was re-indexed on every refresh, forever |

The fix is to propagate the `nil` so callers can say *unknown*, or to refuse — Fluent's
`try requireID()` is the idiom.

This fault *is* a local syntactic shape, which is the only reason it can be separated from the
first. Measured across the sweep corpus before the split: **7 production occurrences in 23
repositories**, 2 of them live defects and 2 more already unreachable by construction. It is kept
inside this rule rather than promoted to its own, because every one of these sites was already
reported here and moving them would hand new findings to anyone who had disabled the rule.

The fabrication check runs *before* the `Identifiable` identity exemption, and that order matters:
`struct Response: Identifiable { let id = model.id ?? UUID() }` satisfies the exemption exactly, and
is also the shape of the four DTO defects that motivated the split.

### What this rule deliberately does not flag

`ContinuousClock()`, `SuspendingClock()`, `Task.sleep(for:)`, `DispatchTime.now()`, the monotonic C functions (`mach_absolute_time`, `clock_gettime`), and `Date(timeIntervalSinceNow:)` all read a clock, and none of them are reported here.

The line this rule draws is **arity**: a construction taking no input can only have come from ambient state. `Date(timeIntervalSinceNow: 60)` takes one, so it falls outside — a known miss, kept rather than quietly closed.

The rest are the subject of [Contradicted Clock Determinism](contradicted-clock-determinism.md), which reports them only where a function claimed `@ClockDeterministic` and its body says otherwise. Both rules read the same classifier in SwiftEffectInference, so they cannot disagree about *what* an expression is — only about which of them should report it.

Widening this rule to the fuller clock set is a decision to take on its own evidence. It briefly happened as a side effect of de-duplicating the two implementations, and was reverted: a rule that widens because its dependency learned new spellings has a scope nobody chose.

```swift
// Before — reads the clock inline; can't be pinned by a test
func isExpired(_ token: Token) -> Bool {
    token.expiry < Date()
}

// After — the clock is injected; a test passes a fixed Date
func isExpired(_ token: Token, now: Date) -> Bool {
    token.expiry < now
}
```

### Non-Violating Examples
```swift
// Injected via a parameter default — this IS the seam
func makeID(_ uuid: UUID = UUID()) -> String { uuid.uuidString }

// Seeded, deterministic RNG passed in
func pick<T>(_ xs: [T], using rng: inout some RandomNumberGenerator) -> T? {
    xs.randomElement(using: &rng)
}
```

### Violating Examples
```swift
// Inline clock read in business logic
let elapsed = CFAbsoluteTimeGetCurrent() - start

// Inline randomness
let bucket = Int.random(in: 0..<10)
let winner = entrants.randomElement()
```

---
