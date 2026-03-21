[← Back to Rules](RULES.md)

## Missing Preview

**Identifier:** `Missing Preview`
**Category:** UI Patterns
**Severity:** Info

### Rationale
SwiftUI previews accelerate the development loop. A view without a preview requires launching the simulator to see any visual change. The Xcode canvas and `#Preview` macro make it inexpensive to add a preview, and even a minimal preview catches layout issues that unit tests cannot.

### Scope
- Flags the **primary view** (first `View`-conforming struct) in a file when no `#Preview` macro or `PreviewProvider` struct is found
- Only flags **leaf components** — views without `@Environment`, `@EnvironmentObject`, `@Bindable`, or ViewModel-typed properties. Views with these dependencies require non-trivial mock setup, making the suggestion less actionable.
- Does **not** flag `App`-conforming structs — app entry points are not previewable
- Does **not** flag secondary/subcomponent views in the same file — these are covered by the primary view's preview
- Does **not** flag views in test files (paths containing `Test`, `Tests`, or `test.swift`)

### Non-Violating Examples
```swift
// Primary view with preview
struct ContentView: View {
    var body: some View { Text("Hello") }
}

#Preview {
    ContentView()
}
```

```swift
// Multiple views — only primary needs a preview
struct HealthScoreBadge: View {
    var body: some View { Text("A") }
}

struct HealthScoreRing: View {     // not flagged — subcomponent
    var body: some View { Text("Ring") }
}
```

### Violating Examples
```swift
// No #Preview or PreviewProvider in the file
struct ContentView: View {
    var body: some View { Text("Hello") }
}
```

---
