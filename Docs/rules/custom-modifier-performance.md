[← Back to Rules](RULES.md)

## Custom Modifier Performance

**Identifier:** `Custom Modifier Performance`
**Category:** Performance
**Severity:** Warning

### Rationale
A custom `ViewModifier`'s `body(content:)` method is called on every view update. Expensive collection operations like `sorted()`, `filter()`, `map()`, `reduce()`, `flatMap()`, or `compactMap()` inside that method execute repeatedly and can degrade scroll and animation performance.

### Discussion
`CustomModifierPerformanceVisitor` identifies structs conforming to `ViewModifier`, then inspects their `body(content:)` method for calls to known expensive operations. The same set of operations flagged by `PerformanceVisitor` in view bodies applies here: `sorted`, `filter`, `map`, `reduce`, `flatMap`, and `compactMap`.

Operations in helper methods or computed properties on the modifier struct are not flagged because they can be lazily evaluated or cached. The rule specifically targets work done inside the body method itself.

### Non-Violating Examples
```swift
struct HighlightModifier: ViewModifier {
    let color: Color

    func body(content: Content) -> some View {
        content
            .padding()
            .background(color)
    }
}

struct ListModifier: ViewModifier {
    // Precomputed outside body — OK
    private var sortedItems: [String] { items.sorted() }
    let items: [String]

    func body(content: Content) -> some View {
        VStack { ForEach(sortedItems, id: \.self) { Text($0) } }
    }
}
```

### Violating Examples
```swift
struct FilteredListModifier: ViewModifier {
    let items: [String]

    func body(content: Content) -> some View {
        let visible = items.filter { !$0.isEmpty }  // runs every update
        VStack {
            ForEach(visible, id: \.self) { Text($0) }
            content
        }
    }
}
```

---
