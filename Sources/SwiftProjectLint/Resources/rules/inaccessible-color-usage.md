[← Back to Rules](RULES.md)

## Inaccessible Color Usage

**Identifier:** `Inaccessible Color Usage`
**Category:** Accessibility
**Severity:** Info

### Rationale
Color alone must not be used to convey information. Users with color vision deficiencies (affecting approximately 8% of males) cannot distinguish information communicated solely through hue. WCAG 2.1 Success Criterion 1.4.1 requires that color not be the only visual means of conveying information.

### Discussion
`ColorAccessibilityChecker` flags two patterns: direct `Color.xxx` member accesses (e.g., `Color.red`), and `.foregroundColor()` modifier calls without a co-located `.accessibilityLabel()`, `.accessibilityHint()`, or `.accessibilityValue()` modifier. When a foreground color is used alongside an accessibility modifier, the flag is suppressed because the developer has consciously provided alternative context. The info severity reflects that some color usage is purely decorative and does not convey information.

### Non-Violating Examples
```swift
// Color with accompanying accessibility label
Circle()
    .foregroundColor(statusColor)
    .accessibilityLabel(statusDescription)

// Text is already accessible — color is decorative
Text("Success")
    .foregroundColor(.green)
    .accessibilityLabel("Success")
```

### Violating Examples
```swift
// Color.red used without any alternative text/icon
Circle()
    .foregroundColor(Color.red)  // color alone conveys status

// foregroundColor without accessibility modifier
Text("Error occurred")
    .foregroundColor(.red)  // color-only status indication
```

---
