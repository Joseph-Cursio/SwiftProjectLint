[← Back to Rules](RULES.md)

## Conflicting Animations

**Identifier:** `Conflicting Animations`
**Category:** Animation
**Severity:** Warning

### Rationale
When two `.animation(_, value: x)` modifiers with the same `value:` argument are chained on the same view, only the outermost modifier takes effect — the inner one is silently ignored. This misleads the reader into believing two animations apply, and the unused inner animation wastes type-checker work during compilation.

### Discussion
`AnimationHierarchyVisitor` inspects each `.animation(_, value:)` call. When it finds such a call, it checks whether the immediately inner expression in the modifier chain is also an `.animation(_, value:)` call with the same `value:` text. If so, it flags the pair. Remove the redundant modifier and keep only the intended one.

### Non-Violating Examples
```swift
struct NoConflictView: View {
    @State private var isVisible = false
    @State private var isExpanded = false

    var body: some View {
        Text("Hello")
            .animation(.easeIn, value: isVisible)
            .animation(.spring(), value: isExpanded)  // different values — no conflict
    }
}
```

### Violating Examples
```swift
struct ConflictView: View {
    @State private var isVisible = false

    var body: some View {
        Text("Hello")
            .animation(.easeIn, value: isVisible)
            .animation(.spring(), value: isVisible)  // same value — inner animation ignored
    }
}
```

---
