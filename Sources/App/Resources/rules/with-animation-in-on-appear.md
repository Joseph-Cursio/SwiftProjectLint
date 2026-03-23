[← Back to Rules](RULES.md)

## withAnimation in onAppear

**Identifier:** `withAnimation in onAppear`
**Category:** Animation
**Severity:** Warning

### Rationale
Calling `withAnimation` inside `onAppear` runs immediately when the view first appears. This produces an animation that plays on every view appearance — including when returning from a pushed navigation destination or when a sheet is dismissed — which often feels jarring and unintended.

### Discussion
`WithAnimationVisitor` tracks `onAppear` closure depth and flags any `withAnimation` call found within that depth, including calls nested inside additional closures within `onAppear`. If an intro animation is genuinely desired on first appearance only, use `.task` with a `hasAppeared` guard flag, or use the `.animation(_, value:)` modifier form tied to a state variable that is set in `onAppear`.

### Non-Violating Examples
```swift
struct MyView: View {
    @State private var isVisible = false

    var body: some View {
        Button("Toggle") {
            withAnimation {
                isVisible = true  // withAnimation outside onAppear — fine
            }
        }
    }
}
```

### Violating Examples
```swift
struct MyView: View {
    @State private var isVisible = false

    var body: some View {
        Text("Hello")
            .onAppear {
                withAnimation {  // withAnimation inside onAppear
                    isVisible = true
                }
            }
    }
}
```

---
