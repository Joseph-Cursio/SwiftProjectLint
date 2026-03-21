[← Back to Rules](RULES.md)

## Inaccessible Color Usage

**Identifier:** `Inaccessible Color Usage`
**Category:** Accessibility
**Severity:** Info

### Rationale
Color alone must not be used to convey information. Users with color vision deficiencies (approximately 8% of males) cannot distinguish information communicated solely through hue. WCAG 2.1 Success Criterion 1.4.1 requires that color not be the only visual means of conveying information.

### Scope
- Flags direct `Color.xxx` member accesses (e.g., `Color.red`, `Color.green`) that could be conveying status or meaning
- Flags `.foregroundColor()` calls without a co-located `.accessibilityLabel()`, `.accessibilityHint()`, or `.accessibilityValue()` modifier
- Does **not** flag `.foregroundColor()` when an accessibility modifier is present on the same element

The rule filters out common non-informational patterns to reduce noise:
- **Non-informational colors**: `Color.clear`, `Color.gray`, `Color.primary`, `Color.secondary`, `Color.accentColor` — these are decorative or semantic system colors that adapt for accessibility
- **Low-opacity background tints**: `Color.xxx.opacity(n)` where `n ≤ 0.2` — these are subtle background tints (e.g., `Color.red.opacity(0.1)` behind an error section), not primary color indicators

### Non-Violating Examples
```swift
// Color with accompanying accessibility context
Circle()
    .foregroundColor(statusColor)
    .accessibilityLabel(statusDescription)

// Non-informational colors — always skipped
Rectangle().fill(Color.clear)
Rectangle().fill(Color.gray.opacity(0.2))
Circle().fill(Color.accentColor)

// Low-opacity background tint — skipped
VStack { ... }
    .background(Color.red.opacity(0.1))
```

### Violating Examples
```swift
// Full-strength color with no alternative indicator
Capsule().fill(Color.red)

// Ternary color conveying status without text/icon backup
Rectangle().fill(isError ? Color.red : Color.green)

// Higher opacity color usage
Circle().fill(Color.red.opacity(0.5))
```

---
