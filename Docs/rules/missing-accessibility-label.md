[← Back to Rules](RULES.md)

## Missing Accessibility Label

**Identifier:** `Missing Accessibility Label`
**Category:** Accessibility
**Severity:** Warning

### Rationale
A standalone `Image` without an `.accessibilityLabel()` modifier provides no information to VoiceOver. Screen readers will announce the image file name or nothing at all, making the element invisible to users who rely on assistive technologies.

### Scope
- Flags `Image` views that lack an `.accessibilityLabel()` modifier
- Does **not** flag images inside a `Button` — those are covered by the [Icon-Only Button Missing Label](icon-only-button-missing-label.md) rule
- Does **not** flag images inside a `Label` — `Label` provides accessible text automatically
- Does **not** flag images with `.accessibilityHidden(true)` — explicitly marked as decorative

### Non-Violating Examples
```swift
// Image with accessibility label
Image(systemName: "star.fill")
    .accessibilityLabel("Favorited")

// Decorative image hidden from VoiceOver
Image("decorative-divider")
    .accessibilityHidden(true)

// Image inside a Label — Label provides accessibility automatically
Label("Settings", systemImage: "gear")
```

### Violating Examples
```swift
// Standalone image with no label
Image(systemName: "star.fill")

// Asset image with no label
Image("custom-icon")
```

---
