[<- Back to Rules](RULES.md)

## Sort Priority Without Container

**Identifier:** `Sort Priority Without Container`
**Category:** Accessibility
**Severity:** Warning

### Rationale
`.accessibilitySortPriority()` customizes the order in which VoiceOver navigates child elements. However, this modifier only takes effect when the parent stack has `.accessibilityElement(children: .contain)`. Without the container modifier, VoiceOver silently ignores the custom sort priorities and uses its default navigation order. This is a common source of confusion because the code compiles and runs without error, but the accessibility behavior is not what the developer intended.

### Scope
- Flags `.accessibilitySortPriority()` calls on views inside a `VStack`, `HStack`, `ZStack`, `LazyVStack`, or `LazyHStack` that lacks `.accessibilityElement(children:)` in its modifier chain
- Walks up the syntax tree to find the nearest enclosing stack
- Does **not** flag sort priorities inside stacks that already have `.accessibilityElement(children:)`

### Non-Violating Examples
```swift
// Sort priority with required container modifier
VStack {
    Text("Read this last").accessibilitySortPriority(0)
    Text("Read this first").accessibilitySortPriority(2)
}
.accessibilityElement(children: .contain)
```

### Violating Examples
```swift
// Sort priority without container -- VoiceOver ignores the priorities
VStack {
    Text("Read this last").accessibilitySortPriority(0)
    Text("Read this first").accessibilitySortPriority(2)
}

// Same issue with HStack
HStack {
    Text("Second").accessibilitySortPriority(1)
    Text("First").accessibilitySortPriority(2)
}
```

---
