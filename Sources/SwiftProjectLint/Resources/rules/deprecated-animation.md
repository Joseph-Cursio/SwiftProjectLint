[← Back to Rules](RULES.md)

## Deprecated Animation

**Identifier:** `Deprecated Animation`
**Category:** Animation
**Severity:** Warning

### Rationale
The single-argument form `.animation(.easeIn)` was deprecated in iOS 15 / macOS 12 because it animates all changes to the view indiscriminately, including changes that should not be animated. The two-argument form `.animation(.easeIn, value: someState)` is precise: it animates only when `someState` changes.

### Discussion
`DeprecatedAnimationVisitor` detects `.animation()` modifier calls that have exactly one argument and whose base expression is not a `Binding` (since `Binding.animation()` is a different, still-current API). The fix is always to add a `value:` parameter that identifies the state driving the animation.

### Non-Violating Examples
```swift
struct MyView: View {
    @State private var isVisible = false

    var body: some View {
        Text("Hello")
            .animation(.default, value: isVisible)  // explicit value parameter
    }
}

// Binding.animation() is not deprecated — no issue
struct MyView: View {
    @State private var text = ""
    var body: some View {
        TextField("Input", text: $text.animation())
    }
}
```

### Violating Examples
```swift
struct MyView: View {
    @State private var isAnimating = false

    var body: some View {
        Text("Hello, World!")
            .animation(.default)  // deprecated single-argument form
    }
}
```

---
