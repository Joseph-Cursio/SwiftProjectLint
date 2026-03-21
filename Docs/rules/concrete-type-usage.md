[← Back to Rules](RULES.md)

## Concrete Type Usage

**Identifier:** `Concrete Type Usage`
**Category:** Architecture
**Severity:** Info

### Rationale
A function parameter or stored property typed as a concrete service class (e.g., `func configure(service: APIService)`) cannot be substituted with a test double or alternative implementation without modifying the function signature. Protocol abstractions allow callers to pass any conforming type.

### Discussion
`ConcreteTypeUsageVisitor` checks type annotations in function parameters and stored properties (without initializers) for names ending in service-like suffixes (`Manager`, `Service`, `Store`, `Provider`, `Client`, `Repository`, `Handler`, `Controller`, `Factory`, `Adapter`, `ViewModel`, `Coordinator`). It skips types ending in `Protocol`, `Type`, or `Interface` (which are already abstractions), types annotated with a SwiftUI property wrapper, and parameters typed with `some Protocol` (opaque types).

The following patterns are exempt because they do not represent real coupling issues:

- **DI containers** — types whose name ends in `Container`, `Dependencies`, `Composition`, or `Assembly` are composition roots where concrete types are intentional
- **System/Foundation types** — `FileManager`, `NotificationCenter`, `UserDefaults`, `URLSession`, `ProcessInfo`, `Bundle`, etc. cannot reasonably be protocol-abstracted
- **Mock/stub/fake types** — test doubles are concrete by design
- **ViewModels in SwiftUI views** — SwiftUI property wrappers (`@State`, `@ObservedObject`, `@Bindable`) require concrete types, so protocol-abstracting ViewModels in views is impractical
- **Test files** — test code and test helpers use concrete types by necessity
- **SwiftUI property wrapper properties** — `@State`, `@StateObject`, `@ObservedObject`, `@EnvironmentObject`, `@Binding`, `@Published`, `@AppStorage`, `@SceneStorage`, `@Bindable`, `@Environment`

Replacing `APIService` with `APIServiceProtocol` — or using `some NetworkProtocol` — resolves the issue.

### Non-Violating Examples
```swift
// Using a protocol-named type
class Owner {
    var service: NetworkServiceProtocol
    init(service: NetworkServiceProtocol) { self.service = service }
}

// Opaque type
class Owner {
    func foo(service: some NetworkProtocol) { }
}

// DI container — concrete types are correct here
class DependencyContainer {
    var workspaceManager: WorkspaceManager
    var onboardingManager: OnboardingManager
}

// System type — cannot be protocol-abstracted
class Analyzer {
    var fileManager: FileManager
}

// ViewModel in SwiftUI view — concrete type required by property wrappers
struct RuleBrowserView: View {
    var viewModel: RuleBrowserViewModel
    var body: some View { Text("") }
}

// Property wrapper — exempt
struct MyView: View {
    @ObservedObject var viewModel: MyViewModel
    var body: some View { Text("") }
}
```

### Violating Examples
```swift
// Concrete type in function parameter
class Setup {
    func configure(service: APIService) { }  // concrete type
}

// Concrete type in stored property
class MyViewModel {
    var repo: UserRepository  // concrete type, no initializer
    init(repo: UserRepository) { self.repo = repo }
}
```

---
