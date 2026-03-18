[← Back to Rules](RULES.md)

## Uninitialized State Variable

**Identifier:** `Uninitialized State Variable`
**Category:** State Management
**Severity:** Error

### Rationale
`@State` variables must have an initial value because SwiftUI manages their storage. Declaring a `@State` property without an initial value compiles in some configurations but produces undefined behavior — the property storage is never initialized by SwiftUI, leading to crashes or incorrect UI at runtime.

### Discussion
The error severity reflects that this is a correctness issue, not a style concern. The rule is detected by `SwiftUIManagementVisitor` during single-file analysis when it finds a `@State`-annotated binding that has neither a type-annotated initializer nor an inferred value.

### Non-Violating Examples
```swift
struct MyView: View {
    @State private var count = 0          // initialized with 0
    @State private var name: String = ""  // initialized with ""
    var body: some View { Text("\(count)") }
}
```

### Violating Examples
```swift
struct MyView: View {
    @State private var count: Int  // no initial value — error
    var body: some View { Text("\(count)") }
}
```

---
