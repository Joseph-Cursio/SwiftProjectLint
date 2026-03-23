[← Back to Rules](RULES.md)

## Hardcoded Animation Values

**Identifier:** `Hardcoded Animation Values`
**Category:** Animation
**Severity:** Info

### Rationale
Numeric literals in animation factory calls — such as `.easeIn(duration: 0.3)` or `.spring(response: 0.5, dampingFraction: 0.8)` — are magic numbers. When the same animation is used in multiple places, or when designers ask to adjust the feel, you must hunt down every literal. Named constants make changes immediate and the animation semantics self-documenting.

### Discussion
`HardcodedAnimationValuesVisitor` checks calls to animation factories: `easeIn`, `easeOut`, `easeInOut`, `linear`, `spring`, `interactiveSpring`, and `interpolatingSpring`. For each recognized parameter label (`duration`, `response`, `dampingFraction`, `bounce`, `blendDuration`, `speed`, `repeatCount`) it checks whether the argument is a float or integer literal. If the argument is a named constant or variable reference, no issue is reported.

### Non-Violating Examples
```swift
let animationDuration: Double = 0.3

struct ConstantDurationView: View {
    @State private var isVisible = false

    var body: some View {
        Text("Hello")
            .animation(.easeIn(duration: animationDuration), value: isVisible)
    }
}

// No parameters at all — no issue
struct DefaultSpringView: View {
    @State private var isVisible = false

    var body: some View {
        Text("Hello")
            .animation(.spring(), value: isVisible)
    }
}
```

### Violating Examples
```swift
struct SlowEaseView: View {
    @State private var isVisible = false

    var body: some View {
        Text("Hello")
            .opacity(isVisible ? 1 : 0)
            .animation(.easeIn(duration: 0.5), value: isVisible)  // literal duration
    }
}

struct SpringView: View {
    @State private var isVisible = false

    var body: some View {
        Text("Hello")
            .animation(.spring(response: 0.3, dampingFraction: 0.8), value: isVisible)  // literal response and dampingFraction
    }
}
```

---
