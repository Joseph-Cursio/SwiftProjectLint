[← Back to Rules](RULES.md)

## Modifier Order Issue

**Identifier:** `Modifier Order Issue`
**Category:** UI Patterns
**Severity:** Warning

### Rationale
In SwiftUI, modifier order determines visual outcome, and a modifier only affects the view *beneath* it in the chain.

`.clipShape()` (and `.cornerRadius()`) masks the view it is applied to. A `.background()` added **after** the clip is drawn behind the already-clipped view at its full rectangular bounds, so it is *not* clipped — usually a bug. The clipped-background idiom is therefore `.background().clipShape()`: add the background first, then clip the composited result so the background is clipped too.

`.shadow()` works the opposite way: a shadow applied **before** a clip is clipped away entirely. Clip first, then shadow, so the shadow follows the clipped shape.

### Discussion
`ModifierOrderVisitor` walks modifier chains (nested `FunctionCallExprSyntax` nodes) and extracts the ordered list of modifier names. It then checks for known-bad orderings:

| Misordered (applied first) | Should come after | Why |
|----------------------------|-------------------|-----|
| `.clipShape()` / `.cornerRadius()` | `.background()` | The background is added after the clip, so it isn't clipped to the shape |
| `.shadow()` | `.clipShape()` or `.cornerRadius()` | The shadow is clipped away — apply it after the clip so it follows the shape |

Only chains containing both the "before" and "after" modifiers are checked. Chains with unrelated modifiers are ignored.

### Non-Violating Examples
```swift
Text("Hello")
    .background(Color.red)
    .clipShape(RoundedRectangle(cornerRadius: 10))  // background then clip — background IS clipped

Text("World")
    .cornerRadius(8)
    .shadow(radius: 5)        // clip then shadow — shadow follows the shape
```

### Violating Examples
```swift
Text("Hello")
    .clipShape(RoundedRectangle(cornerRadius: 10))
    .background(Color.red)    // clip before background — background is left unclipped

Text("World")
    .shadow(radius: 5)
    .cornerRadius(8)          // shadow before clip — shadow is clipped away
```

---
