[← Back to Rules](RULES.md)

## Inconsistent Styling

**Identifier:** `Inconsistent Styling`
**Category:** UI Patterns
**Severity:** Info

### Rationale
Applying many visual styling modifiers directly to individual `Text` elements — rather than extracting them into a shared `ViewModifier` or style extension — leads to visual inconsistency as the number of styled elements grows. Repeated inline styling is also harder to update when the design changes.

### Scope
- Flags `Text` views with **4 or more** visual styling modifiers applied directly
- Only counts visual styling modifiers: `font`, `foregroundColor`, `foregroundStyle`, `background`, `shadow`, `border`, `bold`, `italic`, `underline`, `strikethrough`, `fontWeight`, `fontDesign`
- Does **not** count layout modifiers (`padding`, `cornerRadius`, `frame`, `lineLimit`) — these are structural, not visual style
- Does **not** count behavioral modifiers (`onAppear`, `accessibilityLabel`, etc.)
- Only counts modifiers applied directly to the `Text`, not modifiers on enclosing container views

### Non-Violating Examples
```swift
// Style extracted to a ViewModifier
struct BadgeStyle: ViewModifier {
    func body(content: Content) -> some View {
        content
            .font(.caption2)
            .fontWeight(.semibold)
            .foregroundStyle(.white)
            .background(Capsule().fill(Color.red))
    }
}

Text("3").modifier(BadgeStyle())
```

```swift
// 2-3 styling modifiers is normal — not flagged
Text("Hello")
    .font(.headline)
    .foregroundColor(.blue)
    .bold()
```

### Violating Examples
```swift
// 4+ visual styling modifiers inline — extract to a ViewModifier
Text("3")
    .font(.caption2)
    .fontWeight(.semibold)
    .foregroundStyle(.white)
    .background(Capsule().fill(Color.red))
```

---
