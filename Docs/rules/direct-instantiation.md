[← Back to Rules](RULES.md)

## Direct Instantiation

**Identifier:** `Direct Instantiation`
**Category:** Architecture
**Severity:** Warning

### Rationale
Creating a service, manager, repository, or similar object directly at its point of use — rather than receiving it through an initializer or environment — makes code hard to test and creates hidden coupling between consumer and implementation.

### Discussion
`DirectInstantiationVisitor` identifies calls to constructors of types whose names carry a service-like suffix. The suffix set is **not** listed here: it lives in `ServiceTypeSuffix`, shared with every other architecture rule that keys off "does this name look like a service", and a copy in this document is a copy that goes stale. (One did — this paragraph named thirteen suffixes for several months after the enum reached twenty-seven.)

It fires for stored property initializers, local variable declarations, and closure bodies. It does not fire when the variable has a SwiftUI property wrapper (`@StateObject`, `@ObservedObject`, etc.), because wrapper-decorated `@StateObject var vm = SomeViewModel()` is the correct SwiftUI pattern for owned view models, nor inside a `#Preview` macro or an `#if DEBUG` block, because building a concrete object graph to look at is what a preview is *for*.

**The callee has to name a type.** The suffix test used to run against the whole of `calledExpression.description`, which reads a *member call* as a construction whenever the member's own name happens to end in a service suffix. `DerivationStrategist.composedGenerator(forTypeName:)` is a `static func` returning a value, and it was reported as "direct instantiation of `'DerivationStrategist.composedGenerator'` — prefer dependency injection": advice with no referent, because there is no such type to inject. The trailing component now decides and it has to look like a type — `Module.Type()` is a construction, `Type.method()` is not — while `Foo<Bar>()` is unwrapped to `Foo` first.

**A `private` or `fileprivate` type is not reported.** Such a type is unreachable outside the file that declares it, so there is no caller anywhere that could supply a substitute and no test that could pass one. Taking the advice would mean *widening* the type's access level in order to hide it — exporting an implementation detail to make it injectable, which is the opposite of the trade the rule offers.

The shape this reaches is the single-use accumulator, and it matters more than the count suggests. `AmbientStateReads.occur(in:)` is eight lines long: construct a `private final class Checker: SyntaxVisitor`, walk it, read one flag, discard it. That function is a total kernel — a pure predicate over a syntax node, the exact thing the extraction rules in this tool exist to produce — and this rule was reporting its insides as coupling. Seven findings across three repositories were that shape: four in `SwiftEffectInference`'s `PurityInferrer`, two in this project, and one argument-accumulator `private struct Builder` nested inside the initializer that fills it.

Because a `private` type can only be *used* in the file that declares it, the check needs no project-wide prescan — the declaration is always in the file being analysed if it is anywhere. It is read in a pre-pass rather than as the walk goes, because the construction usually comes first: `AmbientStateReads` builds its `Checker` eight lines above the `private final class Checker` that declares it.

**Test doubles are not reported.** `MockGenerator(…)`, `StubClient(…)`, `FakeStore(…)` — a double is already the substitute an injection would supply, so asking for a seam in front of one is asking the author to abstract the abstraction. `Concrete Type Usage`, the rule that counts the same seam from the *declaration* end, had exempted these for some time; this rule had no such vocabulary, so `MockGenerator` was exempt where it was declared and reported where it was built. Both now resolve against `MockTypeName`, for the same single-source-of-truth reason as `ServiceTypeSuffix`.

**The program's entry point is not flagged.** Swift designates exactly one place where a program begins, and it has nowhere further out to push a construction. Two spellings are recognised: top-level code in `main.swift`, which the language permits in no other file, and an `@main` type's `static func main()` or `init()`. The `init()` case is a SwiftUI `App` seeding the `@State` containers the whole program reads from — the same role, and the corpus's Explorer target describes it that way in its own file header.

The gate is the entry point, not the whole type: a `@main` type's other methods are ordinary code and hard-wiring a dependency in one is an ordinary finding. Six findings across four repositories went, five of them a spike's `PaymentStore()`/`ProfileStore()` two lines into `static func main()`.

**An `@Observable` model a view owns is not flagged.** That is already why `@State private var model = Model()` is exempt; this is the same ownership one step deferred, and the deferral is forced rather than stylistic. An `@Environment` value cannot be read from a property initializer, so a model that needs one is built in `.task` and stored into an optional `@State`:

```swift
@Environment(AppState.self) private var appState
@State private var viewModel: BeadsViewModel?
...
.task { if viewModel == nil { viewModel = BeadsViewModel(appState: appState) } }
```

That construction *is* the injection — `appState` arrives from the environment — and the rule's suggestion, "use `@StateObject`/`@EnvironmentObject`", names the pre-Observation API for a problem Observation does not have. Seven of the corpus's findings were this pattern, written identically seven times in one app.

Two things keep it narrow. It applies only inside a `View` — the same `@Observable` type built by a coordinator is an ordinary dependency of that coordinator — and only to types the project-wide `@Observable` prescan knows about, so a plain service reached for inside a view body is still the case the rule exists for.

**A type the runtime constructs is not flagged.** `ParsableCommand`, `AsyncParsableCommand` and `ParsableArguments` conformers are built by ArgumentParser out of argv and then run. The synthesized initializer takes only the decoded `@Option`/`@Argument`/`@Flag` values, so there is no parameter to inject through, and the one remaining spelling — a stored property with an inline default — is exactly the shape this rule reports. Inside a command, every form of the fix the rule recommends is either impossible or itself a finding, which is what "advice with no reachable end state" means.

