[← Back to Rules](RULES.md)

## isButton Trait Without Action

**Identifier:** `isButton Trait Without Action`
**Category:** Accessibility
**Severity:** Warning

### Rationale
`.accessibilityAddTraits(.isButton)` is a promise about behaviour, not a label. It tells VoiceOver "this element is a button", and VoiceOver acts on that: it announces the element as a button and offers the activate gesture. If nothing in the chain handles activation, the double-tap reaches nothing.

That failure is invisible to a sighted tester — the view still looks right and still responds to a real tap if a gesture is attached elsewhere — so it tends to survive review. The trait is the only thing that makes the element *appear* interactive to assistive technology, and it is the one thing that cannot, by itself, make it *be* interactive.

This rule is the counterpart to [onTapGesture Instead of Button](on-tap-gesture-instead-of-button.md), which recommends adding `.accessibilityAddTraits(.isButton)`. Following that advice without also supplying an action produces exactly the state flagged here.

### Discussion
`IsButtonTraitWithoutActionVisitor` anchors on the root view of a modifier chain, collects the whole chain, and flags it when `.accessibilityAddTraits` adds `.isButton` — bare or inside a trait array — and no modifier supplies an activation path. Because the entire chain is gathered before either check, the order of the modifiers does not matter.

Activation is considered satisfied by `.accessibilityAction`, `.accessibilityCustomAction`, `.accessibilityAdjustableAction`, `.onTapGesture`, `.onLongPressGesture`, `.gesture`, `.highPriorityGesture`, or `.simultaneousGesture`.

Views that already carry an action — `Button`, `NavigationLink`, `Link`, `Menu`, `Toggle`, `Stepper`, `Picker` — are skipped entirely. Adding `.isButton` to those is redundant rather than broken, which is not worth a warning.

**Known limitation:** activation inherited from an ancestor view, or supplied by a gesture attached further up the hierarchy, is not visible from the chain this rule inspects. Those cases report a false positive. Suppress them with `// swiftprojectlint:disable:next isButton Trait Without Action`.

### Non-Violating Examples
```swift
// Explicit accessibility action
HStack {
    Text("Mars")
    Image(systemName: "heart")
}
.accessibilityElement(children: .ignore)
.accessibilityAddTraits(.isButton)
.accessibilityAction { tappedLike() }

// A tap gesture the activate gesture can reach
HStack { Text("Mars") }
    .accessibilityAddTraits(.isButton)
    .onTapGesture { tappedLike() }

// Already a Button — trait is redundant, not broken
Button("Mars") { tappedLike() }
    .accessibilityAddTraits(.isButton)

// A different trait entirely
Text("Mars")
    .accessibilityAddTraits(.isHeader)
```

### Violating Examples
```swift
// Announced as a button, but the activate gesture reaches nothing
HStack {
    Text("Mars")
    Image(systemName: "heart")
}
.accessibilityElement(children: .ignore)
.accessibilityAddTraits(.isButton)

// Same problem, trait supplied inside an array
VStack { Text("Mars") }
    .accessibilityAddTraits([.isButton, .isSelected])
```

---
