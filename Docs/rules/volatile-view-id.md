[← Back to Rules](RULES.md)

## Volatile View ID

**Identifier:** `Volatile View ID`
**Category:** Performance
**Severity:** Warning

### Rationale
SwiftUI uses a view's `.id(_:)` value as its **stable identity**. When that value changes, SwiftUI does not diff the view — it tears down the entire existing subtree and builds a brand-new one in its place. Deliberately changing an `.id` to "force a refresh" throws away all of that work on every change.

For a `List`, `Table`, or other collection view this is especially harmful: the view is backed by an `NSTableView`/`UITableView`, and rebuilding its identity reloads the table **while it is already mid-update**. On macOS this surfaces as the runtime warning *"Application performed a reentrant operation in its NSTableView delegate. This warning will become an assert in the future."* It also discards scroll position, selection, and focus, and animates as a full replacement rather than an in-place update.

### Discussion
The rule looks for a `.id(token)` view modifier whose argument is a bare property reference — `.id(refreshToken)` or `.id(self.refreshToken)` — and then checks whether that same name is **reassigned** anywhere in the file (`refreshToken = UUID()`, `version += 1`). Only the combination fires:

- A stable `.id(someConstant)` that is never reassigned is fine — that is the legitimate use of `.id`.
- A keypath/member id such as `.id(item.id)` is excluded, since that is how you give `ForEach` rows their per-element identity.

The fix is to stop resetting identity and instead let SwiftUI update the view from the state its subviews already observe. Bindings, `@State`, `@Observable`, and `Set`/array contents all drive updates reactively without recreating the view. If you genuinely need to reset a subtree (e.g. a "start over" screen), prefer driving that from real navigation/presentation state rather than a churning token.

### Non-Violating Examples
```swift
// Stable identity — never reassigned.
List(rows) { row in RowView(row) }
    .id(sectionKind)            // sectionKind does not change as a "refresh" hack

// Per-element identity via a keypath.
ForEach(items, id: \.id) { item in ItemView(item) }
```

### Violating Examples
```swift
struct RulesView: View {
    @State private var listRefreshToken = UUID()

    var body: some View {
        VStack {
            Button("Select All") {
                enabledRules = allRules
                listRefreshToken = UUID()      // reassigned to force a rebuild
            }
            List(rules) { rule in RuleRow(rule) }
                .id(listRefreshToken)          // ← Volatile View ID
        }
    }
}
```

```swift
// An incrementing counter used purely to re-render is the same anti-pattern.
ScrollView { content }
    .id(reloadVersion)                         // reloadVersion += 1 elsewhere
```

---