The gate covers the command type rather than its `run()`, because the constraint belongs to the type: `BootstrapSkillsCommand.makeDetector()` assembles a registry, an anti-pattern store, a knowledge graph and a builder in a private helper, and it is no more injectable there. Eight findings across two repositories, four of them CLI subcommands reaching for a diagram generator whose protocol seam already exists and is already used — `DiagramViewModel` takes `any ClassDiagramGenerating = ClassDiagramGenerator()`, the defaulted-parameter shape this rule documents as the seam, and the test target has doubles for it.

**A helper handed its own owner is not flagged.** `ButtonAccessibilityChecker(visitor: self)` cannot be injected into the thing it is given: `self` does not exist before the initializer that would receive a substitute has run, so taking the advice means two-phase initialization — an optional stored property filled after construction — to buy a substitution nobody can use, because the helper is bound to this owner anyway. Four of these are one file, where `AccessibilityVisitor` splits its five element checks into `lazy var` sub-checkers, which is the ordinary way to keep a 900-line visitor from being one type.

**A composition root is not flagged.** Dependency injection has to bottom out. Somewhere a concrete object graph is built, and that place is allowed — required — to name every concrete type it wires together; the whole benefit of injecting everywhere else is that there is exactly one such place. Reporting each construction inside it turns one architectural fact into a warning per line, and it was doing so twelve times across four bodies.

Two conditions, and the second is what keeps it from being a neighbour count. The body must construct at least **three distinct** service-like types, **and** keep at least one of them past its own return by assigning to a stored property of the enclosing type — `self.store = store`, or the bare `handler = newHandler` and `_ruleRegistry = State(initialValue: registry)` spellings, told apart from a local reassignment by collecting every name the body itself binds.

The retention condition was added after measuring the first version, which had only the count. `ProjectAnalyzer.analyze(paths:)` builds four diagram generators, uses each once and returns a summary; it went silent while an identical `ClassDiagramGenerator()` forty lines below, in a function with fewer neighbours, kept reporting. A rule that answers differently for the same construction depending on how many siblings it has is drawing the line on syntax rather than on substance — the fault the paragraph below already records correcting once, over defaulted parameters. With retention required, `analyze` reports all three again and the twelve that go are roots by inspection: `AppState.constructCoreServices` / `assignStatelessServices` / `constructHigherLayers`, `ExtensionServiceContainer.commandHandler`, `KnowledgeGraph.init` (nine domain stores off one injected database), and a sandboxed SwiftUI `App`'s `init` whose file header calls itself a composition root in as many words.

Note for anyone extending this: the assignment is read off `SequenceExprSyntax`, not `InfixOperatorExprSyntax`. An unfolded tree — what `Parser.parse` produces and what every visitor here walks — represents `self.store = store` as a three-element sequence whose middle element is the `AssignmentExprSyntax`; `InfixOperatorExprSyntax` appears only after operator folding, which the linter never does. Written the other way first, this gate compiled, its tests passed, and it removed exactly nothing from the corpus.

**A defaulted parameter is not flagged, and used to be.** `init(svc: NetworkService = NetworkService())` was reported with the advice "remove the default value and inject at the call site". The parameter *is* the seam: a test substitutes by passing one, which is the whole requirement, and removing the default only makes every caller construct one for no testability gain. The rule was also inconsistent about it — `= .shared` and `= .default` hard-wire production in exactly the same way and were never reported, so the line was drawn on whether the default was spelled as a constructor call rather than on whether a seam existed. What remains is where the rule's value is: a stored property with an inline initializer has no parameter to pass and no seam at all.

**The singleton definition site is exempt.** A type that vends an instance of *itself* as a `static` member — `static let shared = ProjectParser()` *inside* `ProjectParser` — is defining the singleton, not consuming an injectable dependency. Instantiating yourself to publish your own `.shared` is the singleton idiom (and the same shape covers namespaced constants like `static let live = Client()`); flagging it contradicts the rule's intent and double-reports the line that `Singleton Usage` already covers at the *access* sites. The visitor tracks the enclosing nominal type via a declaration stack (`class`/`struct`/`enum`/`actor`) and skips a `static` initializer whose instantiated type equals the enclosing type. The exemption is deliberately narrow: a `static` member instantiating a *different* service type, or a *non-`static`* member instantiating the enclosing type, is still flagged.

### Non-Violating Examples
```swift
// Injected through initializer
class MyViewModel {
    private let service: NetworkService
    init(service: NetworkService) {
        self.service = service
    }
}

// Property wrapper instantiation is acceptable
struct MyView: View {
    @StateObject private var vm = MyViewModel()
    var body: some View { Text("") }
}

// Singleton definition — a type vending an instance of itself, not a dependency
final class ProjectParser {
    static let shared = ProjectParser()
    private init() {}
}

// A file-local accumulator — nothing outside this file can name it, so nothing
// can substitute it. The enclosing function is the kernel; the class is its body.
enum AmbientStateReads {
    static func occur(in node: some SyntaxProtocol) -> Bool {
        let checker = Checker(viewMode: .sourceAccurate)
        checker.walk(node)
        return checker.sawSource
    }

    private final class Checker: SyntaxVisitor { var sawSource = false }
}

// A static member call is not a construction
let generator = DerivationStrategist.composedGenerator(forTypeName: name)

// A test double is already the substitute
let generator = MockGenerator(typeName: name)
```

### Violating Examples
```swift
// Direct instantiation in stored property
class MyView {
    private let svc = NetworkService()  // direct instantiation
}

// Direct instantiation in function body
class Setup {
    func setup() {
        let svc = NetworkService()  // direct instantiation
        _ = svc
    }
}
```

---
