[← Back to Rules](RULES.md)

## Navigation Button Should Be Link

**Identifier:** `Navigation Button Should Be Link`
**Category:** Accessibility
**Severity:** Warning

### Rationale

A `Button` containing a trailing `chevron.right` or `chevron.forward` icon visually signals "this navigates somewhere" — but VoiceOver announces it as a generic **Button**. Blind users rely on VoiceOver's element type announcement to understand interaction intent. When a button looks like a navigation link to sighted users but is announced as a button to VoiceOver users, those users receive a misleading interface description.

`NavigationLink` announces itself as a **Link**, which is the correct semantic type for navigating to another screen. When `NavigationLink` isn't suitable (e.g. programmatic navigation, non-standard transitions), adding `.accessibilityAddTraits(.isLink)` achieves the same VoiceOver announcement.

### Discussion

`ButtonAccessibilityChecker` fires this rule when:
- A `FunctionCallExprSyntax` for `Button` is found
- Its subtree contains `Image(systemName: "chevron.right")` or `Image(systemName: "chevron.forward")`
- The button does **not** already have `.accessibilityAddTraits` in its modifier chain (checked both upward through the chained modifier chain and downward into the label closure)

The chevron is the signal. `chevron.down` and `chevron.up` are used for expand/collapse and are not flagged. Only the directional `chevron.right` / `chevron.forward` — the conventional "navigate forward" indicator — triggers this rule.

### Non-Violating Examples

```swift
// NavigationLink — correct semantic element
NavigationLink(destination: RuleDetailView(rule: rule)) {
    HStack {
        Text(rule.name)
        Spacer()
        Image(systemName: "chevron.right")
            .accessibilityHidden(true)
    }
}

// Button with explicit link trait
Button {
    navigateToDetail(rule)
} label: {
    HStack {
        Text(rule.name)
        Spacer()
        Image(systemName: "chevron.right")
            .accessibilityHidden(true)
    }
}
.accessibilityAddTraits(.isLink)

// Expand/collapse chevron — not flagged (chevron.down, not chevron.right)
Button {
    isExpanded.toggle()
} label: {
    Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
}
```

### Violating Examples

```swift
// Button looks like navigation but VoiceOver says "Button"
Button {
    // navigate to detail
} label: {
    HStack {
        Text(rule.name)
        Spacer()
        Image(systemName: "chevron.right")
            .accessibilityHidden(true)
    }
}
.buttonStyle(.plain)
```

### Fix

Prefer `NavigationLink` when navigating within a `NavigationStack`:

```swift
NavigationLink(value: rule) {
    HStack {
        Text(rule.name)
        Spacer()
        Image(systemName: "chevron.right")
            .accessibilityHidden(true)
    }
}
```

When programmatic navigation is required, add the link trait:

```swift
Button { navigateTo(rule) } label: { ... }
    .accessibilityAddTraits(.isLink)
```

### See Also
- [Icon-Only Button Missing Label](icon-only-button-missing-label.md) — detects buttons where a missing label makes the element invisible to VoiceOver
- [Missing Accessibility Hint](missing-accessibility-hint.md) — suggests hints for text buttons whose outcome isn't obvious

---
