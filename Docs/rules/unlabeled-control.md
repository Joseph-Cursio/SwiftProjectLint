[← Back to Rules](RULES.md)

## Unlabeled Control

**Identifier:** `Unlabeled Control`
**Category:** Accessibility
**Severity:** Warning
**Opt-in:** yes — enable via `enabled_only`

### Rationale
`Slider(value: $volume, in: 0...1)` announces to VoiceOver as "50 percent, slider" — a value and a role, with nothing saying *what* it adjusts. A VoiceOver user can operate the control perfectly well and still have no idea what it does, which is worse than it sounds: the control is reachable, focusable, and adjustable, so nothing signals that anything is missing.

This is the sibling of [Control Missing Accessibility Label](control-missing-accessibility-label.md), which covers labels that are present but **empty**. The split matters because the fixes differ. There you blanked out a label you already had, and the repair is to stop blanking it. Here you never wrote one.

### Discussion
The rule's scope is genuinely narrow, and that is not an oversight.

**Most SwiftUI controls cannot be written without a label.** `Toggle`, `Stepper`, and `Picker` require either a string title or a label closure in *every* initializer, so they can only ever have an *empty* label — never an absent one. Those belong to the sibling rule. Only `Slider` and `ProgressView` ship label-less initializers, so only they can reach this one.

`UnlabeledControlVisitor` flags a `Slider` or `ProgressView` that supplies no label in any spelling — no string title, no trailing closure, no explicit `label:` — and has no compensating `.accessibilityLabel` on its chain.

The bare `ProgressView()` spinner is excluded. It is usually decorative and explained by adjacent text, so only the determinate `value:` form — the one that announces a bare number — is flagged.

As with the sibling rule, an ancestor applying `.accessibilityElement(children: .combine)` or `.ignore` suppresses the finding, because the parent then supplies the accessible name. `.contain` does not suppress: it keeps children as individual elements, so an unlabeled one stays unlabeled.

**Why opt-in:** `Slider(value:in:)` is the ordinary way people write a slider, so a default-on rule would fire across most codebases at once. Severity is Warning rather than Info because, once you have chosen to look for this, an unlabeled slider is a real defect rather than a matter of taste.

### Non-Violating Examples
```swift
// Label closure
Slider(value: $volume, in: 0...1) { Text("Volume") }

// Compensating modifier
Slider(value: $volume, in: 0...1)
    .accessibilityLabel("Volume")

// Titled progress
ProgressView("Uploading", value: progress, total: 1.0)

// Indeterminate spinner — decorative, explained by nearby text
ProgressView()

// Parent supplies the name
HStack {
    Text("Volume")
    Slider(value: $volume, in: 0...1)
}
.accessibilityElement(children: .combine)
```

### Violating Examples
```swift
// "50 percent, slider" — of what?
Slider(value: $volume, in: 0...1)

// Announces a bare number with no context
ProgressView(value: progress, total: 1.0)
```

---
