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

Uses in a parameter *default value* position are exempt — a defaulted `clock: () -> Date = { Date() }`
is itself the injection seam — as are test files.

### Three faults, one trigger

The same marker witnesses three different problems, and only one of them is about testability. The
rule reports all three, with different messages.

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

#### The identity may be reached through a computed `id`

The exemption used to require a stored binding literally named `id`. Several codebases cannot spell
it that way: a SwiftLint `identifier_name` minimum of three characters makes `id` unavailable as a
stored property, so the conformance is satisfied by

```swift
let identifier = UUID()
var id: UUID { identifier }
```

The gate was asking for a name the project's own configuration forbids. It now resolves a computed
`id` to the property it returns.

**The link is required, not just the conformance.** A second `UUID` on the same type that `id` does
not return is a different value — it may be a database key or a wire value — and stays reported.

The fabrication check runs *before* the `Identifiable` identity exemption, and that order matters:
`struct Response: Identifiable { let id = model.id ?? UUID() }` satisfies the exemption exactly, and
is also the shape of the four DTO defects that motivated the split.

#### Creating a value is not fabricating one

```swift
let sessionID = currentSessionID ?? UUID()   // no session yet, so make one
…
currentSessionID = sessionID                 // and it is now the session
```

What makes a fabrication a defect is that the invented value stands in for a **real one that exists
somewhere else** — a row's id, a file's modification date — so the two can disagree. When the value
is written back into the thing that was missing, there is no counterpart left to disagree with: it
*becomes* the answer. The one-statement form `current = current ?? UUID()` is the same thing.

These are **reclassified, not silenced.** They fall through to the rule's ordinary message, which is
true of them — a test still cannot pin the id — so the gate moves the corpus count by zero. The
gate stays shut when the `??` falls back from a call or a literal, because there is no storage a
later statement could be matched against.

#### Fresh read per access

A read that is the body of a computed property happens once per **access**, not once:

```swift
// One reference instant for every state resolution in a render pass
private var now: Date { Date() }
```

That comment is from `WaiversView`, and the declaration under it could not deliver what it claimed.
The view took seventeen reads of `now` in one pass — six across the summary tiles, four building
the groups below, one per waiver inside each filter — so a waiver crossing its expiry between the
tile count and the list underneath was counted "Active" above and shown under "Expired" below.

The rule already reported that line, as a value a test could not pin. That is true and is not what
was wrong with it: **the disagreement survives injection**, because a provider read seventeen times
still answers seventeen times. A reader who takes the ordinary advice threads a clock through every
call site and leaves the defect exactly where it was, which is why this shape gets its own sentence.

A name promises a value. `let` delivers one and `var … { }` does not, and the gap is invisible at
every use site — `now` reads identically either way. The fix is to read once at the top of the
operation that needs it and pass it down: `body` computes `let now = Date()`, the helpers take
`asOf: now`.

**The getter must be a single expression**, and that requirement came from the corpus rather than
from the tests. Without it the check reported `WaiversView` *after* the fix — `let now = Date()`
followed by a `return` — naming the remedy as the fault. A multi-statement getter has already given
the value a name, which is the whole repair; what is left is the shape where the property *is* the
read. Scoped to properties, not to zero-argument functions: `now()` reads as work at every call
site, `now` reads as a value, and only the second one misleads.

Like the lazy-creation gate, this **changes what the rule says and not what it counts** — 5 sites
across the sweep corpus, all already reported, all still reported.

### A closure parameter default is a seam too

The default-value exemption used to stop at any closure, so this was reported:

```swift
init(clock: @escaping @Sendable () -> Date = { Date() }) { … }
```

That is the shape this page offers as the fix, and the shape a reader who takes its advice ends up
writing. The corpus said so plainly: **three sites across two repositories carried a hand-written
`swiftprojectlint:disable:next` for this rule**, each with a comment beside it making the same
point — *"The seam itself, and the one place in this type that reads a clock. The rule is right that
this default reads ambient time — that is what a default is for."* Nobody had traced the
suppressions back here.

A default value is substitutable by construction, and it makes no difference whether what is handed
over is the instant (`= Date()`) or the capability that reads it (`= { Date() }`). A test passes
`{ fixedDate }` to either.

**The line held is `defaultValue`, not "is a closure."** A closure argument at a call site stays
reported: `items.map { Date() }` runs immediately, and `queue.async { stamp = Date() }` runs later
with nothing able to replace it. Only a parameter guarantees substitutability. A provider constant
like `DateProvider { Date() }` is outside it too — the substitutability there comes from the type
being a provider, which this rule cannot see, and the one in the corpus stays declined in writing
beside the code.

Corpus effect: **one finding**, and three suppression comments that no longer suppress anything.

### Two gates on the declines

Both were measured against the 26-repository sweep before being written, and together they remove
**21 of 164 findings**.

**A scratch path's name** (14 findings, eight repositories):

```swift
FileManager.default.temporaryDirectory
    .appendingPathComponent("import-\(UUID().uuidString)", isDirectory: true)
```

The uniqueness *is* the point — two concurrent callers handed the same name would collide — and
every one of these sites creates the directory, uses it, and deletes it on the way out. Nothing
compares the name, stores it, or sends it anywhere, so there is no second value for it to disagree
with, which is the same test the fabrication branch applies.

**Both spellings of the temporary directory count.** The gate matched
`FileManager.default.temporaryDirectory` at the head of a member chain, and the corpus also writes

```swift
URL(fileURLWithPath: NSTemporaryDirectory())
    .appendingPathComponent("spm-\(UUID().uuidString)")
```

where the call sits inside a `URL` initialiser instead. Same scratch path, same reason it needs no
seam, and the first version of the gate did not see it.

**Only an identity source**, and the first draft got that wrong: it exempted anything
nondeterministic in a temporary path name, which would have silenced `"run-\(Date())"` — and a
clock read used to make a name unique is the shape that produced a real defect in SwiftMarkdownWiki's
snapshot collision loop, which terminated *only* because the format carried milliseconds. A UUID is
a name that cannot collide; a timestamp is a name that usually does not, which is a different claim.

**A test-support target** (7 findings, one directory). `isTestOrFixtureFile()` already matched
`Tests/` and `FooTests/` folders; it now also matches folders ending `TestSupport`, `TestHelpers`,
`TestKit` and `TestFixtures`. Those are shipped library products rather than test targets, so
nothing about the path said "test" — but every symbol in them exists to be called from a test, and
their helpers are *deliberately* nondeterministic: a per-test `UserDefaults` suite name, a
per-process scratch root, a unique directory per call.

That check is shared with other rules, so the change was scoped by measurement rather than by
argument: across the corpus it matches four directories and 39 files, and it removed exactly seven
findings (all this rule's) and three candidate-census entries. No other rule moved.

### Why bare `.now` is not flagged

`Date.now` is reported; a leading-dot `.now` is not, and that is a decision rather than a gap.

Without type resolution the base is unknown, and the corpus contains
`ContinuousClock.Instant = .now` — a monotonic read this rule
[deliberately excludes](contradicted-clock-determinism.md). Classifying bare `.now` as a wall-clock
read would trade a false negative for a false positive of exactly the kind the scope note refuses.

`TupleEqualityWithUnstableComponentsVisitor` reached the same conclusion independently: *"Un-based
`.now` (leading-dot syntax with inferred base) is NOT flagged — without type resolution the base is
unknown."*

The practical consequence is worth stating, because it can be mistaken for progress: writing
`generatedAt: .now` instead of `Date.now` moves a clock read somewhere the tool cannot see, and the
rule's count falls. **A read the tool reports where it belongs is better than one it cannot find.**

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
