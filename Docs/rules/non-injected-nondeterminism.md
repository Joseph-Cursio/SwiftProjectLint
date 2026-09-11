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

### Four faults, one trigger

The same marker witnesses four different situations, and only one of them is a testability problem
you can fix by injecting anything. The rule reports all four, with different messages.

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
Three independent instances, one failure mode each time:

| Where | What the fabricated value did |
| --- | --- |
| A file whose modification date the file system did not report | Looked like the newest thing on disk, won every comparison, and silently uploaded over the server's copy |
| A CI run with no finish time | Won `max(existing.lastOccurrence, incoming)` and pinned the anti-pattern's last occurrence to poll time |
| A note with no recorded date | Never matched its search-index entry, so it was re-indexed on every refresh, forever |

The fix is to propagate the `nil` so callers can say *unknown*, or to refuse — Fluent's
`try requireID()` is the idiom.

This fault *is* a local syntactic shape, which is the only reason it can be separated from the
first. **It is also rare, and worth knowing that before you go looking**: across 23 Swift
repositories it occurred 7 times in production code, 2 of them live defects and 2 more already
unreachable by construction. It is kept
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
true of them — a test still cannot pin the id — so the reported count does not change. The
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

**The getter must be a single expression.** Without that requirement the check reports a view
*after* it has been fixed — `let now = Date()` followed by a `return` — naming the remedy as the
fault. A multi-statement getter has already given
the value a name, which is the whole repair; what is left is the shape where the property *is* the
read. Scoped to properties, not to zero-argument functions: `now()` reads as work at every call
site, `now` reads as a value, and only the second one misleads.

Like the lazy-creation gate, this **changes what the rule says and not what it counts**: the same
sites are reported, with a message that names the fault they actually have.

#### Handed straight on — a composition-root read

The read's value becomes a call argument and this scope never looks at it again:

```swift
store.approve(proposalID: id, by: reviewer, on: Date())

let now = Date()
summary(asOf: now)
content(asOf: now)
```

**This is what following the rest of this rule's advice produces**, which is why it needed its own
sentence rather than a gate. The ordinary message says a property-based test cannot pin the value.
At a composition root that is false about everything that decides: the callee takes the instant as
a parameter and a test pins it there. The only unpinnable thing is the expression itself, which
contains no logic. A reader who moved every clock read to the edge — exactly what this rule asked
for — was still being told their code was untestable.

