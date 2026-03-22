[← Back to Rules](RULES.md)

## Missing Dependency Injection

**Identifier:** `Missing Dependency Injection`
**Category:** Architecture
**Severity:** Info

### Rationale
Views and objects that create their dependencies internally cannot be tested in isolation. A view with an empty initializer, or a view that instantiates an `ObservableObject` inline with `@StateObject var vm = MyViewModel()`, ties itself to a concrete type that cannot be swapped for a test double.

### Discussion
`ArchitectureVisitor` reports two related scenarios: a `View`-suffixed struct that declares an empty `init()`, and a view whose `@StateObject` property is initialized inline (e.g., `@StateObject var vm = SomeType()`). Both patterns suggest that the dependency could instead be passed through the initializer. The info severity acknowledges that `@StateObject` inline initialization is the correct pattern for app entry points — it is only worth reconsidering when the type needs to be mockable.

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
```

### Violating Examples
```swift
// Inline @StateObject — concrete type, cannot be swapped for a test double
struct MyView: View {
    @StateObject private var viewModel = UserViewModel()

    var body: some View { Text(viewModel.name) }
}

// Empty init with no environment properties — no dependencies at all
struct MyView: View {
    init() { }
    var body: some View { Text("Hello") }
}
```

---
