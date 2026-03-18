[← Back to Rules](RULES.md)

## ForEach Without ID

**Identifier:** `ForEach Without ID`
**Category:** Performance
**Severity:** Warning

### Rationale
`ForEach` uses the `id` parameter to perform efficient diffing when the collection changes. Without an explicit `id`, SwiftUI falls back to index-based identity, which defeats structural diffing and forces full redraws of unchanged elements.

### Discussion
This performance-category rule is detected by `PerformanceVisitor`. A companion UI-category rule (`forEachWithoutIDUI`) detects the same pattern from the UI visitor. The two rules exist because the same issue is independently flagged by both the performance and UI analysis passes. If a `ForEach` item type conforms to `Identifiable`, the `ForEach(_:content:)` form implicitly uses the `id` property and does not trigger this rule.

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
