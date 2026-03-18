[← Back to Rules](RULES.md)

## ForEach Without ID (UI)

**Identifier:** `ForEach Without ID UI`
**Category:** UI Patterns
**Severity:** Warning

### Rationale
This UI-category counterpart to the performance-category `forEachWithoutID` rule detects `ForEach` calls with no `id:` parameter. Without explicit identity, SwiftUI uses array indices, which fails when items are inserted or removed — causing incorrect animations and stale cell content.

### Discussion
`UIVisitor` checks every `ForEach` call for the presence of an `id:` labeled argument. If none is found, a warning is reported. The UI rule and the performance rule fire independently from their respective analysis passes.

### Non-Violating Examples
```swift
struct ContentView: View {
    let items = [Item(id: "1"), Item(id: "2")]

    var body: some View {
        ForEach(items, id: \.id) { item in
            Text(item.id)
        }
    }
}
```

### Violating Examples
```swift
struct ContentView: View {
    let items = ["A", "B", "C"]

    var body: some View {
        ForEach(items) { item in  // no id: parameter
            Text(item)
        }
    }
}
```

---
