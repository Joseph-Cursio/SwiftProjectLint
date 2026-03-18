[← Back to Rules](RULES.md)

## Missing Accessibility Hint

**Identifier:** `Missing Accessibility Hint`
**Category:** Accessibility
**Severity:** Info

### Rationale
Accessibility hints provide additional context about what an interactive element does, beyond its label. For text buttons — where VoiceOver reads the label automatically — a hint answers "what happens when I activate this?" The info severity reflects that hints are strongly recommended but not mandatory for all buttons.

### Discussion
`ButtonAccessibilityChecker` checks buttons containing `Text` views for the presence of an `.accessibilityHint()` modifier. The check is a complementary signal to the accessibility label rule. Buttons that use `Label` views (which combine an image and text) may satisfy both rules if both a label and a hint are provided.

### Non-Violating Examples
```swift
Button("Submit") {
    submitForm()
}
.accessibilityHint("Submits the current form and navigates to the confirmation screen")
```

### Violating Examples
```swift
Button("Submit") {  // text button with no accessibilityHint
    submitForm()
}
```

---
