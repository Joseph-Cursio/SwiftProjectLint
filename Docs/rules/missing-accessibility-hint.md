[← Back to Rules](RULES.md)

## Missing Accessibility Hint

**Identifier:** `Missing Accessibility Hint`
**Category:** Accessibility
**Severity:** Info

### Rationale
Accessibility hints provide additional context about what an interactive element does, beyond its label. For text buttons — where VoiceOver reads the button text automatically — a hint answers "what happens when I activate this?" Apple's Human Interface Guidelines recommend using hints sparingly for actions whose effect isn't obvious from the label alone.

### Scope
- Flags `Button` views containing `Text` that lack an `.accessibilityHint()` modifier
- Does **not** flag buttons that use `Label` — `Label` provides accessible text automatically
- Does **not** flag icon-only buttons — those are covered by the [Icon-Only Button Missing Label](icon-only-button-missing-label.md) rule
- Does **not** flag buttons with `.accessibilityHidden(true)` — hidden elements are invisible to VoiceOver
- Info severity reflects that hints are recommended but not mandatory for all buttons

### Non-Violating Examples
```swift
// Button with hint
Button("Submit") {
    submitForm()
}
.accessibilityHint("Submits the form and navigates to confirmation")

// Button using Label — accessible by default
Button {
    deleteItem()
} label: {
    Label("Delete", systemImage: "trash")
}

// Decorative button hidden from VoiceOver — no hint needed
Button("Dismiss") {
    dismiss()
}
.accessibilityHidden(true)
```

### Violating Examples
```swift
// Text button with no hint
Button("Submit") {
    submitForm()
}
```

---
