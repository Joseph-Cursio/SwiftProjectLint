[← Back to Rules](RULES.md)

## Related Duplicate State Variable

**Identifier:** `Related Duplicate State Variable`
**Category:** State Management
**Severity:** Warning

### Rationale
A view and a child view it shows both own a `@State` or `@StateObject` with the same name. The two are separate sources of truth. The child's copy starts from whatever the parent passed in, and after that the two drift apart: a change in either view is invisible to the other. The usual fix is `@Binding` in the child, which makes it read and write the parent's value.

The parent and child can be in one file or in different files. This is the cross-file case a single-file linter cannot see.

### Discussion
The rule is a cross-file analysis (`RelatedDuplicateStateVisitor`), run after every file is parsed. It reports at the **child's** declaration, the one to change, and names the parent. A child shown by several parents that own the same name gets one report naming all of them.

**What counts as a parent showing a child.** The parent's declaration constructs the child anywhere: in `body`, in a helper property or method, inside a `sheet`/`popover`/`fullScreenCover` closure, as a `NavigationLink` destination, or in an extension of the parent. A "child" is any `View` struct declared in the project, so no list of system views decides it.

**What counts as the same state.** Both properties are `@State` or `@StateObject` (also written `@SwiftUI.State`) and share a name. When both spell out a type, the types must match as written. When either omits it, the name alone decides.

Not reported:
- a child that declares `@Binding var x`, which is the fix;
- views that never show one another, even when the names match;
- a grandchild compared with its grandparent: only direct parent/child pairs count;
- other wrappers, such as `@Environment`, `@AppStorage` or `@ObservedObject`;
- a view that shows itself (a recursive tree view);
- a child built in a `#Preview`, a free function or a non-view type.

Known limits, all of which make the rule quieter rather than louder:
- **A view name declared twice in the run is ambiguous**, for example the same name in two modules or two nested types. It takes part in no pair.
- **A child built through a qualified name (`Feature.Row()`) or a factory function is not seen.**

Suppress the rule on the child's declaration when each view really should keep its own copy, such as a list row tracking its own expansion state under a name its parent also uses.

### Suppression
```swift
// swiftprojectlint:disable:next related-duplicate-state-variable
@State private var isExpanded = false
```

### Non-Violating Examples
```swift
// The child takes a binding to the parent's state
struct ParentView: View {
    @State private var isLoggedIn = false
    var body: some View { ChildView(isLoggedIn: $isLoggedIn) }
}

struct ChildView: View {
    @Binding var isLoggedIn: Bool
    var body: some View { Toggle("Signed in", isOn: $isLoggedIn) }
}

// State shared more widely lives in an observable object both views read
@Observable final class Session { var isLoggedIn = false }

struct RootView: View {
    @State private var session = Session()
    var body: some View { AccountView().environment(session) }
}

struct AccountView: View {
    @Environment(Session.self) private var session
    var body: some View { Text(session.isLoggedIn ? "Signed in" : "Signed out") }
}
```

### Violating Examples
```swift
// ParentView.swift
struct ParentView: View {
    @State private var isLoggedIn = false
    var body: some View { ChildView() }
}

// ChildView.swift: reported here
struct ChildView: View {
    @State private var isLoggedIn = false  // a separate copy; the parent's changes never reach it
    var body: some View { Text(isLoggedIn ? "Signed in" : "Signed out") }
}
```

---
