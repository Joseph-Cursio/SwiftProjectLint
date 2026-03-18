[← Back to Rules](RULES.md)

## Inconsistent Styling

**Identifier:** `Inconsistent Styling`
**Category:** UI Patterns
**Severity:** Info

### Rationale
Applying more than one styling modifier (font, foregroundColor, background, padding, cornerRadius, shadow, border) directly to individual `Text` elements in the same view, rather than extracting them into a shared `ViewModifier` or style extension, leads to visual inconsistency as the number of styled elements grows.

### Discussion
`UIVisitor` collects styling modifiers applied to each `Text` call by walking the parent expression chain. If more than one recognized styling modifier is found on a single `Text`, it reports an info issue suggesting extraction into a `ViewModifier`. This rule flags the threshold at two or more styling modifiers on a single `Text`.

### Non-Violating Examples
```swift
// Style extracted to a ViewModifier
struct HeadlineStyle: ViewModifier {
    func body(content: Content) -> some View {
        content
            .font(.headline)
            .foregroundColor(.primary)
    }
}

struct MyView: View {
    var body: some View {
        Text("Title").modifier(HeadlineStyle())
    }
}
```

### Violating Examples
```swift
struct MyView: View {
    var body: some View {
        Text("Title")
            .font(.headline)
            .foregroundColor(.blue)  // two styling modifiers inline
    }
}
```

---
