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
