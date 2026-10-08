[← Back to Rules](RULES.md)

## Direct Instantiation

**Identifier:** `Direct Instantiation`
**Category:** Architecture
**Severity:** Warning
**Principle:** Dependency Inversion (SOLID)

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
| The program's entry point — `main.swift`; in an `@main` type or a SwiftUI `App`, its `main()`, initializers, instance stored properties and `body` | There is nowhere further out to push the construction. See [the app's own root](#the-apps-own-root). |
| A `ParsableCommand` conformer | ArgumentParser builds it from argv; the synthesized initializer has no parameter to inject through. |
| A helper handed `self` — `Checker(visitor: self)` | `self` does not exist before the initializer that would receive a substitute has run. |
| An `@Observable` model a view owns | The `.task` construction *is* the injection — the environment value it takes cannot be read from a property initializer. |
| A composition root | DI has to bottom out somewhere, and that place is allowed to name every concrete type it wires. Three or more distinct services, at least one kept past the body's return. |
| A defaulted parameter — `init(svc: Service = Service())` | The parameter is the seam; a test substitutes by passing one. |
| A type vending itself — `static let shared = Foo()` inside `Foo` | That defines the singleton. `Singleton Usage` covers the *access* sites. |

Each exemption's evidence — what it was measured against and what nearly went wrong — is in the doc comment on the code that implements it, where someone changing that code will meet it.

### The app's own root

Most small SwiftUI apps wire themselves in a stored property of the `App`, not in `init()`:

```swift
@main
struct CheckoutApp: App {
    private let store = CoreDataOrderStore()

    var body: some Scene {
        WindowGroup { CheckoutView(model: CheckoutViewModel(store: store)) }
    }
}
```

That `store` used to be reported while `init() { store = CoreDataOrderStore() }` was not, though a
stored property's initializer runs as part of every initializer: the same construction at the same
moment, answered two ways by spelling. And it is `init()` that has the right answer. The runtime
builds an `App` through `init()`, so no caller can hand it a substitute, and whatever it holds in
production is built inside it. The exemption therefore covers every member on the runtime's own
path into the program:

- `static func main()` and the initializers;
- instance stored properties, `lazy` ones included;
- `body`, which only the runtime reads.

The type is an `@main` type — a SwiftUI `App`, an application delegate, a tool — or a SwiftUI `App`
without `@main`. That last is the launcher spelling: an `@main enum` whose `main()` picks the real
`App` or a bare one for a unit-test host, and the `App` it picks is still built by `App.main()`
through `init()`. A tool whose own `main()` builds `Self()` is the one entry type with a caller,
which could pass its services in; its stored properties follow its `init()`, which was exempt
first, rather than split the two spellings again.

Still reported, because each has an edit that satisfies the advice:

- **A `static` stored property.** No initializer fills it. It is a global every file can reach as
  `Server.store`; building it in `main()` and passing it down is an injection.
- **Any other method or computed property.** Ordinary code the app calls, which can take what it
  needs as a parameter or read it from the root's stored property.
- **A type nested inside the `App`, or a `Scene` it builds.** The app's own code constructs it, and
  can pass it the store.

This is not the composition-root count lowered. A root that is not the entry type still needs three
services: at two, a function that reaches for a store and its index — the case the rule exists for —
would go silent. The `App` is exempt for what it is, not for how much it builds.

Measured on 33 repository roots — the sibling projects, pulled to `origin/main`, and this one — each
run with only this rule enabled, so a repository's own `enabled_only` list could not hide it: 39
findings before, 38 after. The one removed is `CheckoutApp.swift:7`, and none of the remaining 38
sits in an entry type. None of the other thirteen `App`s in those repositories keeps a service in a
plain stored property: they hold it in `@State`, exempt already as a property wrapper, build it in
`init()`, or construct none.

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


### A type that holds nothing a test could supply

Constructing one is not a coupling point. A test that wants different behaviour from
`PromptBuilder` passes different arguments, not a different instance — there is no state for a
second instance to hold differently and no effect for a double to intercept.

`CleanInstanceMethodCatalog.isPureKernel(_:)` decides it, shared with `ConcreteTypeUsage`, which
asks the same question from the declared type rather than the construction site. Three conditions:
every method is a function of its inputs under the purity fixpoint this project already resolved,
no stored property is mutable, and every stored property is a value — a stdlib value type, a
project enum, a collection or optional of one, **or another kernel**.

The purity fixpoint judges with the run's construction facts, so the exemption can shrink: a method
that builds a value of a package type that mints an identity (`let id = UUID()`) is not a function of
its inputs, and its type is no longer a kernel. Re-measured on seven repositories when the facts were
wired, it moved no finding of this rule or of `ConcreteTypeUsage`. Only the packages the root
compiles feed those facts (see [which files' types count](pure-function-candidate.md#constructions-what-building-a-value-runs)):
before that bound, an unrelated nested package's namesake took a kernel's exemption away and added a
warning. A nested package the run reports on feeds them too, so with `--include-nested-packages` its
own kernels are judged with its own types — and its namesakes can take a root kernel's exemption,
the accepted cost of judging it at all.

**That last clause and the fixpoint under condition (1) were both added after
`EffectAnnotationParser` refused to qualify**, and neither alone would have admitted it. It holds
one `AttributeRecognition` — five `Set<String>` — which was itself admitted while the type holding
it was not, so storage now resolves to a fixpoint rather than one pass. And four of its methods
are recursive: two `combinedDocTrivia` overloads share a name key and so call themselves, and
`parseEffect` and `resolveDeclEffect` call each other. The purity fixpoint used to promote a
method only once its callees were *already* clean, so a cycle never started — and **recursion is
not an effect**. It now assumes and demotes instead. See `ConcreteTypeUsage`'s notes for the full
account.

**Both cheap approximations were measured and refused.** *Value type* fails on `CacheManager`, a
`public struct` doing file I/O. *No-argument initializer* fails on `AntiPatternStore()` and
`SourceKitClient()`, which take no arguments and talk to disk and to `sourcekitd`.

**And the storage test is positive rather than negative for a measured reason.** Asked as a
denylist — is any stored property a closure or an existential? — it produced two false exemptions
on its first corpus run, including a type storing `UserDefaults`. That type's method reads
`defaults.data(forKey:)`, the property's name; the type appears only in the declaration. A
dependency held as storage does not name itself where it is used, so the oracle that reads bodies
cannot see it and only the declaration can.


---
