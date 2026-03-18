[← Back to Rules](RULES.md)

## Default Animation Curve

**Identifier:** `Default Animation Curve`
**Category:** Animation
**Severity:** Info

### Rationale
`.animation(.default, value:)` defers the choice of curve to the system. The system default can change between OS versions, meaning the animation behavior of your app may change without you changing any code. Explicit curves such as `.easeInOut` or `.spring()` make behavior deterministic across OS updates.

### Discussion
`AnimationHierarchyVisitor` checks whether the first unlabeled argument to `.animation()` is a `.default` member access expression. The info severity reflects that using the system default is not wrong per se — it adapts to platform conventions — but it is worth a deliberate choice.

### Non-Violating Examples
```swift
struct ExplicitCurveView: View {
    @State private var isVisible = false

    var body: some View {
        Text("Hello")
            .opacity(isVisible ? 1 : 0)
            .animation(.easeInOut, value: isVisible)  // explicit curve
    }
}
```

### Violating Examples
```swift
struct DefaultCurveView: View {
    @State private var isVisible = false

    var body: some View {
        Text("Hello")
            .opacity(isVisible ? 1 : 0)
            .animation(.default, value: isVisible)  // system default curve
    }
}
```

---
