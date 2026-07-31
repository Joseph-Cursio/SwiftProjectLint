# Accessibility Rule Proposals

Potential lint rules derived from [mobilea11y.com SwiftUI accessibility guides](https://mobilea11y.com/guides/swiftui/swiftui-accessibility/).

> **Status (2026-07-31): closed.** Every candidate is resolved — all six shipped,
> and the seven Deferred items below are decisions not to build rather than
> pending work. Kept as the record of what was proposed, what shipped, and where
> each rule departed from its proposal. The shipped rules are documented in
> [`rules/RULES.md`](../rules/RULES.md); read those for current behaviour, and
> this only for intent.
>
> | # | Proposal | Shipped as |
> |---|---|---|
> | 1 | Accessibility Hidden With Other Modifiers | `accessibilityHiddenConflict` |
> | 2 | Sort Priority Without Container | `sortPriorityWithoutContainer` |
> | 3 | Animation Without Reduce Motion | `animationWithoutReduceMotion` (opt-in) |
> | 4 | Custom Font With Fixed Size | folded into `hardcodedFontSize` |
> | 5 | isButton Trait Without Action | `isButtonTraitWithoutAction` |
> | 6 | Unlabeled Toggle, Slider, or Picker | folded into `controlMissingAccessibilityLabel`, with the absent-label half split out as `unlabeledControl` |

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

### 3. ~~Animation Without Reduce Motion Check~~ -- Implemented (`animationWithoutReduceMotion`)

Shipped **opt-in** rather than merely Info-severity. The proposal treated Info as
sufficient mitigation for the false-positive risk; in practice most SwiftUI views
animate and few consult Reduce Motion, so enabling it by default would bury a
codebase in findings on first run. It matches the posture of the other Info-severity
heuristic rules instead.

Detection also went slightly wider and slightly narrower than specified: `.transition`
counts as animating alongside `.animation` and `withAnimation` (the proposal's own
violating example relies on it), while `.animation(nil, …)`, `.transition(.opacity)`,
and `.transition(.identity)` are excluded because they introduce no motion.
`UIAccessibility.isReduceMotionEnabled` counts as consulting the preference, not just
the SwiftUI environment value.

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

### 4. ~~Custom Font With Fixed Size~~ -- Implemented (folded into `hardcodedFontSize`)

**Shipped as an extension of the existing rule rather than a new one**, per the
implementation note below. `HardcodedFontSizeVisitor` now accepts `.custom` alongside
`.system`, and exempts the `relativeTo:` form. No new `RuleIdentifier`: the concern,
category, and severity are identical, so disabling `hardcodedFontSize` disables both.

Note this *changed* previously-tested behaviour — a negative test asserted custom fonts
were not flagged, and `rules/hardcoded-font-size.md` justified the exemption with
"cannot use text styles". That reasoning conflated `.font(.title)` with Dynamic Type;
`relativeTo:` and `@ScaledMetric` both scale a custom face.


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

### 5. ~~isButton Trait Without Accessibility Action~~ -- Implemented (`isButtonTraitWithoutAction`)

Shipped as its own rule, with one deliberate widening of the detection below: the
chain is collected whole before either check, so modifier *order* does not matter,
and activation counts as satisfied by any of `.accessibilityAction`,
`.accessibilityCustomAction`, `.accessibilityAdjustableAction`, `.onTapGesture`,
`.onLongPressGesture`, `.gesture`, `.highPriorityGesture`, `.simultaneousGesture`.
Already-activatable views (`Button`, `NavigationLink`, `Link`, `Menu`, `Toggle`,
`Stepper`, `Picker`) are skipped, since there the trait is redundant, not broken.


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

### 6. ~~Unlabeled Toggle, Slider, or Picker~~ -- Implemented (folded into `controlMissingAccessibilityLabel`)

Shipped as an extension of the existing rule, which already handled the empty-*string*
form for `Toggle`/`Button`. The extension adds `Slider`, `Stepper`, and `Picker`, plus
the empty-*closure* form the original rule explicitly left alone.

Split deliberately from the **absent**-label case. The proposal's wording ("the label
closure is empty or the string title is empty") is about labels that are present but
blank; a control written with no label at all — `Slider(value:in:)` — is a different and
far more common shape. Folding both into one default-on Warning rule would have turned a
quiet rule noisy overnight, so the absent case is tracked as its own rule instead.

`Picker` is excluded from the closure check on purpose: its trailing closure is the
option *content*, not the label, so an empty one there means something else entirely.

The proposal's own false-positive note — controls intentionally unlabeled inside a
`.accessibilityElement(children: .combine)` group — is handled, and `.ignore` too. Since
a parent's modifier call is an ancestor of the control in the syntax tree, one upward
walk covers both the control's own chain and any enclosing container's. `.contain` does
not suppress, because it leaves children as individual elements.

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
