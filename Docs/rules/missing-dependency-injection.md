[← Back to Rules](RULES.md)

## Missing Dependency Injection

**Identifier:** `Missing Dependency Injection`
**Category:** Architecture
**Severity:** Info

### Rationale
Views and objects that create their dependencies internally cannot be tested in isolation. A view with an empty initializer, or a view that instantiates an `ObservableObject` inline with `@StateObject var vm = MyViewModel()`, ties itself to a concrete type that cannot be swapped for a test double.

### Discussion
`ArchitectureVisitor` reports three related scenarios:

1. A `View`-suffixed struct that declares an empty `init()`.
2. A view whose `@StateObject` property is initialized inline (e.g., `@StateObject var vm = SomeType()`).
3. A view whose `@State` property is initialized inline with a **service-like type** (e.g., `@State private var viewModel = DiagramViewModel()`). Only types with recognized service suffixes (`Manager`, `Service`, `Store`, `Provider`, `Client`, `Repository`, `Handler`, `Controller`, `Factory`, `Adapter`, `ViewModel`, `Coordinator`, `Generator`) trigger this check — simple value types like `@State private var count = 0` are not flagged.

All three patterns suggest that the dependency could instead be passed through the initializer. The info severity acknowledges that inline initialization is the correct pattern for app entry points — it is only worth reconsidering when the type needs to be mockable.

The `@State` check was added because `@Observable` (introduced in iOS 17 / macOS 14) replaces `ObservableObject` + `@StateObject` with `@Observable` + `@State`. Without this check, the same tight-coupling pattern that was previously caught via `@StateObject` would go undetected in modern SwiftUI code.

**`@Environment` and `@EnvironmentObject` are exempt from the empty-init check.** SwiftUI's environment system *is* dependency injection — dependencies are injected by the SwiftUI runtime rather than through the initializer. A view that reads from the environment via `@Environment(MyModel.self)` or `@EnvironmentObject var model: MyModel` is correctly designed; an empty `init()` on such a view is intentional.

### Non-Violating Examples
```swift
// Protocol-typed @StateObject injected through the initializer
struct MyView: View {
    @StateObject private var viewModel: UserViewModelProtocol

    init(viewModel: UserViewModelProtocol) {
        _viewModel = StateObject(wrappedValue: viewModel)
    }

    var body: some View { Text(viewModel.name) }
}

// @Environment — SwiftUI's built-in injection; empty init is intentional
public struct ContentView: View {
    @Environment(AppState.self) private var appState
    public init() {}
    var body: some View { Text(appState.title) }
}

// @EnvironmentObject — also exempt
struct ProfileView: View {
    @EnvironmentObject var model: UserModel
    init() {}
    var body: some View { Text(model.name) }
}

// @State with simple value types — not flagged
struct CounterView: View {
    @State private var count = 0
    @State private var name = ""
    @State private var isActive = false
    var body: some View { Text("\(count)") }
}

// @State with non-service type — not flagged
struct SettingsView: View {
    @State private var config = AppConfig()
    var body: some View { Text("") }
}
```

### Violating Examples
```swift
// Inline @StateObject — concrete type, cannot be swapped for a test double
struct MyView: View {
    @StateObject private var viewModel = UserViewModel()

    var body: some View { Text(viewModel.name) }
}

// Inline @State with service-like type (@Observable pattern)
struct ContentView: View {
    @State private var viewModel = DiagramViewModel()

    var body: some View { Text(viewModel.title) }
}

// Inline @State with Manager suffix
struct AppView: View {
    @State private var subscriptionManager = SubscriptionManager()

    var body: some View { Text("") }
}

// Empty init with no environment properties — no dependencies at all
struct MyView: View {
    init() { }
    var body: some View { Text("Hello") }
}
```

---
