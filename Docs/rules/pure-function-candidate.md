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
- is not `async`, and
- has a body with no obvious impurity markers — `print`, `NSLog`, `FileManager`, `URLSession`, `UserDefaults`, `NotificationCenter`, `DispatchQueue`, the `arc4random` family, `.random` / `.randomElement` / `.shuffled`.

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
