[← Back to Rules](RULES.md)

## Pure Function Property-Test Candidate

**Identifier:** `Pure Function Property-Test Candidate`
**Category:** Testability
**Severity:** Info

### Rationale
Most testability rules flag what makes code *hard* to test. This one is the positive signal: it surfaces functions that are already an ideal fit for property-based testing. A free or `static` function that takes inputs, returns a value, isn't `async`, and shows no obvious side effects is — to a first approximation — pure and total. Those are exactly the functions where properties (round-trips, invariants, idempotence, commutativity) pay off, and they're the seeds the `lint → infer → verify` pipeline hands to `swift-infer` to propose properties automatically.

### Discussion
`PureFunctionCandidateVisitor` flags a `FunctionDeclSyntax` that:
- is free (top-level) or `static` — instance methods can read mutable `self`, so they're excluded,
- takes at least one parameter,
- returns a non-`Void` value,
- is not `async`,
- has a body with no obvious impurity markers — `print`, `NSLog`, `FileManager`, `URLSession`, `UserDefaults`, `NotificationCenter`, `DispatchQueue`, the `arc4random` family, `.random` / `.randomElement` / `.shuffled`, and
- if it `throws`, raises only its **own** errors — see [Throwing candidates](#throwing-candidates-pure-but-partial).

The rule is deliberately conservative: it would rather stay silent than label an impure function pure. It is `info` severity (a suggestion, not a problem) and skips test files.

```swift
// Flagged — a clean property-test candidate
func clamp(_ x: Int, to range: ClosedRange<Int>) -> Int {
    min(max(x, range.lowerBound), range.upperBound)
}
// e.g. property: range.contains(clamp(x, to: range)) for all x
```

### Non-Violating Examples
```swift
// No return value — nothing to assert on
func log(_ message: String) { print(message) }

// No parameters — no input domain to quantify over
func makeDefault() -> Config { Config() }

// Impure body
func save(_ data: Data) -> Bool {
    UserDefaults.standard.set(data, forKey: "k"); return true
}

// Instance method reading MUTABLE state — two calls with the same argument can differ,
// so it is a function of nothing a test can pin down
struct Counter { var n = 0; func next() -> Int { n + 1 } }

// Instance method reading state this file cannot resolve — doubt refutes
extension Widget { func scaled(_ n: Int) -> Int { hidden * n } }

// THROWS by propagation — the error comes from a callee this rule cannot see, and so does
// whatever else that callee does. Doubt refutes.
func read(_ url: URL) throws -> String { try String(contentsOf: url, encoding: .utf8) }
```

### Violating Examples
```swift
// Pure, total, free function with inputs and an output — "a function of its inputs"
func add(_ a: Int, _ b: Int) -> Int { a + b }

// Static, pure
enum Geometry {
    static func area(width: Double, height: Double) -> Double { width * height }
}

// INSTANCE METHOD reading nothing from `self` — a free function that happens to live in a type
struct Calc { var total = 0; func add(_ a: Int, _ b: Int) -> Int { a + b } }

// INSTANCE METHOD reading only immutable stored state — "a function of `self` and its inputs".
// The test builds a `Pricing` first; that is a chore, not an obstacle.
struct Pricing { let rate: Double; func discounted(_ amount: Double) -> Double { amount * rate } }

// Nullary, over immutable stored state — `self` IS the input. Vary the value, not the arguments.
struct Receipt { let amount: Double; func formatted() -> String { String(amount) } }

// THROWS its own error — "pure but partial". The law narrows to the success set.
func parse(_ text: String) throws -> Int {
    guard let value = Int(text) else { throw ParseError.bad }
    return value
}
```

### Instance methods

Instance methods are candidates. What decides candidacy is **what a method reads from `self`**, not
whether it is free-standing:

| the body reads | verdict |
|---|---|
| nothing from `self` | **a function of its inputs** — same as a free function |
| only *immutable* stored properties | **a function of `self` and its inputs** — build a `self`, then generate the arguments |
| *mutable* or *computed* state | not a candidate — two calls with the same argument can differ |
| an identifier this file cannot resolve | not a candidate — doubt refutes |

Refusing instance methods outright (the old behaviour) left this rule nearly blind on application
code, where almost all logic is instance methods. Doubt still refutes, though: purity is the bottom
of the effect lattice and the most dangerous place to land wrongly, so an identifier that cannot be
tied to a parameter, a local, or a type is assumed to be instance state — even when it is a global.
Under-suggesting costs a missed test; over-suggesting costs a generated test that runs impure code
and lies about the result.

### Throwing candidates: pure but partial

A `throws` function can be a candidate. `throws` refutes **totality**, not referential transparency,
and only one of those makes a function untestable: a function that rejects the inputs it cannot map
is a deterministic function of its inputs on all the rest. The message says *"looks pure but
partial"* and the suggestion tells you to narrow the law's domain — compare `try? f(x)` on both
sides, so an input in the throwing domain is a no-op for the property rather than a failure.

**But only when the function throws its own errors.** A `try` into a callee refutes:

| the body | verdict |
|---|---|
| `guard let v = Int(text) else { throw ParseError.bad }` | **pure but partial** — it rejects an input |
| `try process.run()`, `try String(contentsOf: url)` | not a candidate — the throw, and whatever else the callee does, comes from code this rule cannot see |

That second gate is load-bearing, and the reason is worth knowing before anyone relaxes it. **The
old blanket `throws` exclusion was silently doing a second job**: nearly all real I/O in Swift
throws, so gating on `throws` masked every impurity marker the set does not name — `Process`,
`Pipe`, `FileHandle`, `String(contentsOf:)`, `Data(contentsOf:)`, the SQLite surface. Admitting
throwing candidates without the propagation check re-admitted all of them at once, and a
subprocess-spawning `runSwiftLint(executable:workingDirectory:lintFile:)` was judged pure — the
lattice-bottom mistake this rule exists to avoid. Measured on a real subject, the unnarrowed form
added 11 seeds of which ~10 were I/O; the narrowed form adds 3.

The cost is a pure function that happens to call another pure throwing function, refused for want of
a cross-file view. That is the sound direction.

### Access level: `internal` is the floor

A candidate is only useful if a test can *call* it. `@testable import` reaches `internal` and stops
— it does not reach `private` or `fileprivate`.

This rule still surfaces `private` candidates, and `swift-infer` will still write the law for one
when a seed names it, because knowing your pure logic exists is worth something. But no test can run
that law until the access widens. If a candidate is `private`, either widen it to `internal` or lift
the logic into a type of its own.

Note the tension with [Could Be Private Member](could-be-private-member.md), which will happily tell
you to narrow the very function this rule just flagged. That rule now names the cost when it does.

---

### Not listed in the default report

This rule is a **census**, and on a real codebase it is a large one: 464 findings here, alongside
208 from [Pure Closure Property-Test Candidate](pure-closure-candidate.md) — together **76% of
everything the linter prints**. A pure function is not a defect and there is nothing to fix per
line, so enumerating them buries the findings that *are* defects. During this project's own road
test the linter found a real bug in its configuration code, reported it correctly, and the finding
went unread in exactly that pile. Volume that large does not inform; it functions as silence.

So `--format text` counts these findings in its summary and names them in a footer, but does not
print one line each:

```
Found 884 issues (82 warnings, 802 info)

672 of these are property-test candidates, not listed above (464 Pure Function …, 208 Pure Closure …).
  See them:  --categories testability
  Use them:  --format pbt-seeds > .pbt/seeds.json
```

**Nothing is filtered out of detection.** The rule still runs, still counts toward the summary and
the exit code, and still populates the seed manifest — `--format pbt-seeds` is the pipeline's input
and would be emptied by any change that suppressed the rule itself. `--format json`, `csv` and
`html` also stay complete: a machine consumer filters for itself. Only the human listing is
shortened, and naming `testability` in `--categories` restores it in full.

This is [`../archive/PBT_TESTABILITY_RULES_SCOPE.md`](../archive/PBT_TESTABILITY_RULES_SCOPE.md) decision 5 —
*"Rule 5 opt-in (info, advisory)"* — arriving late, in the only place it can arrive without
breaking the handoff.
