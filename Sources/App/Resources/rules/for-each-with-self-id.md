[← Back to Rules](RULES.md)

## ForEach With Self ID (UI)

**Identifier:** `ForEach With Self ID`
**Category:** UI Patterns
**Severity:** Warning

### Rationale
This UI-category rule detects the same `ForEach(items, id: \.self)` anti-pattern as the performance-category `forEachSelfID` rule, but from the UI pass. Using `\.self` as the identity breaks smooth list animations because mutated values hash to different identities, causing SwiftUI to remove and re-add rows rather than animate them in place.

### Discussion
`ForEachSelfIDVisitor` performs the same check as `PerformanceDetectionHelpers.detectForEachSelfID`. The duplicate detection exists because the UI analysis pass and the performance analysis pass run independently. See the [ForEach Self ID](for-each-self-id.md) rule under Performance for detailed discussion.

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
