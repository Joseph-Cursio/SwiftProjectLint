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

// Instance method — may depend on mutable self
struct Counter { var n = 0; func next() -> Int { n + 1 } }
```

### Violating Examples
```swift
// Pure, total, free function with inputs and an output
func add(_ a: Int, _ b: Int) -> Int { a + b }

// Static, pure
enum Geometry {
    static func area(width: Double, height: Double) -> Double { width * height }
}
```

---
