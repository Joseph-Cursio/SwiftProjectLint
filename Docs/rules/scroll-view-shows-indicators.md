[<- Back to Rules](RULES.md)

## ScrollView showsIndicators

**Identifier:** `ScrollView showsIndicators`
**Category:** Modernization
**Severity:** Info

### Rationale
The `ScrollView(showsIndicators:)` initializer parameter was the old way to control scroll indicators. The `.scrollIndicators(.hidden)` modifier is the iOS 16+ replacement and is more composable — it can be applied to any scrollable view without being coupled to the initializer.

### Discussion
`ScrollViewShowsIndicatorsVisitor` inspects `FunctionCallExprSyntax` nodes where the callee is `ScrollView` and any argument has the label `showsIndicators`.

Note: `.scrollIndicators()` requires iOS 16+ / macOS 13+.

### Non-Violating Examples
```swift
// Modern modifier (iOS 16+)
ScrollView(.vertical) {
    content
}
.scrollIndicators(.hidden)

// No indicator control — fine
ScrollView {
    content
}
```

### Violating Examples
```swift
// Legacy initializer parameter
ScrollView(.vertical, showsIndicators: false) {
    content
}

ScrollView(showsIndicators: true) {
    content
}
```

---
