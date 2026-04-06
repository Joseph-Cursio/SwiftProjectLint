[<- Back to Rules](RULES.md)

## Computed Property View

**Identifier:** `Computed Property View`
**Category:** Architecture
**Severity:** Warning (Info if `@ViewBuilder` is present)

### Rationale
Computed properties that return `some View` are a common pattern for breaking up `body`, but they defeat SwiftUI's structural identity. SwiftUI can only diff views at the `body` boundary; sub-views expressed as computed properties get re-evaluated on every parent update with no diffing. Separate `struct` views give SwiftUI a stable identity boundary and can independently hold `@State`.

### Discussion
`ComputedPropertyViewVisitor` inspects `VariableDeclSyntax` nodes inside types that conform to `View` (or have a `var body: some View` property). It flags any computed property (other than `body`) whose type annotation is `some View`. Properties annotated with `@ViewBuilder` are flagged at `.info` severity since they at least get `@ViewBuilder` result-builder behaviour, though they still lack a stable identity boundary.

### Non-Violating Examples
```swift
// body is never flagged
struct ContentView: View {
    var body: some View {
        VStack { HeaderView() }
    }
}

// Separate View struct — correct pattern
struct HeaderView: View {
    var body: some View {
        Text("Title").font(.largeTitle)
    }
}

// Non-View type — not flagged
struct Utility {
    var helper: some View {
        Text("Not in a View type")
    }
}
```

### Violating Examples
```swift
struct ContentView: View {
    // Warning: computed property returning some View
    var header: some View {
        Text("Title").font(.largeTitle)
    }

    // Info: @ViewBuilder mitigates slightly
    @ViewBuilder
    var footer: some View {
        Text("Footer")
    }

    var body: some View {
        VStack {
            header
            footer
        }
    }
}
```

---
