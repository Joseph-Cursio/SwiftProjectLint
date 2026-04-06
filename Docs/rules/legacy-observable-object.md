[← Back to Rules](RULES.md)

## Legacy ObservableObject

**Identifier:** `Legacy Observable Object`
**Category:** Modernization
**Severity:** Info

### Rationale
Starting with iOS 17, the `@Observable` macro replaces the older `ObservableObject` protocol and `@Published` property wrapper from Combine. The new observation system is more efficient — it tracks property access at a fine-grained level, so views only re-render when the specific properties they read actually change. The legacy pattern re-renders any view that subscribes to the object whenever *any* `@Published` property changes.

Along with `@Observable`, the associated property wrappers change too:
- `@StateObject` → `@State` (ownership semantics are the same)
- `@ObservedObject` → `@Bindable` or pass the object directly
- `@EnvironmentObject` → `@Environment`
- `@Published` → remove entirely (properties on `@Observable` classes are tracked automatically)

### Discussion
`LegacyObservableObjectVisitor` detects two categories of legacy usage:

1. **Class conformance** — `class Foo: ObservableObject`. The class declaration itself is flagged with a suggestion to apply the `@Observable` macro and remove the protocol conformance.
2. **Legacy property wrappers** — `@StateObject`, `@ObservedObject`, `@EnvironmentObject`, and `@Published`. Each variable declaration triggers a separate issue with a specific suggestion for the modern replacement.

When both are present (a class conforming to `ObservableObject` that also has `@Published` properties), each is flagged independently so every touch point is visible.

This rule uses info severity because migrating to `@Observable` requires iOS 17+ and may involve broader refactoring. It is intended as a gentle nudge toward modernization rather than a hard warning.

```swift
// Before
class ViewModel: ObservableObject {
    @Published var count = 0
    @Published var name = ""
}

struct ContentView: View {
    @StateObject var viewModel = ViewModel()
    @EnvironmentObject var settings: Settings
}

// After
@Observable
class ViewModel {
    var count = 0
    var name = ""
}

struct ContentView: View {
    @State var viewModel = ViewModel()
    @Environment(Settings.self) var settings
}
```

### Non-Violating Examples
```swift
// @State — the modern ownership wrapper
@State var count = 0

// @Environment — the modern environment injection
@Environment(\.dismiss) var dismiss

// @Bindable — the modern non-owning wrapper
@Bindable var model: Model

// @Observable class — no @Published needed
@Observable
class AppState {
    var count = 0
    var name = ""
}
```

### Violating Examples
```swift
// ObservableObject conformance — migrate the class to @Observable
class ViewModel: ObservableObject { }

// @StateObject — legacy ownership wrapper
@StateObject var viewModel = ViewModel()

// @ObservedObject — legacy non-owning wrapper
@ObservedObject var model: Model

// @EnvironmentObject — legacy environment injection
@EnvironmentObject var settings: Settings

// @Published — legacy change notification
@Published var count = 0
```

---
