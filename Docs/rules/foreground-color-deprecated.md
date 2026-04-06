[← Back to Rules](RULES.md)

## Foreground Color Deprecated

**Identifier:** `Foreground Color Deprecated`
**Category:** Modernization
**Severity:** Warning

### Rationale
`.foregroundColor()` was deprecated in iOS 17. The replacement `.foregroundStyle()` accepts any `ShapeStyle` — not just `Color` — enabling gradients, materials, and hierarchical styles. For flat colors the migration is a one-word change.

### Discussion
`ForegroundColorDeprecatedVisitor` detects `.foregroundColor()` modifier calls. These should be replaced with `.foregroundStyle()`.

```swift
// Before
Text("Hello")
    .foregroundColor(.red)

Image(systemName: "star")
    .foregroundColor(.accentColor)

// After
Text("Hello")
    .foregroundStyle(.red)

Image(systemName: "star")
    .foregroundStyle(.tint)

// Now also possible with foregroundStyle
Text("Gradient")
    .foregroundStyle(.linearGradient(colors: [.red, .blue], startPoint: .top, endPoint: .bottom))
```

### Non-Violating Examples
```swift
Text("Hello").foregroundStyle(.primary)
Text("Hello").foregroundStyle(.red)
Text("Hello").foregroundStyle(.secondary)
```

### Violating Examples
```swift
Text("Hello").foregroundColor(.blue)
Image(systemName: "heart").foregroundColor(.red)
```

---
