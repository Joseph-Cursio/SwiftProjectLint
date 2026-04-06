[← Back to Rules](RULES.md)

## Missing Preview

**Identifier:** `Missing Preview`
**Category:** UI Patterns
**Severity:** Warning (public views) / Info (internal views)

### Rationale
SwiftUI previews accelerate the development loop. A view without a preview requires launching the simulator to see any visual change. The Xcode canvas and `#Preview` macro make it inexpensive to add a preview, and even a minimal preview catches layout issues that unit tests cannot.

### Scope
- Flags the **primary view** (first `View`-conforming struct) in a file when no `#Preview` macro or `PreviewProvider` struct is found
- Only flags **leaf components** — views without `@Environment`, `@EnvironmentObject`, `@Bindable`, or ViewModel-typed properties

**Tiered severity:**
- **`.warning`** for `public` or `open` views — these are part of a module's API and previews serve as living documentation
- **`.info`** for `internal` views with non-trivial bodies

**Suppressed:**
- `private` or `fileprivate` views (small helper views extracted for readability)
- Views with trivial bodies (< 4 source lines)
- Files matching `*+Extensions.swift` or `*Helper.swift`
- `App`-conforming structs (not previewable)
- Secondary/subcomponent views in the same file
- Views in test files

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
// Private helper view — suppressed
private struct HelperView: View {
    var body: some View {
        VStack { Text("A"); Text("B"); Text("C") }
    }
}

// Trivial body — suppressed
struct SimpleWrapper: View {
    var body: some View { Text("Hello") }
}
```

### Violating Examples
```swift
// Public view without preview — warning severity
public struct PublicView: View {
    var body: some View {
        VStack { Text("Hello"); Text("World"); Text("Detail") }
    }
}

// Internal view with non-trivial body — info severity
struct ContentView: View {
    var body: some View {
        VStack {
            Text("Hello")
            Text("Subtitle")
            Button("Action") { }
        }
    }
}
```

---
