[← Back to Rules](RULES.md)

## Corner Radius Deprecated

**Identifier:** `Corner Radius Deprecated`
**Category:** Modernization
**Severity:** Warning

### Rationale
`.cornerRadius()` was deprecated in iOS 17. The modern replacement `.clipShape(.rect(cornerRadius:))` uses a typed shape, unlocks the `.continuous` corner style (matching Apple's design language), and composes cleanly with other shape-based modifiers like `.stroke()`.

### Discussion
`CornerRadiusDeprecatedVisitor` detects `.cornerRadius()` modifier calls. These should be replaced with `.clipShape(.rect(cornerRadius:))` or `.clipShape(RoundedRectangle(cornerRadius:))`.

```swift
// Before
Text("Card")
    .padding()
    .background(.blue)
    .cornerRadius(12)

// After — using shorthand rect
Text("Card")
    .padding()
    .background(.blue)
    .clipShape(.rect(cornerRadius: 12))

// After — with continuous corner style (matches iOS design)
Text("Card")
    .padding()
    .background(.blue)
    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
```

### Non-Violating Examples
```swift
Text("Hello").clipShape(.rect(cornerRadius: 10))
Text("Hello").clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
Text("Hello").clipShape(Circle())
```

### Violating Examples
```swift
Text("Hello").cornerRadius(8)
VStack { Text("Content") }.cornerRadius(16)
```

---
