[← Back to Rules](RULES.md)

## Subclassed For Mocking

**Identifier:** `Subclassed For Mocking`
**Category:** Architecture
**Severity:** Info

### Rationale
When a test substitutes a concrete production class by **subclassing** it — `class MockFooService: FooService` overriding the methods under test — that is the anti-pattern protocols exist to eliminate. The subclass must call the real `super.init` (inheriting any side effects the production initializer carries, such as file or network access), and a new method added to the production class silently escapes the override, so the mock drifts out of sync without a compiler error. If the only reason a class is subclassed is to fake it in tests, and the class exposes no protocol abstraction, extracting a protocol lets the test supply a lightweight conformer instead.

### Discussion
`SubclassedForMockingVisitor` performs cross-file analysis. Pass 1 collects every class and protocol declaration, each class's inheritance clause, and the declaration's line number (captured while the correct per-file source-location converter is active). Pass 2 (`finalizeAnalysis`) walks the test doubles and flags their production superclass.

A subclass is treated as a **test double** when its name begins with `Mock`, `Stub`, `Fake`, `Spy`, or `Dummy`, **or** it is declared in a test/fixture file. A base class is flagged only when it is a genuine target for abstraction:

- The base is a production type (not itself a test double).
- The base does **not** already conform to a project-declared protocol — if it does, the test should mock through that protocol rather than subclassing, so the missing-abstraction signal does not apply.
- No conventional mirror protocol (`<BaseName>Protocol`) already exists.

Because the rule keys off the *test subclass* rather than the type's name, it catches missed protocol seams that a name-suffix heuristic misses (an `Analyzer`, `Simulator`, or any class whose injection sites are all behind exempt composition roots). Once a protocol is extracted and the base conforms to it, the rule stops firing — it is self-resolving.

**Scope note:** the rule can only link a base class and its mock when both are visible in a single analysis run. If the production class lives in a nested Swift package (a directory with its own `Package.swift`, which the linter analyzes separately) while the mock lives in a different target, the two are never seen together and the rule will not fire.

### Non-Violating Examples
```swift
// Mock conforms to a protocol — no subclassing of the production type
protocol PaymentProcessing { func charge() }
class StripeProcessor: PaymentProcessing { func charge() { } }
struct MockPaymentProcessor: PaymentProcessing { func charge() { } }

// Genuine production subclassing — the subclass is not a test double
class BaseRow { func render() { } }
class HighlightedRow: BaseRow { override func render() { } }
```

### Violating Examples
```swift
// Production class with no abstraction, faked by subclassing in a test
class WorkspaceAnalyzer {
    func analyze() { }
}

// In a test target:
class MockWorkspaceAnalyzer: WorkspaceAnalyzer {
    override func analyze() { }   // must call super.init; drifts when analyze's siblings change
}
```

### How to Fix
Extract a protocol describing the surface the mock overrides, conform the production class to it, and inject the protocol at the call sites. The test then provides a small conformer instead of subclassing the production type and invoking its real initializer.
