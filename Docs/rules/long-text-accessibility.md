[← Back to Rules](RULES.md)

## Long Text Accessibility

**Identifier:** `Long Text Accessibility`
**Category:** Accessibility
**Severity:** Info

### Rationale
Long text content (over 50 characters) can be difficult for VoiceOver users to navigate. Adding `.accessibilityLabel()` with a condensed summary, `.accessibilityHint()` with context, or `.accessibilityValue()` can improve the experience for users who rely on assistive technologies.

### Scope
- Flags `Text` views whose string literal content exceeds 50 characters
- Does **not** flag `Text` views that already have an `.accessibilityLabel()`, `.accessibilityHint()`, or `.accessibilityValue()` modifier
- Does **not** flag short text (50 characters or fewer)
- Does **not** flag text constructed from variables or string interpolation — only literal strings are measured
- Info severity reflects that long text is already accessible to VoiceOver; this is an enhancement suggestion

### Non-Violating Examples
```swift
// Long text with accessibility summary
Text("Click \"Check\" to analyze your configuration compatibility with the selected SwiftLint version")
    .accessibilityLabel("Check configuration compatibility")

// Short text — under threshold
Text("No issues found")
```

### Violating Examples
```swift
// Long literal text with no accessibility modifiers
Text("Click \"Check\" to analyze your configuration compatibility with the selected SwiftLint version")
```

---
