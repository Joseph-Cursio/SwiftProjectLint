[← Back to Rules](RULES.md)

## Hardcoded Font Size

**Identifier:** `Hardcoded Font Size`
**Category:** Accessibility
**Severity:** Warning

### Rationale
Using `.font(.system(size: 48))` sets a fixed font size that ignores the user's Dynamic Type preference. Users who need larger (or smaller) text for readability will see no change, which is an accessibility barrier. Semantic text styles like `.font(.title)` automatically scale with the user's settings.

The same applies to custom faces. `.font(.custom("Avenir", size: 14))` is just as fixed as the system equivalent — and the fix is concrete, because SwiftUI provides `.custom(_:size:relativeTo:)` specifically so a custom font can scale against a text style. Using a brand font is not a reason to opt out of Dynamic Type.

### Discussion
`HardcodedFontSizeVisitor` checks `.font(...)` calls where the argument is a `.system(size:)` or `.custom(_:size:)` call with a literal integer or float value. Variable references, semantic text styles (`.largeTitle`, `.body`, etc.), text-style-based `.system(.body)` calls, and the anchored `.custom(_:size:relativeTo:)` form are not flagged.

If you need a specific size that isn't covered by a built-in text style, use `@ScaledMetric` to ensure the value still scales with Dynamic Type:

```swift
@ScaledMetric(relativeTo: .title) private var iconSize: CGFloat = 48
```

> **Changed:** custom fonts were previously exempt, on the reasoning that they "cannot use text styles". That is true of `.font(.title)` but not of Dynamic Type itself — `relativeTo:` and `@ScaledMetric` both scale a custom face — so the exemption was removed.

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

// Custom font anchored to a text style — scales with Dynamic Type
Text("Brand")
    .font(.custom("Avenir", size: 14, relativeTo: .body))

// Custom font with a scaled size
@ScaledMetric private var brandSize: CGFloat = 14

Text("Brand")
    .font(.custom("Avenir", size: brandSize))
```

### Violating Examples
```swift
// Literal integer size — bypasses Dynamic Type
Text("Hello")
    .font(.system(size: 48))

// Literal float size — also bypasses Dynamic Type
Text("Details")
    .font(.system(size: 14.0, weight: .bold, design: .rounded))

// Custom face with no relativeTo: anchor — equally fixed
Text("Brand")
    .font(.custom("Avenir", size: 14))
```

---
