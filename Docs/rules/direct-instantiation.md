[← Back to Rules](RULES.md)

## Direct Instantiation

**Identifier:** `Direct Instantiation`
**Category:** Architecture
**Severity:** Warning

### Rationale

Creating a service, manager, repository, or similar object directly at its point of use — rather than receiving it through an initializer or environment — makes code hard to test and creates hidden coupling between consumer and implementation.

**The rule only reports a construction dependency injection could actually reach.** Everything in the table below is a place where "prefer dependency injection" names an edit that cannot be made — not a place where the construction is merely defensible. That is the test each exemption had to pass: *is there an edit that satisfies the advice?*

### Discussion

`DirectInstantiationVisitor` reports a construction of a type whose name carries a service-like suffix. The suffix set is **not** listed here: it lives in `ServiceTypeSuffix`, shared with every architecture rule that keys off "does this name look like a service", and a copy in this document is a copy that goes stale. (One did — this paragraph named thirteen suffixes for months after the enum reached twenty-seven.)

It fires for stored property initializers, local variable declarations, and closure bodies.

#### What it does not report

| Not reported | Because |
| --- | --- |
| A SwiftUI property wrapper — `@StateObject var vm = VM()` | That is the correct pattern for an owned view model. |
| Anything in `#Preview` or `#if DEBUG` | Building a concrete object graph to look at is what a preview is *for*. |
| A callee that does not name a type — `Strategist.composedGenerator(…)` | A `static func` is not a construction; there is no type to inject. |
| A `private` or `fileprivate` type | Unreachable outside its file, so nothing could supply a substitute. Taking the advice means *widening* the access level in order to hide the type. |
| A test double — `MockGenerator(…)`, `StubClient(…)` | A double is already the substitute an injection would supply. |
| The program's entry point — `main.swift`, an `@main` type's `main()` or `init()` | There is nowhere further out to push the construction. |
| A `ParsableCommand` conformer | ArgumentParser builds it from argv; the synthesized initializer has no parameter to inject through. |
| A helper handed `self` — `Checker(visitor: self)` | `self` does not exist before the initializer that would receive a substitute has run. |
| An `@Observable` model a view owns | The `.task` construction *is* the injection — the environment value it takes cannot be read from a property initializer. |
| A composition root | DI has to bottom out somewhere, and that place is allowed to name every concrete type it wires. Three or more distinct services, at least one kept past the body's return. |
| A defaulted parameter — `init(svc: Service = Service())` | The parameter is the seam; a test substitutes by passing one. |
| A type vending itself — `static let shared = Foo()` inside `Foo` | That defines the singleton. `Singleton Usage` covers the *access* sites. |

Each exemption's evidence — what it was measured against and what nearly went wrong — is in the doc comment on the code that implements it, where someone changing that code will meet it.

### The fix

Take the dependency through the initializer, with a default if callers should not have to supply one:

```swift
final class Importer {
    private let parser: ConfigParser

    init(parser: ConfigParser = ConfigParser()) {
        self.parser = parser
    }
}
```

The default keeps every existing call site working and gives a test somewhere to pass a substitute — which is the whole requirement, and why a defaulted parameter is not itself reported.

### Examples

```swift
// Reported — a stored property with an inline initializer has no seam at all
final class Importer {
    private let parser = ConfigParser()
}

// Reported — same in a function body
func run() {
    let parser = ConfigParser()
    _ = parser
}

// Not reported — the file-local accumulator. Nothing outside this file can name
// `Checker`, so nothing could substitute it; the enclosing function is the kernel
// and the class is its body.
enum AmbientStateReads {
    static func occur(in node: some SyntaxProtocol) -> Bool {
        let checker = Checker(viewMode: .sourceAccurate)
        checker.walk(node)
        return checker.sawSource
    }

    private final class Checker: SyntaxVisitor { var sawSource = false }
}

// Not reported — a type vending itself is defining the singleton
final class ProjectParser {
    static let shared = ProjectParser()
    private init() {}
}
```

---
