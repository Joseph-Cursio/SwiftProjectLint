[← Back to Rules](RULES.md)

## Animation in High Frequency Update

**Identifier:** `Animation in High Frequency Update`
**Category:** Animation
**Severity:** Warning

### Rationale
Attaching a `.animation()` modifier immediately after a high-frequency modifier — `onReceive`, `onChange`, or `task` — causes the animation system to run on every event emission. For a timer firing at 60 Hz or a text field's `onChange`, this can create hundreds of simultaneous animations per second, degrading performance and producing visual chaos.

### Discussion
`AnimationPerformanceVisitor` walks the modifier chain inward from an `.animation()` call. If any modifier within the chain is one of the high-frequency callbacks, it flags the pattern. The fix is to move the `.animation()` to a more narrowly scoped view or to use `withAnimation` inside the callback only when a specific condition is met.

### Non-Violating Examples
```swift
struct NormalView: View {
    @State private var isVisible = false

    var body: some View {
        Text("Hello")
            .opacity(isVisible ? 1 : 0)
            .animation(.spring(), value: isVisible)
    }
}
```

### Violating Examples
```swift
struct TimerView: View {
    let timer = Timer.publish(every: 1, on: .main, in: .common)
    @State private var count = 0

    var body: some View {
        Text("\(count)")
            .onReceive(timer) { _ in count += 1 }
            .animation(.spring(), value: count)  // animation chained after onReceive
    }
}

struct ChangeView: View {
    @State private var value = ""
    @State private var isEditing = false

    var body: some View {
        TextField("Input", text: $value)
            .onChange(of: value) { isEditing = true }
            .animation(.easeIn, value: isEditing)  // animation chained after onChange
    }
}
```

---
