[← Back to Rules](RULES.md)

## Direct Instantiation

**Identifier:** `Direct Instantiation`
**Category:** Architecture
**Severity:** Warning

### Rationale
Creating a service, manager, repository, or similar object directly at its point of use — rather than receiving it through an initializer or environment — makes code hard to test and creates hidden coupling between consumer and implementation.

### Discussion
`DirectInstantiationVisitor` identifies calls to constructors of types whose names end with service-like suffixes: `Manager`, `Service`, `Store`, `Provider`, `Client`, `Repository`, `Handler`, `Controller`, `Factory`, `Adapter`, `ViewModel`, `Coordinator`, or `Generator`. It fires for stored property initializers, local variable declarations, and closure bodies. It does not fire when the variable has a SwiftUI property wrapper (`@StateObject`, `@ObservedObject`, etc.), because wrapper-decorated `@StateObject var vm = SomeViewModel()` is the correct SwiftUI pattern for owned view models.

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
