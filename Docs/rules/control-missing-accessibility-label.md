[← Back to Rules](RULES.md)

## Control Missing Accessibility Label

**Identifier:** `Control Missing Accessibility Label`
**Category:** Accessibility
**Severity:** Warning

### Rationale
An interactive control built with an **empty string label** — `Toggle("", isOn:)`, `Button("", action:)` — is visible and tappable but exposes no accessible name. VoiceOver announces it as just "checkbox" / "button" with no indication of what it does. This commonly happens with `Toggle("", …).labelsHidden()`, where the developer hides the label visually (because a neighbouring `Text` shows it) but leaves nothing for assistive technology, since adjacent text is not programmatically tied to the control.

This is distinct from [Icon-Only Button Missing Label](icon-only-button-missing-label.md): there the label argument is *absent* (a `Button { Image(...) }`); here it is *present but empty*.

The same distinction bounds this rule generally: it is about labels that are **present but empty**. A control written with no label at all — `Slider(value:in:)` — is a different and far more common shape, and is not flagged here.

### Discussion
`ControlMissingAccessibilityLabelVisitor` covers `Toggle`, `Button`, `Slider`, `Stepper`, and `Picker`, and recognises two shapes of empty label:

- **An empty string title** — `Toggle("", isOn:)`, `Picker("", selection:)`
- **An empty label closure** — `Toggle(isOn:) { }`, or one whose only content is `EmptyView()`

`Picker` is deliberately excluded from the closure check. Its trailing closure is the *content* — the list of options — not the label, so an empty one there means something else entirely and is not this rule's business. Its label is the string title or an explicit `label:` argument.

The rule stays quiet when a `.accessibilityLabel(…)` modifier is applied to the control's chain, and when an ancestor applies `.accessibilityElement(children: .combine)` or `.ignore`: those hand naming to the parent, so an unlabeled child is harmless. `.contain` does **not** suppress, because it keeps children as individual elements, leaving an unlabeled one still unlabeled.

Because a parent's modifier call is an ancestor of the control in the syntax tree, one upward walk covers both the control's own chain and any enclosing container's.

The fix is to pass the real label and hide it visually rather than blanking it: `Toggle(name, isOn:).labelsHidden()` keeps the exact same layout while giving VoiceOver a name. Or add `.accessibilityLabel("…")`.

### Non-Violating Examples
```swift
Toggle("Bold", isOn: $isBold)                       // real label

Toggle(rule.name, isOn: $isEnabled).labelsHidden()  // label set, hidden visually

Toggle("", isOn: $isEnabled)
    .accessibilityLabel("Enable rule")              // compensating modifier

Picker("Theme", selection: $theme) {                // trailing closure is content,
    Text("Light").tag(0)                            // not a label
    Text("Dark").tag(1)
}

Slider(value: $volume, in: 0...1)                   // label absent, not empty

HStack {
    Text("Bold")
    Toggle("", isOn: $isBold).labelsHidden()        // parent names the group
}
.accessibilityElement(children: .combine)
```

### Violating Examples
```swift
Toggle("", isOn: $isEnabled)
    .labelsHidden()                                 // unlabeled checkbox for VoiceOver

Button("", action: save)                            // unlabeled button

Toggle(isOn: $isEnabled) { }                        // empty label closure

Slider(value: $volume, in: 0...1) { EmptyView() }   // renders nothing

Stepper("", value: $count)                          // unlabeled stepper
```

---
