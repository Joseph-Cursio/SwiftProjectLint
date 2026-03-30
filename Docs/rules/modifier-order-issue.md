[← Back to Rules](RULES.md)

## Modifier Order Issue

**Identifier:** `Modifier Order Issue`
**Category:** UI Patterns
**Severity:** Warning

### Rationale
In SwiftUI, modifier order determines visual outcome. Applying `.background()` before `.clipShape()` means the background extends beyond the clipped region, which is almost never the intended result. Similarly, `.shadow()` before `.cornerRadius()` produces a rectangular shadow instead of one matching the rounded shape.

### Discussion
`ModifierOrderVisitor` walks modifier chains (nested `FunctionCallExprSyntax` nodes) and extracts the ordered list of modifier names. It then checks for known-bad orderings:

| Misordered | Should come after | Why |
|------------|-------------------|-----|
| `.background()` | `.clipShape()` or `.cornerRadius()` | Background won't be clipped to the shape |
| `.shadow()` | `.clipShape()` or `.cornerRadius()` | Shadow won't match the clipped shape |
| `.border()` | `.clipShape()` | Border won't follow the clip shape |

Only chains containing both the "before" and "after" modifiers are checked. Chains with unrelated modifiers are ignored.

### Non-Violating Examples
```swift
Text("Hello")
    .clipShape(RoundedRectangle(cornerRadius: 10))
    .background(Color.red)    // background after clipShape — correct

Text("World")
    .cornerRadius(8)
    .shadow(radius: 5)        // shadow after cornerRadius — correct
```

### Violating Examples
```swift
Text("Hello")
    .background(Color.red)
    .clipShape(RoundedRectangle(cornerRadius: 10))  // background before clipShape

Text("World")
    .shadow(radius: 5)
    .cornerRadius(8)          // shadow before cornerRadius
```

---
