[← Back to Rules](RULES.md)

## ForEach Without ID

**Identifier:** `ForEach Without ID`
**Category:** Performance
**Severity:** Warning

### Rationale
`ForEach` uses the `id` parameter to perform efficient diffing when the collection changes. Without an explicit `id`, SwiftUI falls back to index-based identity, which defeats structural diffing and forces full redraws of unchanged elements.

### Discussion
This rule is detected by `PerformanceVisitor`. It checks for a `ForEach` call with no `id:` argument. If the item type is known to conform to `Identifiable`, the `ForEach(_:content:)` form implicitly uses the `id` property and the rule does not trigger.

### Non-Violating Examples
```swift
struct ItemListView: View {
    let items: [Item]
    var body: some View {
        ForEach(items, id: \.id) { item in
            Text(item.name)
        }
    }
}

// Also fine: using Identifiable conformance
struct Item: Identifiable {
    let id: UUID
    let name: String
}

struct ItemListView: View {
    let items: [Item]
    var body: some View {
        ForEach(items) { item in Text(item.name) }  // implicit id from Identifiable
    }
}
```

### Violating Examples
```swift
struct ItemListView: View {
    let items: [String]
    var body: some View {
        // No id: parameter — index-based diffing
        ForEach(items) { item in
            Text(item)
        }
    }
}
```

---
