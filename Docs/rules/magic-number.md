[← Back to Rules](RULES.md)

## Magic Number

**Identifier:** `Magic Number`
**Category:** Code Quality
**Severity:** Info

### Rationale
An integer or float literal of 10 or greater that appears without a named constant is a "magic number." Its meaning is not self-evident to future readers, and if the same value appears in multiple places, a change requires finding and updating every occurrence.

### Scope
- Flags numeric literals (integer and float) at or above the threshold (default: 10) that appear **2 or more times** in the same file
- Checks both variable initializers and function call arguments
- Does **not** flag single-use numbers — a number appearing once may be intentional
- Does **not** flag numbers below the threshold (default: 10; strict mode: 5)
- Does **not** flag numbers in SwiftUI layout modifier contexts — values like `.padding(16)`, `spacing: 12`, `.frame(width: 300)` are standard design tokens, not magic numbers

### Layout Modifiers Excluded
Numbers passed to these modifiers and argument labels are skipped:
- **Modifiers**: `padding`, `spacing`, `frame`, `cornerRadius`, `opacity`, `blur`, `shadow`, `offset`, `rotation`, `scaleEffect`, `lineLimit`, `lineSpacing`
- **Argument labels**: `width`, `height`, `minWidth`, `maxWidth`, `minHeight`, `maxHeight`, `horizontal`, `vertical`, `top`, `bottom`, `leading`, `trailing`, `minimum`, `maximum`, `radius`, `lineWidth`
- **Constructors**: `GridItem`, `RoundedRectangle`, `UnevenRoundedRectangle`

### Non-Violating Examples
```swift
// Named constant
let maxRetries = 3
let defaultTimeout: TimeInterval = 30

func configure() {
    connection.timeout = defaultTimeout
    retry(count: maxRetries)
}

// SwiftUI layout values — not flagged
Text("Hello")
    .padding(16)
    .frame(width: 300, height: 200)
    .cornerRadius(12)
```

### Violating Examples
```swift
// Score thresholds repeated without a named constant
if score >= 80 { grade = "B" }
if score >= 80 { showBadge = true }

// Business logic number repeated
let maxItems = 100
Text("\(items.count)").tag(100)
```

---
