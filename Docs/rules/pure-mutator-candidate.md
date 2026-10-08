[← Back to Rules](RULES.md)

## Pure Mutator Property-Test Candidate

**Identifier:** `Pure Mutator Property-Test Candidate`
**Category:** Testability
**Severity:** Info

### Rationale
[Pure Function Property-Test Candidate](pure-function-candidate.md) needs a returned result to assert on, so it refuses every function that returns `Void` — including the ones whose whole job is a pure transformation of one value. A **mutator** has a result all the same: the value it leaves behind. A test copies the value, applies the mutator, and compares, and the laws a mutator owes are often the interesting ones:

- **idempotence** — applied twice, it changes nothing the first application did not (`var once = x; f(&once); var twice = once; f(&twice); once == twice`);
- **determinism** — two copies given the same inputs end equal.

SwiftLintRuleStudio's `MigrationAssistant.applyMigration(_:to:)` is the shape that motivated it: a migration written through `inout`, which should be idempotent, and which the seed manifest never named.

### Discussion
`PureMutatorCandidateVisitor` reports, through `PropertyTestCandidacy.mutatorCandidate(of:…)`:

- a function with exactly **one** `inout` parameter that returns nothing and is not `mutating` — judged for its call shape like any candidate (free, `static`, or an instance method that reads no mutable state); or
- a **`mutating` method** of a `struct` or `enum` (or an extension the project knows extends one) with no `inout` parameter — it changes `self`.

Either must be pure by the shared oracle, not `async`, and not reach an impure package function in one hop. The oracle already reads a write to an `inout` parameter or to a `mutating` method's `self` as the function's own output, and still refutes a clock read or a `print` beside it. A `throws` mutator is reported as partial, as a throwing function is.

The mutated value must be comparable. When it is not but a bare `: Equatable` would make it so, the function is reported by [Missing Equatable on Pure Function Result](missing-equatable-on-pure-result.md) instead, so the two never name the same declaration. A mutator whose value needs a hand-written `==` — or holds a type from another package that its resolved checkout does not declare `Equatable` — is not reported.

Like the other candidate rules this is a **census**: there is nothing to do per item, so a default report counts these findings rather than listing them (`--categories testability` lists them). Each one seeds the manifest (`--format pbt-seeds`) as a **`pure-mutator`**, a kind of its own, naming what it `mutates` — `"self"` or the `inout` parameter's internal name — so a consumer can write the `&` call:

```json
{ "kind": "pure-mutator", "symbol": "add", "mutates": "config", "rule": "Pure Mutator Property-Test Candidate" }
```

A kind rather than a field on `pure-function`, because a consumer that ignored the field would read a `Void` function as one returning a result and write `f(x) == f(x)` over nothing. A consumer that predates the kind skips it as unrecognised. A `private` mutator keeps the kind and carries `restriction`; it is not demoted to `restricted-function`, which promises a function with a result.

### Non-Violating Examples
```swift
// Returns its result — a Pure Function Property-Test Candidate instead
func adding(_ name: String, to config: Config) -> Config { … }

// Two values written — no single law covers both
func swapFirst(_ a: inout [Int], _ b: inout [Int]) { … }

// Impure: reads the clock
struct Counter: Equatable {
    var n = 0
    mutating func stamp() { n = Int(Date().timeIntervalSince1970) }
}
```

### Violating Examples
```swift
struct Config: Equatable { var items: [String] = [] }
func add(_ name: String, to config: inout Config) {
    if !config.items.contains(name) { config.items.append(name) }
}

struct Counter: Equatable {
    var n = 0
    mutating func bump() { n += 1 }
}
```

---
