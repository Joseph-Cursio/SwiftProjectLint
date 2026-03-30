[← Back to Rules](RULES.md)

## ViewBuilder Complexity

**Identifier:** `ViewBuilder Complexity`
**Category:** Performance
**Severity:** Warning

### Rationale
`@ViewBuilder` functions and computed properties that grow beyond 30 lines or 15 statements become difficult to read and may hide unnecessary re-computation. Large builders should be split into smaller subviews or helper functions for clarity and performance.

### Discussion
`ViewBuilderComplexityVisitor` checks every function or computed property annotated with `@ViewBuilder`. It counts both the number of source lines and the number of top-level statements in the body. If either exceeds its threshold (30 lines or 15 statements), the rule fires.

The standard `body` property is excluded because it is already covered by the existing `largeViewBody` rule. This rule complements that one by targeting auxiliary `@ViewBuilder` helpers that can accumulate complexity outside the main body.

### Non-Violating Examples
```swift
@ViewBuilder
func header() -> some View {
    Text("Title")
    Image(systemName: "star")
    Divider()
}
```

### Violating Examples
```swift
@ViewBuilder
func massiveBuilder() -> some View {
    // 30+ lines of nested VStacks, HStacks, conditionals...
    Text("Line 1")
    Text("Line 2")
    // ... 28 more lines
}
```

---
