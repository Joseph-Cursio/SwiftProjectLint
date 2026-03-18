[← Back to Rules](RULES.md)

## Missing Preview

**Identifier:** `Missing Preview`
**Category:** UI Patterns
**Severity:** Info

### Rationale
SwiftUI previews accelerate the development loop. A view without a preview requires launching the simulator to see any visual change. The Xcode canvas and `#Preview` macro make it inexpensive to add a preview, and even a minimal preview catches layout issues that unit tests cannot.

### Discussion
`UIVisitor` tracks view names (from `struct` declarations conforming to `View`) and preview declarations (from `#Preview` macro expansions and `PreviewProvider` conformances). After visiting each view struct, if no preview was detected for that view name in the file, an info-severity issue is reported. Test files (paths containing `test.swift`, `Test`, or `Tests`) are exempt because preview-less test helper views are common.

### Non-Violating Examples
```swift
struct ContentView: View {
    var body: some View { Text("Hello") }
}

#Preview {
    ContentView()
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
