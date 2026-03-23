[← Back to Rules](RULES.md)

## ForEach Self ID

**Identifier:** `ForEach Self ID`
**Category:** Performance
**Severity:** Warning

### Rationale
Using `\.self` as the `id` in `ForEach` makes every value its own identity. For non-trivially equatable types, this forces SwiftUI to hash the entire value on every redraw, which is slower than comparing a stable identifier. It also breaks animations when values are mutated, because the old and new values hash differently and SwiftUI treats them as unrelated items.

### Discussion
`PerformanceDetectionHelpers.detectForEachSelfID` inspects the `id:` argument of a `ForEach` call. If the argument expression evaluates to `\.self` (a key path rooted at `Self`), the rule fires. The fix is to introduce a stable `id` property — either by conforming to `Identifiable` or by explicitly specifying `id: \.stableProperty`.

### Non-Violating Examples
```swift
ForEach(items, id: \.id) { item in
    Text(item.name)
}
```

### Violating Examples
```swift
ForEach(items, id: \.self) { item in
    Text(item.name)
}
```

---
