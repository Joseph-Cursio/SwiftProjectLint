[← Back to Rules](RULES.md)

## Icon-Only Button Missing Label

**Identifier:** `Icon-Only Button Missing Label`
**Category:** Accessibility
**Severity:** Warning

### Rationale
A `Button` containing only an `Image` and no text is completely invisible to VoiceOver. Screen readers have no text to announce, making the button unusable for users who rely on assistive technologies. This is a WCAG 2.1 Level A failure (Success Criterion 1.1.1 — Non-text Content).

### Scope
- Flags `Button` views that contain an `Image` but no `Text`, no string title, and no `.accessibilityLabel()` modifier
- Checks images in trailing closures, `label:` arguments, and nested stacks
- Does **not** flag buttons that contain both `Image` and `Text`
- Does **not** flag buttons that use `Label` — `Label` provides accessible text automatically
- Does **not** flag buttons with an `.accessibilityLabel()` modifier
- Does **not** flag buttons with `.accessibilityHidden(true)` — hidden elements are invisible to VoiceOver
- Warning severity reflects that this is a functional accessibility failure, not a style suggestion

### Non-Violating Examples
```swift
// Icon button with accessibility label
Button {
    deleteItem()
} label: {
    Image(systemName: "trash")
}
.accessibilityLabel("Delete item")

// Button using Label — accessible by default
Button {
    deleteItem()
} label: {
    Label("Delete", systemImage: "trash")
}

// Button with labelStyle(.iconOnly) — still has accessible text from Label
Button("Delete", systemImage: "trash") {
    deleteItem()
}
.labelStyle(.iconOnly)
```

### Violating Examples
```swift
// Icon-only button with no label — invisible to VoiceOver
Button {
    deleteItem()
} label: {
    Image(systemName: "trash")
}

// Image as direct argument with no label
Button(action: deleteItem) {
    Image(systemName: "trash")
}
```

---
