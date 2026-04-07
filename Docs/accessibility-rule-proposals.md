# Accessibility Rule Proposals

Potential lint rules derived from [mobilea11y.com SwiftUI accessibility guides](https://mobilea11y.com/guides/swiftui/swiftui-accessibility/).

---

## Strong Candidates

### 1. ~~Accessibility Hidden With Other Accessibility Modifiers~~ -- Implemented (`accessibilityHiddenConflict`)

**Source:** [Semantic Views](https://mobilea11y.com/guides/swiftui/swiftui-semantic-views/)

**Problem:** Applying `.accessibilityHidden(true)` alongside other accessibility modifiers (`.accessibilityLabel()`, `.accessibilityHint()`, `.accessibilityValue()`, `.accessibilityAddTraits()`) is contradictory. The hidden modifier removes the element from the accessibility tree entirely, making the other attributes unreachable. The article calls this "pointless."

**Detection:** Find a modifier chain containing `accessibilityHidden` plus any other accessibility modifier on the same node.

**Severity:** Warning

**Example (violating):**
```swift
HStack { /* ... */ }
    .accessibilityHidden(true)
    .accessibilityLabel("Custom label")
```

**Example (non-violating):**
```swift
// Hidden only — correct
HStack { /* ... */ }
    .accessibilityHidden(true)

// Use .ignore instead to replace child semantics
HStack { /* ... */ }
    .accessibilityElement(children: .ignore)
    .accessibilityLabel("Custom label")
```

**False-positive risk:** Very low. This combination is always a mistake.

---

### 2. ~~Sort Priority Without Accessibility Container~~ -- Implemented (`sortPriorityWithoutContainer`)

**Source:** [Sort Priority](https://mobilea11y.com/guides/swiftui/swiftui-sort-priority/)

**Problem:** `.accessibilitySortPriority()` on children inside a stack has no effect unless the parent stack has `.accessibilityElement(children: .contain)`. Developers add sort priorities expecting custom VoiceOver navigation order, but VoiceOver silently ignores them without the container modifier.

**Detection:** Find `accessibilitySortPriority` calls and check whether an ancestor stack node has `accessibilityElement` in its modifier chain. This requires walking up the syntax tree from the sort priority call.

**Severity:** Warning

**Example (violating):**
```swift
VStack {
    Text("Read this last").accessibilitySortPriority(0)
    Text("Read this first").accessibilitySortPriority(2)
}
// Missing .accessibilityElement(children: .contain) on VStack
```

**Example (non-violating):**
```swift
VStack {
    Text("Read this last").accessibilitySortPriority(0)
    Text("Read this first").accessibilitySortPriority(2)
}
.accessibilityElement(children: .contain)
```

**False-positive risk:** Low. Sort priority without a container is always ineffective.

---

### 3. Animation Without Reduce Motion Check

**Source:** [User Settings](https://mobilea11y.com/guides/swiftui/swiftui-settings/)

**Problem:** Views using `.animation()` or `withAnimation` without checking `@Environment(\.accessibilityReduceMotion)` anywhere in the same struct ignore the user's motion preferences. Users with vestibular disorders or motion sensitivity enable Reduce Motion specifically to avoid animations that cause discomfort.

**Detection:** Find structs containing `.animation()` or `withAnimation` calls that do not reference `accessibilityReduceMotion` anywhere in the struct body. This is a struct-level check, not a per-call check.

**Severity:** Info

**Example (violating):**
```swift
struct MyView: View {
    @State private var isLoading = false
    var body: some View {
        Text("Loading")
            .transition(.scale)
            .animation(.easeInOut, value: isLoading)
    }
}
```

**Example (non-violating):**
```swift
struct MyView: View {
    @Environment(\.accessibilityReduceMotion) var reduceMotion
    @State private var isLoading = false
    var body: some View {
        Text("Loading")
            .transition(reduceMotion ? .identity : .scale)
            .animation(reduceMotion ? nil : .easeInOut, value: isLoading)
    }
}
```

**False-positive risk:** Moderate. Some animations (opacity fades, color changes) are not motion-sensitive. Struct-level detection avoids per-call noise but may still flag harmless cases. Info severity is appropriate.

---

### 4. Custom Font With Fixed Size

**Source:** [Dynamic Type](https://mobilea11y.com/guides/swiftui/swiftui-dynamic-type/)

**Problem:** `.font(.custom("FontName", size: 17))` with a literal numeric size bypasses Dynamic Type. Unlike the existing `hardcodedFontSize` rule (which catches `.font(.system(size:))`), this targets custom fonts. The dynamic type page calls ignoring user font preferences "arrogant."

**Detection:** Find `.font(.custom(_, size:))` calls where the `size:` argument is a numeric literal.

**Severity:** Warning

**Example (violating):**
```swift
Text("Hello")
    .font(.custom("Helvetica", size: 17))
```

**Example (non-violating):**
```swift
// Using @ScaledMetric
@ScaledMetric var fontSize: CGFloat = 17
Text("Hello")
    .font(.custom("Helvetica", size: fontSize))

// Using relativeTo: for automatic scaling
Text("Hello")
    .font(.custom("Helvetica", size: 17, relativeTo: .body))
```

**False-positive risk:** Low. Literal sizes in custom fonts are always non-scaling. Note: `.custom(_:size:relativeTo:)` should NOT be flagged since it scales with Dynamic Type.

**Implementation note:** Consider extending the existing `HardcodedFontSizeVisitor` rather than creating a new visitor.

---

## Moderate Candidates

### 5. isButton Trait Without Accessibility Action

**Source:** [Semantic Views](https://mobilea11y.com/guides/swiftui/swiftui-semantic-views/)

**Problem:** A view with `.accessibilityAddTraits(.isButton)` that lacks `.accessibilityAction` declares itself as interactive but provides no way for assistive technology users to activate it.

**Detection:** Find modifier chains containing `accessibilityAddTraits` with `.isButton` that lack `accessibilityAction` in the same chain.

**Severity:** Warning

**Example (violating):**
```swift
HStack {
    Text("Mars")
    Image(systemName: "heart")
}
.accessibilityElement(children: .ignore)
.accessibilityAddTraits(.isButton)
// No .accessibilityAction — VoiceOver users can't tap it
```

**Example (non-violating):**
```swift
HStack {
    Text("Mars")
    Image(systemName: "heart")
}
.accessibilityElement(children: .ignore)
.accessibilityAddTraits(.isButton)
.accessibilityAction { tappedLike() }
```

**False-positive risk:** Low-moderate. Some views inherit tap handling from parent views or gesture recognizers that the AST can't see.

---

### 6. Unlabeled Toggle, Slider, or Picker

**Source:** [Named Controls](https://mobilea11y.com/guides/swiftui/swiftui-controls/)

**Problem:** Controls like `Toggle(isOn:)` without a label are invisible to VoiceOver and Voice Control. Users hear "Toggle. Off." with no indication of what they're toggling. Voice Control users must use numeric grid overlays instead of speaking the control name.

**Detection:** Find `Toggle`, `Slider`, `Stepper`, or `Picker` initializers where the label closure is empty or the string title is empty, and no `.accessibilityLabel()` modifier is present.

**Severity:** Warning

**Example (violating):**
```swift
Toggle(isOn: $updates) {
    // Empty label
}

Toggle("", isOn: $updates)
```

**Example (non-violating):**
```swift
Toggle(isOn: $updates) {
    Text("Send me updates")
}

Toggle("Send me updates", isOn: $updates)

// Labeled externally
Toggle(isOn: $updates) { EmptyView() }
    .accessibilityLabel("Send me updates")
```

**False-positive risk:** Moderate. Some controls are intentionally unlabeled when grouped with external labels via `.accessibilityElement(children: .combine)` on a parent. Would need to check for that.

---

## Deferred (too heuristic-heavy for reliable AST detection)

- **Image with non-descriptive filename** — Cannot determine "meaningfulness" of asset names statically.
- **Color-only state indicators** — Requires understanding semantic intent of color choices.
- **Separate accessibility UI branches** — Would false-positive on legitimate `if reduceMotion` checks.
- **Auto-play video without check** — `isVideoAutoplayEnabled` is too niche and rarely used.
- **Redundant hint content** — Comparing label and hint strings for semantic overlap is unreliable.
- **Over-long accessibility labels** — Length thresholds are arbitrary and context-dependent.
- **Custom font size fixed until redraw** — Runtime behavior, not detectable via AST.
