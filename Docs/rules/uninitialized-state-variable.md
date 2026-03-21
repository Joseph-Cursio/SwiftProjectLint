[← Back to Rules](RULES.md)

## Uninitialized State Variable

**Identifier:** `Uninitialized State Variable`
**Category:** State Management
**Severity:** Error

### Rationale
A `private @State` variable without an initial value and no `init()` assignment has no way to receive a value. Swift's memberwise initializer excludes private properties, and SwiftUI does not synthesize default values for `@State` storage. The result is a compiler error or, in edge cases with protocol witnesses, undefined runtime behavior.

### Scope
- Flags `@State private var name: Type` with no inline initializer and no `init()` that assigns `_name = State(initialValue:)`
- Does **not** flag optional types (`String?`, `Optional<T>`) — they default to `nil`
- Does **not** flag non-private `@State` vars — they can be set via the memberwise initializer from the parent view
- Does **not** flag variables assigned in an explicit `init()` using `_varName = State(initialValue:)`
- Applies to both `View` and `App` conformers

### Non-Violating Examples
```swift
// Inline initializer
struct MyView: View {
    @State private var count = 0
    @State private var name: String = ""
    var body: some View { Text("\(count)") }
}

// Optional — defaults to nil
struct MyView: View {
    @State private var errorMessage: String?
    var body: some View { Text("Hello") }
}

// Non-private — set by parent via memberwise init
struct RuleDetailView: View {
    @State var viewModel: RuleDetailViewModel
    var body: some View { Text("Hello") }
}

// Assigned in init()
struct MyApp: App {
    @State private var registry: RuleRegistry

    init() {
        let reg = RuleRegistry()
        _registry = State(initialValue: reg)
    }

    var body: some Scene { WindowGroup { Text("Hello") } }
}
```

### Violating Examples
```swift
struct MyView: View {
    @State private var count: Int  // private, non-optional, no init — error
    var body: some View { Text("\(count)") }
}
```

---
