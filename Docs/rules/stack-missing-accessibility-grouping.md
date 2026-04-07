[<- Back to Rules](RULES.md)

## Stack Missing Accessibility Grouping

**Identifier:** `Stack Missing Accessibility Grouping`
**Category:** Accessibility
**Severity:** Info

### Rationale
When a `VStack` or `HStack` contains a label–value pair of `Text` views without `.accessibilityElement(children:)`, VoiceOver reads each `Text` as a separate element. This strips context from the data — for example, "Temperature" and "72F" are announced individually instead of together, making the value meaningless without its label.

Adding `.accessibilityElement(children: .combine)` merges the child elements into a single VoiceOver announcement, preserving the label–value relationship.

### Scope
- Flags `VStack` and `HStack` views containing exactly 2 `Text` children (and no interactive elements) that lack `.accessibilityElement(children:)`
- Does **not** flag stacks with interactive elements (Button, Toggle, Slider, TextField, etc.)
- Does **not** flag stacks with more or fewer than 2 `Text` children
- Does **not** flag stacks with `.accessibilityHidden(true)`
- Does **not** flag stacks that already have `.accessibilityElement(children:)`
- Info severity reflects that this is a recommendation, not a functional bug

### Non-Violating Examples
```swift
// Stack with accessibility grouping
VStack {
    Text("Temperature")
    Text("72F")
}
.accessibilityElement(children: .combine)

// Stack with interactive element -- not a label-value pair
HStack {
    Text("Enable notifications")
    Toggle("", isOn: $enabled)
}

// Stack with only one Text
VStack {
    Text("Title")
    Image(systemName: "star")
}

// Stack hidden from VoiceOver
VStack {
    Text("Debug")
    Text("v1.2.3")
}
.accessibilityHidden(true)
```

### Violating Examples
```swift
// Label-value pair without grouping -- VoiceOver reads each Text separately
VStack {
    Text("Core temperature")
    Text("1,000,000C")
}

// Horizontal label-value pair
HStack {
    Text("Status")
    Text("Online")
}
```

---
