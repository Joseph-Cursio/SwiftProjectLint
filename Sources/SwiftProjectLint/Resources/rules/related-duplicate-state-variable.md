[← Back to Rules](RULES.md)

## Related Duplicate State Variable

**Identifier:** `Related Duplicate State Variable`
**Category:** State Management
**Severity:** Warning

### Rationale
When the same state variable name appears in views that are part of the same hierarchy, SwiftUI will separately track the value in each view. Changes in one view do not automatically propagate to the other. The intended solution is a shared `ObservableObject` injected via `.environmentObject()`.

### Discussion
This rule is a cross-file analysis that operates after all files in a project have been parsed. The `SwiftUIManagementVisitor` collects all `@State` and `@StateObject` variable names per view, and the `CrossFileAnalysisEngine` then correlates duplicates across views that share a parent-child relationship in the view hierarchy. A duplicate found in related views is a stronger signal than one found in unrelated views, and therefore carries a warning severity rather than the info severity used by the unrelated-duplicate rule.

Suppress this rule when different views in the hierarchy intentionally track independent copies of the same local UI state (for example, each row cell in a list tracking its own expansion state under the same variable name).

### Non-Violating Examples
```swift
// Shared state lifted into an ObservableObject injected at the root
class AppState: ObservableObject {
    @Published var isLoggedIn = false
}

struct RootView: View {
    @StateObject private var appState = AppState()
    var body: some View {
        ChildView().environmentObject(appState)
    }
}

struct ChildView: View {
    @EnvironmentObject var appState: AppState
    var body: some View {
        Text(appState.isLoggedIn ? "Logged in" : "Logged out")
    }
}
```

### Violating Examples
```swift
// isLoggedIn tracked independently in both a parent and a child view
struct ParentView: View {
    @State private var isLoggedIn = false
    var body: some View { ChildView() }
}

struct ChildView: View {
    @State private var isLoggedIn = false  // duplicate in related view
    var body: some View { Text("Child") }
}
```

---
