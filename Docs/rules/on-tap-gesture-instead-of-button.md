[<- Back to Rules](RULES.md)

## onTapGesture Instead of Button

**Identifier:** `onTapGesture Instead of Button`
**Category:** Accessibility
**Severity:** Warning

### Rationale
`.onTapGesture { }` bypasses SwiftUI's button semantics. Unlike `Button`, it provides no implicit `button` accessibility trait, no keyboard or pointer focus, and no haptic feedback on iOS. The only legitimate uses are when you specifically need `onTapGesture(count:)` for multi-tap detection or `onTapGesture { location in }` for tap position.

### Discussion
`OnTapGestureInsteadOfButtonVisitor` inspects `FunctionCallExprSyntax` nodes for `.onTapGesture` member accesses. It flags the zero-argument form (single trailing closure with no parameters). The following forms are allowed:
- `count:` argument with a value greater than 1 (e.g., double-tap)
- `coordinateSpace:` argument (location-aware overload)
- Trailing closure with a parameter (location-aware form)

### Non-Violating Examples
```swift
// Button — correct pattern
Button("Tap me") { doSomething() }

// Double-tap — legitimate use
Text("Double tap")
    .onTapGesture(count: 2) { doubleTapped() }

// Location-aware — legitimate use
Text("Tap here")
    .onTapGesture { location in
        handleTap(at: location)
    }
```

### Violating Examples
```swift
// Simple tap — should be a Button
Text("Tap me")
    .onTapGesture { doSomething() }

Image(systemName: "trash")
    .onTapGesture { deleteItem() }
```

---
