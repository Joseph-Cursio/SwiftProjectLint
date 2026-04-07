[<- Back to Rules](RULES.md)

## Button Toggling Bool

**Identifier:** `Button Toggling Bool`
**Category:** Accessibility
**Severity:** Info

### Rationale
A `Button` whose action calls `.toggle()` on a Bool is functionally a toggle control. SwiftUI's `Toggle` with a custom `ToggleStyle` provides the same visual flexibility while automatically including semantic accessibility traits (`.isToggle`, `.isSelected`) that VoiceOver uses to announce the control type and state. Replacing the `Button` with a styled `Toggle` improves accessibility with no loss of visual control.

### Scope
- Flags `Button` views whose action closure contains a `.toggle()` call on a variable
- Detects `.toggle()` in both trailing-closure and `action:` argument forms
- Info severity reflects that this is a design suggestion, not a functional bug

### Non-Violating Examples
```swift
// Toggle with custom style -- accessible by default
Toggle("Warp Speed", isOn: $selected)
    .toggleStyle(MyCustomToggleStyle())

// Button that does not toggle a Bool
Button("Submit") {
    submitForm()
}
```

### Violating Examples
```swift
// Button is really a toggle control -- missing semantic traits
Button {
    isEnabled.toggle()
} label: {
    HStack {
        Image(systemName: isEnabled ? "circle.fill" : "circle")
        Text("Warp Speed")
    }
}
.buttonStyle(.plain)
```

---
