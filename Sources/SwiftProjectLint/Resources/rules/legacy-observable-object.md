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
`LegacyObservableObjectVisitor` checks variable declarations for the four legacy attributes: `@StateObject`, `@ObservedObject`, `@EnvironmentObject`, and `@Published`. Each triggers an info-level issue with a specific suggestion for the modern replacement.

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
