[← Back to Rules](RULES.md)

## Hardcoded Font Size

**Identifier:** `Hardcoded Font Size`
**Category:** Accessibility
**Severity:** Warning

### Rationale
Using `.font(.system(size: 48))` sets a fixed font size that ignores the user's Dynamic Type preference. Users who need larger (or smaller) text for readability will see no change, which is an accessibility barrier. Semantic text styles like `.font(.title)` automatically scale with the user's settings.

### Discussion
`HardcodedFontSizeVisitor` checks `.font(...)` calls where the argument is a `.system(size:)` call with a literal integer or float value. Variable references, semantic text styles (`.largeTitle`, `.body`, etc.), text-style-based `.system(.body)` calls, and `.custom(...)` fonts are not flagged.

If you need a specific size that isn't covered by a built-in text style, use `@ScaledMetric` to ensure the value still scales with Dynamic Type:

```swift
@ScaledMetric(relativeTo: .title) private var iconSize: CGFloat = 48
```

### Non-Violating Examples
```swift
// Semantic text style — scales automatically
Text("Welcome")
    .font(.largeTitle)

// System font with text style — scales automatically
Text("Details")
    .font(.system(.body, design: .rounded))

// Variable size — assumed intentional (use @ScaledMetric)
@ScaledMetric private var fontSize: CGFloat = 14

Text("Hello")
    .font(.system(size: fontSize))

// Custom font — cannot use text styles
Text("Brand")
    .font(.custom("Avenir", size: 14))
```

### Violating Examples
```swift
// Literal integer size — bypasses Dynamic Type
Text("Hello")
    .font(.system(size: 48))

// Literal float size — also bypasses Dynamic Type
Text("Details")
    .font(.system(size: 14.0, weight: .bold, design: .rounded))
```

---
