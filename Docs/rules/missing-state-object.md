[← Back to Rules](RULES.md)

## Missing StateObject

**Identifier:** `Missing StateObject`
**Category:** State Management
**Severity:** Warning

### Rationale
`@ObservedObject` tells SwiftUI that you do not own the object — the object's lifetime is managed elsewhere. When a view creates an `ObservableObject` that it also owns, `@StateObject` must be used instead. Using `@ObservedObject` for an owned object causes SwiftUI to recreate the object on every redraw, losing all accumulated state.

### Discussion
This rule detects the pattern where a view declares an `@ObservedObject` and there is evidence (in the same file or hierarchy) that the view is responsible for creating that object's instance. The fix is straightforward: replace `@ObservedObject` with `@StateObject` so SwiftUI manages the object's lifetime correctly.

### Non-Violating Examples
```swift
struct ParentView: View {
    // Parent owns the model — correct use of @StateObject
    @StateObject private var viewModel = UserViewModel()
    var body: some View {
        ChildView(viewModel: viewModel)
    }
}

struct ChildView: View {
    // Child receives and observes — correct use of @ObservedObject
    @ObservedObject var viewModel: UserViewModel
    var body: some View { Text(viewModel.name) }
}
```

### Violating Examples
```swift
struct MyView: View {
    // View creates the object but uses @ObservedObject — incorrect
    @ObservedObject private var viewModel = UserViewModel()
    var body: some View { Text(viewModel.name) }
}
```

---
