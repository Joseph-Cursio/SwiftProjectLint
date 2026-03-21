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
- Does **not** flag numbers inside `#Preview` blocks — these are sample/mock data, not business logic
- Does **not** flag numbers in SwiftUI design-token contexts (see exclusions below)
- Does **not** flag positional index arguments in `sqlite3_bind_*` functions

### Design-Token Exclusions
Numbers passed to these modifiers, argument labels, and constructors are skipped:
- **Modifiers**: `padding`, `spacing`, `frame`, `cornerRadius`, `opacity`, `blur`, `shadow`, `offset`, `rotation`, `scaleEffect`, `lineLimit`, `lineSpacing`, `font`, `system`
- **Argument labels**: `width`, `height`, `minWidth`, `maxWidth`, `minHeight`, `maxHeight`, `idealWidth`, `idealHeight`, `horizontal`, `vertical`, `top`, `bottom`, `leading`, `trailing`, `minimum`, `maximum`, `spacing`, `radius`, `lineWidth`, `size`, `weight`, `min`, `ideal`, `max`
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
