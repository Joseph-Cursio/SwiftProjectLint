[← Back to Rules](RULES.md)

## Expensive Operation in View Body

**Identifier:** `Expensive Operation in View Body`
**Category:** Performance
**Severity:** Warning

### Rationale
SwiftUI calls the `body` computed property every time state changes. Placing operations like `sorted`, `filter`, `map`, `reduce`, `flatMap`, or `compactMap` directly in `body` runs them on every redraw. For large collections this causes visible frame drops.

### Discussion
The `PerformanceVisitor` tracks whether execution is inside a `body` getter, then flags calls to any of the listed expensive operations when they appear there. The fix is to move the transformation into the ViewModel or into a `@State`/`@StateObject` property that is updated only when the underlying data changes. Alternatively, `Lazy` collection wrappers can defer evaluation.

### Non-Violating Examples
```swift
class ItemViewModel: ObservableObject {
    @Published var sortedItems: [Item] = []

    func loadItems(_ raw: [Item]) {
        sortedItems = raw.sorted { $0.name < $1.name }
    }
}

struct ItemListView: View {
    @StateObject private var vm = ItemViewModel()
    var body: some View {
        List(vm.sortedItems) { Text($0.name) }
    }
}
```

### Violating Examples
```swift
struct ItemListView: View {
    let items: [Item]
    var body: some View {
        // sorted runs on every redraw
        List(items.sorted { $0.name < $1.name }) { Text($0.name) }
    }
}
```

---
