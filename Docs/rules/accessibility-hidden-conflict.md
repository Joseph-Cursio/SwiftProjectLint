[<- Back to Rules](RULES.md)

## Accessibility Hidden Conflict

**Identifier:** `Accessibility Hidden Conflict`
**Category:** Accessibility
**Severity:** Warning

### Rationale
Applying `.accessibilityHidden(true)` removes an element from the accessibility tree entirely. Any other accessibility modifiers on the same view (`.accessibilityLabel()`, `.accessibilityHint()`, `.accessibilityValue()`, `.accessibilityAddTraits()`, etc.) become unreachable and have no effect. This is always a mistake -- either the element should be hidden (and the other modifiers removed) or the element should be visible (using `.accessibilityElement(children: .ignore)` instead of `.accessibilityHidden(true)`).

### Scope
- Flags views with `.accessibilityHidden(true)` alongside any other accessibility modifier in the same modifier chain
- Detects conflicts with: `.accessibilityLabel()`, `.accessibilityHint()`, `.accessibilityValue()`, `.accessibilityAddTraits()`, `.accessibilityRemoveTraits()`, `.accessibilityAction()`, `.accessibilityAdjustableAction()`, `.accessibilityCustomAction()`, `.accessibilitySortPriority()`
- Reports which specific conflicting modifiers were found

### Non-Violating Examples
```swift
// Hidden only -- correct for decorative elements
Image("background")
    .accessibilityHidden(true)

// Using .ignore to replace child semantics with custom attributes
HStack {
    Image(systemName: "star")
    Text("Favorite")
}
.accessibilityElement(children: .ignore)
.accessibilityLabel("Favorite")
```

### Violating Examples
```swift
// Hidden but also labeled -- label is unreachable
Image("icon")
    .accessibilityHidden(true)
    .accessibilityLabel("Send")

// Hidden with multiple conflicting modifiers
HStack { /* ... */ }
    .accessibilityHidden(true)
    .accessibilityLabel("Custom label")
    .accessibilityHint("Does something")
```

---
