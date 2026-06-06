[← Back to Rules](RULES.md)

## Control Missing Accessibility Label

**Identifier:** `Control Missing Accessibility Label`
**Category:** Accessibility
**Severity:** Warning

### Rationale
An interactive control built with an **empty string label** — `Toggle("", isOn:)`, `Button("", action:)` — is visible and tappable but exposes no accessible name. VoiceOver announces it as just "checkbox" / "button" with no indication of what it does. This commonly happens with `Toggle("", …).labelsHidden()`, where the developer hides the label visually (because a neighbouring `Text` shows it) but leaves nothing for assistive technology, since adjacent text is not programmatically tied to the control.

This is distinct from [Icon-Only Button Missing Label](icon-only-button-missing-label.md): there the label argument is *absent* (a `Button { Image(...) }`); here it is *present but empty*.

### Discussion
`ControlMissingAccessibilityLabelVisitor` flags a `Toggle` or `Button` whose first positional argument is an empty string literal, unless a `.accessibilityLabel(…)` modifier is applied to the control's modifier chain (checked by walking up from the control). Non-empty labels and the closure-label form are left alone.

The fix is to pass the real label and hide it visually rather than blanking it: `Toggle(name, isOn:).labelsHidden()` keeps the exact same layout while giving VoiceOver a name. Or add `.accessibilityLabel("…")`.

### Non-Violating Examples
```swift
Toggle("Bold", isOn: $isBold)                       // real label

Toggle(rule.name, isOn: $isEnabled).labelsHidden()  // label set, hidden visually

Toggle("", isOn: $isEnabled)
    .accessibilityLabel("Enable rule")              // compensating modifier
```

### Violating Examples
```swift
Toggle("", isOn: $isEnabled)
    .labelsHidden()                                 // unlabeled checkbox for VoiceOver

Button("", action: save)                            // unlabeled button
```

---
