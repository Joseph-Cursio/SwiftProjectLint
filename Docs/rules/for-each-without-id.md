[← Back to Rules](RULES.md)

## ForEach Without ID

**Identifier:** `ForEach Without ID`
**Category:** Performance
**Severity:** Warning

### Rationale
`ForEach` uses the `id` parameter to perform efficient diffing when the collection changes. Without an explicit `id`, SwiftUI falls back to index-based identity, which defeats structural diffing and forces full redraws of unchanged elements.

### Discussion
This rule is detected by `PerformanceVisitor`. It checks for a `ForEach` call with no `id:` argument. If the item type is known to conform to `Identifiable`, the `ForEach(_:content:)` form implicitly uses the `id` property and the rule does not trigger.

A type counts as `Identifiable` when it declares the conformance in its inheritance clause or in an `extension Type: Identifiable`, or, for a class, when it is a SwiftData `@Model` (a `PersistentModel`, which refines `Identifiable`).

The element type is read from a type annotation the file can see. For `ForEach(viewModel.items)`, where `items` is declared on another type, often in another file, the project-wide pre-scan lists every member property declared as `[T]` or `Array<T>` of an `Identifiable` `T`. Matching is by property name alone, so a name counts only when **every** member property of that name in the project is such an array; a single `var items: [String]`, or an `items` with no type annotation, keeps the warning.

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
