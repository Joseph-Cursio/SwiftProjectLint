[← Back to Rules](RULES.md)

## Excessive Spring Animations

**Identifier:** `Excessive Spring Animations`
**Category:** Animation
**Severity:** Warning

### Rationale
Spring animations are computationally heavier than linear or ease animations because they simulate a physical spring system with continuous integration. More than three spring animations active simultaneously in a single struct puts measurable load on the animation engine and can cause dropped frames on older devices.

### Discussion
`AnimationPerformanceVisitor` counts `.spring()` call-sites within a `struct` declaration. The count resets at each new struct so that separate, independently animating views are not penalized together. The threshold is four or more — three springs in a struct are acceptable. The fix is to consolidate animations into a single `withAnimation(.spring())` block that animates all related state changes together.

### Non-Violating Examples
```swift
struct ModerateView: View {
    @State private var a = false
    @State private var b = false
    @State private var c = false

    var body: some View {
        VStack {
            Text("1").animation(.spring(), value: a)
            Text("2").animation(.spring(), value: b)
            Text("3").animation(.spring(), value: c)
        }
    }
}
```

### Violating Examples
```swift
struct AnimatedView: View {
    @State private var a = false
    @State private var b = false
    @State private var c = false
    @State private var d = false

    var body: some View {
        VStack {
            Text("1").animation(.spring(), value: a)
            Text("2").animation(.spring(), value: b)
            Text("3").animation(.spring(), value: c)
            Text("4").animation(.spring(), value: d)  // fourth spring — exceeds threshold
        }
    }
}
```

---
