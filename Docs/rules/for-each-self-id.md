[← Back to Rules](RULES.md)

## ForEach Self ID

**Identifier:** `ForEach Self ID`
**Category:** Performance
**Severity:** Warning

### Rationale
Using `\.self` as the `id` in `ForEach` makes every value its own identity. For non-trivially equatable types, this forces SwiftUI to hash the entire value on every redraw, which is slower than comparing a stable identifier. It also breaks animations when values are mutated, because the old and new values hash differently and SwiftUI treats them as unrelated items.

Using `\.hashValue` as the `id` is even worse: `hashValue` is not guaranteed to be unique — hash collisions are expected and normal. This causes SwiftUI to confuse items with the same hash, leading to wrong items being updated or animated, items disappearing or duplicating, and subtle hard-to-reproduce bugs.

### Discussion
The rule inspects the `id:` argument of a `ForEach` call. If the argument expression evaluates to `\.self` or `\.hashValue`, the rule fires. Array literals and `.allCases` collections are excluded because `\.self` is idiomatic for those cases.

The fix is to introduce a stable `id` property — either by conforming to `Identifiable` or by explicitly specifying `id: \.stableProperty`.

### Non-Violating Examples
```swift
ForEach(items, id: \.id) { item in
    Text(item.name)
}
```

### Violating Examples
```swift
// Using \.self — forces full-value hashing on every redraw
ForEach(items, id: \.self) { item in
    Text(item.name)
}

// Using \.hashValue — hash collisions cause incorrect view updates
ForEach(items, id: \.hashValue) { item in
    Text(item.name)
}
```

---
