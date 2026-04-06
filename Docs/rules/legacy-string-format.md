[← Back to Rules](RULES.md)

## Legacy String Format

**Identifier:** `Legacy String Format`
**Category:** Modernization
**Severity:** Info

### Rationale
`String(format:)` is a C-style API inherited from Objective-C. It uses printf-style format specifiers (`%d`, `%.2f`) that are neither type-safe nor localisation-aware. The modern `FormatStyle` API is type-safe, automatically respects the user's locale, and integrates directly with SwiftUI's `Text` via the `format:` parameter.

### Discussion
`LegacyStringFormatVisitor` detects `String(format:)` calls. These should be replaced with `FormatStyle` where possible.

```swift
// Before
let label = String(format: "%.2f", price)
let progress = String(format: "%d of %d", current, total)

// After — FormatStyle
let label = price.formatted(.number.precision(.fractionLength(2)))

// After — directly in SwiftUI Text
Text(price, format: .number.precision(.fractionLength(2)))

// After — string interpolation for simple cases
let progress = "\(current) of \(total)"
```

### Non-Violating Examples
```swift
let s = "\(value)"
let s = value.formatted(.number.precision(.fractionLength(2)))
Text(measurement, format: .measurement(width: .abbreviated))
let s = String(describing: someValue)
```

### Violating Examples
```swift
let s = String(format: "%.2f", value)
let s = String(format: "%d items", count)
let s = String(format: "%02d:%02d", minutes, seconds)
```

---
