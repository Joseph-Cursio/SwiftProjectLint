[← Back to Rules](RULES.md)

## Basic Error Handling

**Identifier:** `Basic Error Handling`
**Category:** UI Patterns
**Severity:** Info

### Rationale
Displaying errors with `Text("Error: ...")` in the view body is a bare-minimum pattern that is easy to miss and hard for users to act on. SwiftUI provides `.alert()` and `.sheet()` modifiers that present errors in a standardized, dismissible modal that integrates with platform conventions.

### Discussion
`UIVisitor` inspects the view body text for error-handling patterns: `if let error` bindings or `Text("Error` literals. When such a pattern is found but no `.alert()`, `.sheet()`, or `Alert(` call is present, it reports an info issue suggesting proper error presentation. This is a text-based heuristic, so it may produce false positives if the patterns appear in comments or unrelated string literals.

### Non-Violating Examples
```swift
struct MyView: View {
    @State private var errorMessage: String? = nil

    var body: some View {
        Text("Content")
            .alert("Error", isPresented: .constant(errorMessage != nil)) {
                Button("OK") { errorMessage = nil }
            } message: {
                Text(errorMessage ?? "")
            }
    }
}
```

### Violating Examples
```swift
struct MyView: View {
    var error: Error?

    var body: some View {
        if let error = error {
            Text("Error: \(error.localizedDescription)")  // basic text display, no alert
        }
    }
}
```

---
