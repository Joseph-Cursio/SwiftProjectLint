[← Back to Rules](RULES.md)

## Unused State Variable

**Identifier:** `Unused State Variable`
**Category:** State Management
**Severity:** Warning

### Rationale
A `@State`, `@StateObject`, or related property wrapper variable that is declared but never referenced in the view body or in functions called from the view adds unnecessary overhead. SwiftUI allocates and tracks storage for every `@State` property; unused ones waste memory and complicate the view's mental model.

### Discussion
`SwiftUIManagementVisitor` compares declared state variables against variable references found in the view's body and child functions. A variable is considered unused if its identifier never appears in any expression within the view scope. Remove unused state variables or replace them with the logic that should use them.

### Non-Violating Examples
```swift
struct CounterView: View {
    @State private var count = 0
    var body: some View {
        Button("Tap") { count += 1 }
        Text("\(count)")
    }
}
```

### Violating Examples
```swift
struct MyView: View {
    @State private var count = 0   // declared but never used
    @State private var name = ""   // declared but never used
    var body: some View {
        Text("Hello")
    }
}
```

---
