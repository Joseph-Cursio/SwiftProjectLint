[← Back to Rules](RULES.md)

## Magic Layout Number

**Identifier:** `Magic Layout Number`
**Category:** Code Quality
**Severity:** Info
**Default:** Disabled (opt-in)

### Rationale
Teams that enforce a design token system want all spacing, sizing, and corner radius values to come from named constants (e.g., `Spacing.medium`, `Layout.cornerRadius`) rather than raw numeric literals. This ensures visual consistency and makes design updates a single-point change.

This rule is disabled by default because inline layout numbers like `.padding(16)` and `spacing: 12` are idiomatic SwiftUI for most teams. Enable it when your project has a design token system to enforce.

### Enabling the Rule
Add it to `enabled_only` in `.swiftprojectlint.yml`:
```yaml
enabled_only:
  - "Magic Layout Number"
```

Or run the CLI with `--rule "Magic Layout Number"`.

### Scope
- Flags numeric literals (integer and float) at or above the threshold (default: 10) that appear **2 or more times** in the same file within SwiftUI layout contexts
- Detects numbers in layout modifiers: `padding`, `spacing`, `frame`, `cornerRadius`, `opacity`, `blur`, `shadow`, `offset`, `rotation`, `scaleEffect`, `lineLimit`, `lineSpacing`
- Detects numbers in layout argument labels: `width`, `height`, `radius`, `lineWidth`, `minimum`, `maximum`, `horizontal`, `vertical`, `top`, `bottom`, `leading`, `trailing`
- Does **not** flag single-use layout numbers
- Does **not** flag numbers below the threshold

### Non-Violating Examples
```swift
// Named design tokens
enum Spacing {
    static let small: CGFloat = 8
    static let medium: CGFloat = 16
}

Text("Hello")
    .padding(Spacing.medium)
    .cornerRadius(Layout.cornerRadius)
```

### Violating Examples
```swift
// Raw layout number repeated without a named constant
Text("Hello")
    .padding(16)
    .frame(width: 16)

VStack(spacing: 12) { ... }
LazyVGrid(columns: [...], spacing: 12) { ... }
```

---
