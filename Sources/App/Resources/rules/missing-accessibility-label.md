[← Back to Rules](RULES.md)

## Missing Accessibility Label

**Identifier:** `Missing Accessibility Label`
**Category:** Accessibility
**Severity:** Warning

### Rationale
A `Button` that contains an `Image` without an `.accessibilityLabel()` modifier provides no information to VoiceOver. Screen readers will announce the image file name or nothing at all, making the button unusable for users who rely on assistive technologies.

### Discussion
`ButtonAccessibilityChecker` searches for `Image` views inside `Button` declarations (recursively, including trailing closures and labeled `label:` arguments). When an image is found and no `.accessibilityLabel()` modifier is present on the button, a warning is reported. Buttons that contain only `Text` are handled by the `missingAccessibilityHint` rule.

### Non-Violating Examples
```swift
Button {
    deleteItem()
} label: {
    Image(systemName: "trash")
}
.accessibilityLabel("Delete item")
```

### Violating Examples
```swift
Button {
    deleteItem()
} label: {
    Image(systemName: "trash")  // no accessibilityLabel
}
```

---
