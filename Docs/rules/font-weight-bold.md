[<- Back to Rules](RULES.md)

## Font Weight Bold

**Identifier:** `Font Weight Bold`
**Category:** Code Quality
**Severity:** Info

### Rationale
`.fontWeight(.bold)` has a shorter equivalent: `.bold()`. The shorthand is more readable and idiomatic Swift. Other font weights (`.semibold`, `.heavy`, etc.) have no shorthand and are not flagged.

### Discussion
`FontWeightBoldVisitor` inspects `FunctionCallExprSyntax` nodes for `.fontWeight` member accesses where the single argument is `.bold`. Only the `.bold` case is flagged since it is the only weight with a dedicated modifier.

### Non-Violating Examples
```swift
// Shorthand — correct
Text("Hello").bold()

// Other weights — no shorthand available
Text("Hello").fontWeight(.semibold)
Text("Hello").fontWeight(.heavy)
Text("Hello").fontWeight(.light)
```

### Violating Examples
```swift
// Has a shorter equivalent
Text("Hello").fontWeight(.bold)
```

---
