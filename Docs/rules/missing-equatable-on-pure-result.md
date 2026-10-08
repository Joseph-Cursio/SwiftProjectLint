[← Back to Rules](RULES.md)

## Missing Equatable on Pure Function Result

**Identifier:** `Missing Equatable on Pure Function Result`
**Category:** Testability
**Severity:** Info

### Rationale
A property test asserts on a function's result, so the result has to be comparable with `==`. [Pure Function Property-Test Candidate](pure-function-candidate.md) refuses a pure function whose result is not `Equatable` — rightly — but it refuses silently, so a function **one keyword away** from a property test looks exactly like one with nothing to offer, and never reaches the seed manifest `swift-infer` reads.

This rule reports the function when that is the *only* thing wrong, and names every type that needs `Equatable`. The case that motivated it is SwiftLintRuleStudio's `MigrationAssistant.detectMigrations`: pure and total, returning a `MigrationPlan` that holds `MigrationStep`s, neither declared `Equatable`. It was absent from the manifest while a mutation run left eight mutants alive in the same file.

### Discussion
`MissingEquatableOnPureResultVisitor` asks `PropertyTestCandidacy` the candidate question with one gate moved: the function must pass every other check `pureFunctionCandidate` applies — the purity oracle, the one-hop impure-callee join, the call-shape check — and its result must **not** be `Equatable`. The two rules never report the same declaration.

It fires only when a bare `: Equatable` would be **synthesized**. `EquatableRemedyCatalog`, built in the pre-scan, records what each project `struct`/`enum` would compare and closes over it, so a result holding a non-`Equatable` project type names that type too. Anything that would need a hand-written `==` — or that the linter cannot see well enough to promise — stays silent:

- a stored closure, existential (`any P`), tuple or metatype;
- a class or actor (classes never synthesize `Equatable`);
- a generic type (`Box<T>` conforms conditionally — a different patch);
- a stored property with an attribute (a property wrapper's storage is what synthesis compares, and `Published<Int>` is not `Equatable`);
- a stored property with no annotation, unless its initializer names the type (`= Foo(…)` or a literal);
- a type name declared twice in the project, or declared outside it.

The finding is raised at the **function**, not the type: what earns a conformance is a pure function waiting on it. A blanket "this struct could be `Equatable`" would fire on most value types in a project, and a conformance nothing compares is API surface with no return. The sibling [Missing Equatable on State Type](missing-equatable-on-state-type.md) makes the same argument for SwiftUI state.

Unlike the two candidate census rules, it is **listed** in a default report rather than collapsed: it diagnoses — there is a specific edit to make.

It also seeds the manifest (`--format pbt-seeds`) as a `pure-function` carrying `requires`, so a consumer can name the conformance in the stub it writes:

```json
{ "kind": "pure-function", "symbol": "detectMigrations", "rule": "Missing Equatable on Pure Function Result",
  "requires": { "equatable": ["MigrationPlan", "MigrationStep"] } }
```

```swift
// Before — flagged: `MigrationPlan` holds `[MigrationStep]`, and neither is Equatable
public enum MigrationStep { case rename(from: String, to: String), remove(String) }
public struct MigrationPlan { public let steps: [MigrationStep] }
public func detectMigrations(_ ids: [String]) -> MigrationPlan { … }

// After — both synthesize, and `detectMigrations` is a property-test candidate
public enum MigrationStep: Equatable { case rename(from: String, to: String), remove(String) }
public struct MigrationPlan: Equatable { public let steps: [MigrationStep] }
```

### Non-Violating Examples
```swift
// Already comparable — this is a Pure Function Property-Test Candidate instead
struct Total: Equatable { let cents: Int }
func total(_ items: [Int]) -> Total { Total(cents: items.reduce(0, +)) }

// Needs a hand-written `==`: a stored closure has no synthesized equality
struct Handler { let run: () -> Void }
func handler(_ n: Int) -> Handler { Handler { } }

// Not pure: reads the clock
struct Stamp { let at: Date }
func stamp() -> Stamp { Stamp(at: Date()) }
```

### Violating Examples
```swift
struct Wrapper { let items: [String] }
func wrap(_ items: [String]) -> Wrapper { Wrapper(items: items) }
```

---
