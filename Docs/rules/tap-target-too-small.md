[<- Back to Rules](RULES.md)

## Tap Target Too Small

**Identifier:** `Tap Target Too Small`
**Category:** Accessibility
**Severity:** Warning

### Rationale
Apple's Human Interface Guidelines and WCAG 2.1 Success Criterion 2.5.5 recommend a minimum tap target size of 44×44 points. Interactive elements smaller than this are difficult for users with motor impairments, large fingers, or assistive devices to activate reliably.

### Discussion
`TapTargetTooSmallVisitor` identifies `.frame(width:height:)` calls on interactive elements (`Button`, `Toggle`, `Stepper`, `Slider`, `Link`, `NavigationLink`, `Menu`) where both dimensions are explicitly set and at least one is below 44pt. The rule walks the modifier chain backwards to verify the root is an interactive element.

The rule suppresses findings when `.padding()` is applied after `.frame()`, as padding expands the effective tap area.

### Non-Violating Examples
```swift
// Meets minimum
Button(action: { dismiss() }) {
    Image(systemName: "xmark")
}
.frame(width: 44, height: 44)

// Small frame with padding
Button(action: { dismiss() }) {
    Image(systemName: "xmark")
}
.frame(width: 20, height: 20)
.padding()

// Only one dimension set — other is system-determined
Button("OK") { }
    .frame(width: 30)
```

### Violating Examples
```swift
// Both dimensions below 44pt
Button(action: { dismiss() }) {
    Image(systemName: "xmark")
}
.frame(width: 30, height: 30)

// One dimension below 44pt
Toggle(isOn: $flag) { Text("Option") }
    .frame(width: 44, height: 20)
```

---
