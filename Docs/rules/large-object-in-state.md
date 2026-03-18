[← Back to Rules](RULES.md)

## Large Object in State

**Identifier:** `Large Object in State`
**Category:** Memory Management
**Severity:** Info

### Rationale
Placing a large array — more than 100 literal elements — in a `@State` property means SwiftUI copies and manages the entire array as value-type state. Every mutation triggers a full copy of the array through the property observation chain, causing unnecessary memory allocations and potentially degrading performance.

### Discussion
`MemoryManagementVisitor` checks `@State` bindings whose type annotation is an `ArrayTypeSyntax` and whose initializer is an array literal with more than 100 elements. The threshold of 100 is configurable via `MemoryManagementVisitor.Configuration.maxArraySize`. The fix is to move the collection into an `@StateObject` view model, where mutations are controlled through `@Published` properties and SwiftUI only observes the reference, not the collection contents.

### Non-Violating Examples
```swift
struct ContentView: View {
    @State var items: [String] = ["item1", "item2", "item3"]  // small array — fine
    var body: some View { Text("Hello") }
}
```

### Violating Examples
```swift
struct ContentView: View {
    @State var items: [String] = [
        "item1", "item2", /* ... */ "item101"  // more than 100 elements
    ]
    var body: some View { Text("Hello") }
}
```

---
