[<- Back to Rules](RULES.md)

## Toggle Button Missing Selected Trait

**Identifier:** `Toggle Button Missing Selected Trait`
**Category:** Accessibility
**Severity:** Warning

### Rationale
When a `Button` visually toggles between states (e.g., selected vs. unselected) using a ternary expression, VoiceOver has no way to announce whether the button is currently selected unless `.accessibilityAddTraits(.isSelected)` is applied conditionally. Without this trait, the button looks interactive to sighted users but provides no state information to assistive technology users.

### Scope
- Flags `Button` views whose label closure contains a ternary expression (suggesting conditional visuals) without an `.accessibilityAddTraits` modifier
- Does **not** flag buttons with `.accessibilityHidden(true)` -- hidden elements are invisible to VoiceOver
- Does **not** flag buttons that already have `.accessibilityAddTraits`

### Non-Violating Examples
```swift
// Button with conditional visuals and selected trait
Button(action: { selected.toggle() }) {
    HStack {
        Image(systemName: selected ? "circle.fill" : "circle")
        Text("Warp Speed")
    }
}
.accessibilityAddTraits(selected ? .isSelected : [])
.buttonStyle(.plain)

// Button without conditional visuals -- no ternary, no issue
Button("Submit") {
    submitForm()
}
```

### Violating Examples
```swift
// Button toggles visually but VoiceOver cannot announce selection state
Button(action: { selected.toggle() }) {
    HStack {
        Image(systemName: selected ? "circle.fill" : "circle")
        Text("Warp Speed")
    }
}
.buttonStyle(.plain)
```

---
