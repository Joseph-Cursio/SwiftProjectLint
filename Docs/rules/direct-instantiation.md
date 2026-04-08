[← Back to Rules](RULES.md)

## Direct Instantiation

**Identifier:** `Direct Instantiation`
**Category:** Architecture
**Severity:** Warning

### Rationale
Creating a service, manager, repository, or similar object directly at its point of use — rather than receiving it through an initializer or environment — makes code hard to test and creates hidden coupling between consumer and implementation.

### Discussion
`DirectInstantiationVisitor` identifies calls to constructors of types whose names end with service-like suffixes: `Manager`, `Service`, `Store`, `Provider`, `Client`, `Repository`, `Handler`, `Controller`, `Factory`, `Adapter`, `ViewModel`, `Coordinator`, or `Generator`. It fires for stored property initializers, default parameter values, local variable declarations, and closure bodies. It does not fire when the variable has a SwiftUI property wrapper (`@StateObject`, `@ObservedObject`, etc.), because wrapper-decorated `@StateObject var vm = SomeViewModel()` is the correct SwiftUI pattern for owned view models.

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
```

### Violating Examples
```swift
// Direct instantiation in stored property
class MyView {
    private let svc = NetworkService()  // direct instantiation
}

// Direct instantiation as default parameter
class MyViewModel {
    init(svc: NetworkService = NetworkService()) { }  // default creates concrete instance
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
