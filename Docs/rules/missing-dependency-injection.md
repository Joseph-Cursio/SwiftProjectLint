[← Back to Rules](RULES.md)

## Missing Dependency Injection

**Identifier:** `Missing Dependency Injection`
**Category:** Architecture
**Severity:** Info

### Rationale
Views and objects that create their dependencies internally cannot be tested in isolation. A view with an empty initializer, or a view that instantiates an `ObservableObject` inline with `@StateObject var vm = MyViewModel()`, ties itself to a concrete type that cannot be swapped for a test double.

### Discussion
`ArchitectureVisitor` reports two related scenarios: a `View`-suffixed struct that declares an empty `init()`, and a view whose `@StateObject` property is initialized inline (e.g., `@StateObject var vm = SomeType()`). Both patterns suggest that the dependency could instead be passed through the initializer. The info severity acknowledges that `@StateObject` inline initialization is the correct pattern for app entry points — it is only worth reconsidering when the type needs to be mockable.

### Non-Violating Examples
```swift
struct MyView: View {
    @StateObject private var viewModel: UserViewModelProtocol

    init(viewModel: UserViewModelProtocol) {
        _viewModel = StateObject(wrappedValue: viewModel)
    }

    var body: some View { Text(viewModel.name) }
}
```

### Violating Examples
```swift
struct MyView: View {
    @StateObject private var viewModel = UserViewModel()  // inline instantiation

    var body: some View { Text(viewModel.name) }
}

struct MyView: View {
    init() { }  // empty init in a View — no dependencies injected
    var body: some View { Text("Hello") }
}
```

---
