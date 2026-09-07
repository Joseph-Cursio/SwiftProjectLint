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
