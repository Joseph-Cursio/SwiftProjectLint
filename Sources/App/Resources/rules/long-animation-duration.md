[← Back to Rules](RULES.md)

## Long Animation Duration

**Identifier:** `Long Animation Duration`
**Category:** Animation
**Severity:** Info

### Rationale
Animations longer than two seconds feel sluggish and unresponsive to users. Human perception is particularly sensitive to delays longer than one second; an animation taking more than two seconds makes an app feel slow regardless of actual performance.

### Discussion
`AnimationPerformanceVisitor` extracts the `duration:` argument from animation factory calls (`.easeIn(duration:)`, `.easeOut(duration:)`, `.easeInOut(duration:)`, `.linear(duration:)`, `.spring(duration:)`) and compares it to the 2.0-second threshold. The boundary is exclusive: a duration of exactly 2.0 seconds does not trigger this rule. The info severity reflects that very occasionally a long animation is intentional (e.g., an ambient background transition).

### Non-Violating Examples
```swift
struct NormalView: View {
    @State private var isVisible = false

    var body: some View {
        Text("Hello")
            .animation(.easeIn(duration: 0.5), value: isVisible)
    }
}

// Exactly 2.0 is also fine
struct BoundaryView: View {
    @State private var isVisible = false

    var body: some View {
        Text("Hello")
            .animation(.easeIn(duration: 2.0), value: isVisible)
    }
}
```

### Violating Examples
```swift
struct SlowView: View {
    @State private var isVisible = false

    var body: some View {
        Text("Hello")
            .animation(.easeIn(duration: 3.0), value: isVisible)  // exceeds 2 seconds
    }
}

struct SlowSpringView: View {
    @State private var isVisible = false

    var body: some View {
        Text("Hello")
            .animation(.spring(duration: 5.0), value: isVisible)  // exceeds 2 seconds
    }
}
```

---
