[← Back to Rules](RULES.md)

## Unnecessary View Update

**Identifier:** `Unnecessary View Update`
**Category:** Performance
**Severity:** Warning

### Rationale
When a state variable is assigned the value it already holds, SwiftUI still schedules a redraw because it observes the assignment, not whether the value changed. Unnecessary reassignments cause spurious re-renders that degrade scrolling performance and battery life.

### Discussion
`PerformanceVisitor` tracks state variable reads and writes. When it detects an assignment to a state variable where the right-hand side could be the same value (e.g., assigning a constant or immediately overwriting), it reports this as a potential unnecessary update. In practice, guarding assignments with an equality check (`if newValue != stateVar { stateVar = newValue }`) eliminates the unnecessary redraw.

### Non-Violating Examples
```swift
struct ToggleView: View {
    @State private var isOn = false
    var body: some View {
        Button("Toggle") {
            isOn.toggle()  // only mutates when the logical value changes
        }
    }
}
```

### Violating Examples
```swift
struct MyView: View {
    @State private var label = "Hello"
    var body: some View {
        Button("Reset") {
            label = "Hello"  // potentially the same value — causes unnecessary redraw
        }
    }
}
```

---
