[← Back to Rules](RULES.md)

## onTapGesture Missing Accessibility

**Identifier:** `onTapGesture Missing Accessibility`
**Category:** Accessibility
**Severity:** Info

### Rationale
Multi-tap gestures (`count: 2`, `count: 3`) and location-aware tap gestures are legitimate uses of `.onTapGesture` that cannot be replaced by `Button`. However, these gestures are invisible to VoiceOver unless the view also declares `.accessibilityAddTraits(.isButton)` or `.accessibilityLabel()`. Without accessibility annotations, assistive technology users have no way to discover or invoke the gesture.

### Discussion
This rule complements the `onTapGesture Instead of Button` rule. That rule flags simple `.onTapGesture { }` calls that should be `Button`. This rule handles the allowed exceptions — multi-tap and location-aware gestures — by verifying that they have at least one accessibility annotation (`.accessibilityAddTraits` or `.accessibilityLabel`) in the modifier chain.

The rule walks the SwiftUI modifier chain from the `.onTapGesture` call upward, looking for either modifier. If neither is found, it reports an info-level issue.

### Non-Violating Examples
```swift
// Double-tap with accessibility traits and label
Canvas { context, size in }
    .onTapGesture(count: 2) { resetZoom() }
    .accessibilityAddTraits(.isButton)
    .accessibilityLabel("Diagram canvas")
    .accessibilityHint("Double-tap to reset zoom")

// Location-aware tap with accessibility label
Image("map")
    .onTapGesture { location in
        placePin(at: location)
    }
    .accessibilityLabel("Map view")
```

### Violating Examples
```swift
// Double-tap with no accessibility — invisible to VoiceOver
Canvas { context, size in }
    .onTapGesture(count: 2) { resetZoom() }

// Location-aware tap with no accessibility
Text("Tap here")
    .onTapGesture { location in
        handleTap(at: location)
    }
```

---