So the message changes and the count does not. These sites were already reported and still are;
see [A composition-root read stays reported](#a-composition-root-read-stays-reported-and-that-is-deliberate)
for why suppressing them would be worse than reporting them.

**Argument position only, and that restriction is the whole precision.** A receiver is not handing
the value on, it is *using* it — and every real defect this rule has produced across the corpus
reads the clock into a receiver or an operand, never into a bare argument:

| Shape | What the scope did with it |
| --- | --- |
| `Date().addingTimeInterval(timeout)` | a subprocess deadline |
| `Date().timeIntervalSince(start)` | the entire output of a benchmark |
| `Date.now.timeIntervalSince1970` | a number bound into SQL |
| `"probe_\(UUID().uuidString).swift"` | a filename this scope composed |

**A member that only re-presents the value is reached through.** A receiver is normally the scope
*using* the value, and that is where every defect this rule has produced lives — but four of the nine
sites this arm could not reach were receivers that merely change the value's type and then hand it on:
`Date.now.formatted(date: .abbreviated, time: .shortened)` bound and passed as a `timestamp:`,
`bind(Date.now.timeIntervalSince1970, at: 1)`, `R(identifier: UUID().uuidString, …)`. None of those is
a decision.

The distinction is whether the member's arguments **reach into the scope**:

| expression | arguments | what it is |
| --- | --- | --- |
| `.uuidString` | none | the same identity as text |
| `.timeIntervalSince1970` | none | the same instant as a number |
| `.httpHeader` | none | the same instant as an RFC1123 header |
| `.formatted(date: .abbreviated, time: .shortened)` | leading-dot style options | the same instant, formatted |
| `.addingTimeInterval(timeout)` | **`timeout`** | a deadline |
| `.timeIntervalSince(start)` | **`start`** | an elapsed time — a benchmark's whole output |

An argument may contain literals and leading-dot members and nothing else; one bare identifier and the
member counts as combining, because resolving whether that identifier is a local, a parameter or a
static constant is a scope walk, and guessing it wrong turns a deadline into an end state. A trailing
closure is never inert.

**Re-presentation alone is not enough** — the result still has to be handed on. A formatted instant
that is *returned* rather than passed keeps the ordinary message, as does one interpolated into a
string. Measured: 3 of our 34 findings reclassified and 2 of 37 in third-party checkouts, with none
added or removed in either set.

The bound spelling counts too — `let now = Date()` then only `f(asOf: now)` — and it demands that
**every** reference to the binding is itself an argument. One comparison, one piece of arithmetic,
one `return`, and the binding keeps the ordinary message. That is the safe direction: a shadowed
name can only add a reference that must also pass, never excuse one that does not. A stored
property's initial value is *not* a composition root, because the read happens once per instance
and the uses are in members this walk cannot see — `WaiverRequestSheet`'s
`@State private var openedAt = Date()` is the corpus instance, and it feeds arithmetic two lines
below.

**The message does not say "no action", and that distinction is load-bearing.** The corpus's one
live defect of this shape was

```swift
for entry in filtered { … }                       // the whole eval run
let report = EvalReport(gitSHA: sha, startedAt: Date(), results: results)
```

— `startedAt` read *after* the loop, so the `started_at` column of `swift-assist-eval history` and
every report filename carried the instant each run **finished**. Nothing there is untestable and
nothing is fabricated; the read is simply taken at the wrong moment. A message that closed the
finding would have hidden it, so the suggestion asks the one question this shape can still get
wrong: *is the value read at the moment its label claims?*

**Measured before shipping, and the estimate was wrong in the usual direction.** Reading all 37
corpus findings by hand suggested the arm would reach about 34. The inline form alone reached
**20 of 37**; adding the bound form took it to **25**. That is the fifth time a prediction about a
rule on this project has come in high, and the second on this rule.

**The arm reclassifies and never removes**, which is asserted by a test rather than assumed: the
corpus reported 37 before and 37 after, with 20 of them carrying the new sentence. The rule now
reports 34 across the corpus, and the missing three are declines merged separately — an edge-case
generator whose filler is arbitrary by design, and a deliberately broken `Hashable` conformance in
a book chapter that exists to be falsified. Both are the shape
[the decline section](#when-a-suppression-is-right) names.

The nine that keep the ordinary message are worth listing, because they are what the arm is
*not* claiming: two stamps assigned to storage, a lazy-created session id, a `@State` initial
value that feeds arithmetic, and four receivers — `Date.now.formatted(…)`,
`Date.now.timeIntervalSince1970`, `UUID().uuidString`, and a `UUID()` interpolated into a probe
filename.

### Two shapes where the finding is right and "inject the source" is wrong

The three faults above each carry their own message, because each is a local syntactic shape the
visitor can recognise. These two are not. They report under the ordinary message and they cannot do
better, because nothing at the expression tells them apart — you find them by reading the enclosing
function, or by grepping for a reader that does not exist. They are documented here because a
reader who takes the ordinary advice at either one does real work and fixes nothing.

Between them these two shapes account for most of what a dense file reports, so recognising them
is worth more than working such a file line by line.

#### The value is a placeholder for a feature that does not exist

`AdminRoutes.swift` held **12 findings — the largest single cluster this rule has produced** — and
every one sat inside a stub:

```swift
static func getActivityLog(req _: Request) async throws -> ActivityLogResponse {
    // For now, we'll return a simple activity log
    // In a real implementation, you'd have an ActivityLog model
    let activities = [
        ActivityLogEntry(id: UUID(), userId: UUID(), action: "file_upload", timestamp: Date()),
        …
```

Four registered, admin-authenticated endpoints answering with invented data: an activity log of two
hardcoded rows, a **100 MB backup that does not exist** reported as `completed`, and a restore that
returned `.ok` for any id including one never issued. Three of the four ignore their `Request`
entirely and none touches the database.

Injecting a clock and a UUID provider clears all twelve findings and leaves every one of those
behaviours in place. The fix is `501 Not Implemented` — or an implementation. The tells are in the
file already: a `req _:` parameter, a comment beginning *"For now"* or *"In a real
implementation"*, and a handler that constructs its whole response from literals.

#### The value has no reader

`SyncError.timestamp` was filled by five clock reads at five construction sites, and read by **no
view, no log, and no test**. The type's own documentation called it *"for logging"*; nothing logs
it. Five reads to populate a field that no code consumes.

The fabrication branch above says of its examples that *"they are stored and shown"*. This is
weaker than that — it is stored and **not** shown, which puts it outside every disposition on this
page. Injecting makes five unread values reproducible.

The fix is to delete the field. If the value is wanted, it needs a reader first — a log line, an
ordered error list — and then one instant per operation rather than five independent reads. The
same call was made once before on this type, recorded in its own docstring: the file field used to
be a `MacCloudFile?` that the two failing paths could not supply.

A stored-property default is the same shape when nothing has happened yet:

```swift
var lastSyncTime = Date()   // a cold start reports "Last sync: now"
```

`SyncStatusCard` renders that relative, so a freshly launched app claims a sync that never ran. It
is `Date?` now, `nil` until one completes.

#### And a fault recurs at its call sites after the fix exists

The fabrication table above lists the note-date defect as found. What it does not
say is that `NoteFile.read(at:)` — the helper written to prevent it, carrying the reasoning in its
docstring — was still being bypassed by **five call sites** constructing
`NoteFile(url:modifiedDate: Date())` directly, each immediately after writing the file, where the
real modification date was there to be read.

A fixed fault is fixed at the sites that existed when it was fixed. `grep` for the constructor the
helper replaced is worth a minute after any repair of this kind.

### A closure parameter default is a seam too

The default-value exemption used to stop at any closure, so this was reported:

```swift
init(clock: @escaping @Sendable () -> Date = { Date() }) { … }
```

That is the shape this page offers as the fix, and the shape a reader who takes its advice ends up
writing — and readers said so before the rule was corrected: **three sites carried a hand-written
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
being a provider, which this rule cannot see, so that shape stays declined in writing beside the
code.

The effect on any count is negligible; what changes is that three hand-written suppressions no longer suppress anything, because the rule stopped reporting what they were written for.

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
`FileManager.default.temporaryDirectory` at the head of a member chain, and real code also writes

```swift
URL(fileURLWithPath: NSTemporaryDirectory())
    .appendingPathComponent("spm-\(UUID().uuidString)")
```

where the call sits inside a `URL` initialiser instead. Same scratch path, same reason it needs no
seam, and the first version of the gate did not see it.

**Only an identity source**, and the first draft got that wrong: it exempted anything
nondeterministic in a temporary path name, which would have silenced `"run-\(Date())"` — and a
clock read used to make a name unique is the shape that produced a real defect in a vault app's
snapshot collision loop, which terminated *only* because the format carried milliseconds. A UUID is
a name that cannot collide; a timestamp is a name that usually does not, which is a different claim.

**A test-support target** (7 findings, one directory). `isTestOrFixtureFile()` already matched
`Tests/` and `FooTests/` folders; it now also matches folders ending `TestSupport`, `TestHelpers`,
`TestKit` and `TestFixtures`. Those are shipped library products rather than test targets, so
nothing about the path said "test" — but every symbol in them exists to be called from a test, and
their helpers are *deliberately* nondeterministic: a per-test `UserDefaults` suite name, a
per-process scratch root, a unique directory per call.

That check is shared with other rules, so its blast radius is worth measuring before changing it —
a widened definition of "test support" silences findings under rules that have nothing to do with
this one.

### A composition-root read stays reported, and that is deliberate

**The count for this rule is a census of clock reads, not a backlog of clock problems.** Every
finding it makes is a real read of a real clock. Some of those reads are in the right place, and
they are still reported.

That is the intended end state for most of them. The fix for an inline clock read is almost never to
delete it — the program does need to know the time — it is to *move* it to the edge, where a caller
supplies it and everything underneath becomes a function of its arguments. The read survives the
refactor by design:

```swift
var body: some View {
    let now = Date()              // still reported, and correct
    return VStack {
        summary(asOf: now)        // pure, testable, fed one instant
        content(asOf: now)
    }
}
```

**Expect the count not to move when you fix one of these.** Repairing a view that read the clock
seventeen times per render leaves one read, in the right place, and one finding — which is correct.
A codebase that has done the work everywhere still reports one finding per composition root, and
that list is the point rather than a backlog.

Injection is occasionally the right fix, and the shape to look for is a seam that stops one step
short: `GitAdapter`'s `commitMessage` was already an injectable `(Date) -> String`, so a test could
control the *format* of an auto-commit subject but not the instant inside it — which is the part
that lands in the git log.

**Do not suppress these.** A `swiftprojectlint:disable` at a composition root buys a smaller number
and loses the inventory — and the inventory is what this rule is for. If you want to know where a
program touches the clock, this list is the answer, and a suppressed entry is a lie about the
program rather than a decline of a finding.

#### When a suppression *is* right

Suppress where the rule is wrong about the site permanently, not where it is right and you have
already acted. The sites that qualify share a shape: **the nondeterminism is the declared purpose
of the code, and no caller could supply it instead.**

```swift
// The production half of an injection seam. Its whole job is to read the clock;
// the type exists so that tests can pass the other half.
// swiftprojectlint:disable:next non-injected-nondeterminism
public static let system = DateProvider { Date() }

// A scratch filename that is created, used, and deleted inside one call.
// Nothing compares it, stores it, or sends it anywhere.
// swiftprojectlint:disable:next non-injected-nondeterminism
let tempName = "\(destination.lastPathComponent).\(UUID().uuidString).tmp"
```

A third shape belongs here, and it is the one where taking this page's advice does harm rather than
nothing: **the value is a nonce.**

```swift
// This is a nonce. A caller that could supply it is the property the value exists
// to deny, so an injection seam here is a security regression, not a testability win.
// swiftprojectlint:disable:next non-injected-nondeterminism
let tokenId = UUID().uuidString
```

`AuthRoutes.generateRefreshToken` reads unpredictably *on purpose*. It also has no reader — no
revocation store keys on it yet — which is the shape two sections above, whose disposition is
deletion. Both of that section's tells were present and both conclusions were wrong: the claim is
inside signed tokens already issued, and it is the exact claim a revocation store would key on.

The discriminator is not "is the value read?" but **"would a caller supplying it be a bug?"** For a
clock or a fixture the answer is no, which is why injection works. For a nonce, a session id, a
CSRF token or a salt the answer is yes, and no amount of unread-ness changes it.

Both of the first two are cases where a reader arriving at the finding would otherwise re-derive the
same conclusion every sweep; the third is a case where a reader who does the re-derivation and acts
on it makes the program worse. Write the reasoning beside the directive — a bare suppression is
worse than the finding, because the next reader cannot tell a decision from a dismissal.

**And re-check a suppression when the rule changes.** Three directives were written here
because the rule reported `clock: () -> Date = { Date() }`, the shape its own documentation
prescribes. When that was corrected the directives suppressed nothing, and each still read as an
active disagreement with the rule. They were removed. `grep -rn "swiftprojectlint:disable"` after a
rule change is the cheapest audit available.

### Why bare `.now` is not flagged

`Date.now` is reported; a leading-dot `.now` is not, and that is a decision rather than a gap.

Without type resolution the base is unknown, and real code contains
`ContinuousClock.Instant = .now` — a monotonic read this rule
[deliberately excludes](contradicted-clock-determinism.md). Classifying bare `.now` as a wall-clock
read would trade a false negative for a false positive of exactly the kind the scope note refuses.

`TupleEqualityWithUnstableComponentsVisitor` reached the same conclusion independently: *"Un-based
`.now` (leading-dot syntax with inferred base) is NOT flagged — without type resolution the base is
unknown."*

The practical consequence is worth stating, because it can be mistaken for progress: writing
`generatedAt: .now` instead of `Date.now` moves a clock read somewhere the tool cannot see, and the
rule's count falls. **A read the tool reports where it belongs is better than one it cannot find.**

### Preview fixtures are not flagged

A `#Preview` never ships, and the values in one are fixtures rather than program state. `Date()`
beside a hardcoded violation count and a literal version string is part of the fixture, and there is
no caller who could supply it — the preview *is* the caller. Asking for an injected clock there
means routing one in from somewhere, which is what a preview exists to avoid.

Both spellings are skipped: `#Preview { }` parses as a declaration among other declarations and as
an *expression* when it is the only item in a file, which is exactly the file a preview tends to
live in. A preview nested inside `#if DEBUG` is covered by the same counter.

**The gate is the preview, not the file.** A view and its preview live together, and the view's own
clock reads are the case this rule exists for.

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
