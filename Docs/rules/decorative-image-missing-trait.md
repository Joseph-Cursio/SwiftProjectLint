[<- Back to Rules](RULES.md)

## Decorative Image Missing Trait

**Identifier:** `Decorative Image Missing Trait`
**Category:** Accessibility
**Severity:** Info *(opt-in)*

### Rationale
Decorative images (backgrounds, dividers, visual flourishes) that lack `.accessibilityHidden(true)` are announced by VoiceOver, creating noise for screen reader users. Images that don't convey information should be explicitly hidden from the accessibility tree.

### Discussion
`DecorativeImageMissingTraitVisitor` detects `Image(...)` calls (not SF Symbols) that appear to be decorative based on:
- Image name containing decorative patterns ("background", "divider", "pattern", "gradient", etc.)
- Placement inside `.background()` or `.overlay()` modifiers
- Low `.opacity()` values (< 1.0)

The rule suppresses findings when the image has `.accessibilityHidden(true)`, `.accessibilityLabel()`, or `.accessibilityElement()` in its modifier chain, or when it's inside a `Button` or `Label`.

This rule is opt-in because determining "decorative" from AST alone is heuristic.

### Non-Violating Examples
```swift
// Explicitly hidden from accessibility
Image("headerBackground")
    .resizable()
    .accessibilityHidden(true)

// Has meaningful label
Image("chart")
    .accessibilityLabel("Sales chart showing Q4 results")

// SF Symbol — not flagged
Image(systemName: "star.fill")

// Inside a Button — handled by iconOnlyButtonMissingLabel
Button { } label: {
    Image("backgroundTexture")
}
```

### Violating Examples
```swift
// Decorative name without accessibility handling
Image("headerBackground")
    .resizable()
    .frame(height: 200)

// Inside .background() without accessibility
VStack { content }
    .background(Image("pattern").resizable())

// Low opacity suggests decorative
Image("gradient")
    .opacity(0.3)
```

---
