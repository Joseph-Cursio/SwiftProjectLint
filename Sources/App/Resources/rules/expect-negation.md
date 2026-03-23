[← Back to Rules](RULES.md)

## Expect Negation

**Identifier:** `Expect Negation`
**Category:** Code Quality
**Severity:** Warning

### Rationale
`#expect(!expression)` negates inside the macro. When the assertion fails, Swift Testing captures the value of the negated prefix operator (`!`) — which is simply `false` — rather than the value of `expression`. This produces an unhelpful failure message. `#expect(expression == false)` captures `expression`'s actual value and displays it in the test report.

### Discussion
`ExpectNegationVisitor` identifies `MacroExpansionExprSyntax` nodes where the macro name is `expect` and the first unlabeled argument is a `PrefixOperatorExprSyntax` with operator text `!`. It does not flag `#require(!expr)` because `#require` is a different macro. Negation outside of a `#expect` call (in `if` conditions, `let` bindings, etc.) is also not flagged.

### Non-Violating Examples
```swift
#expect(isVisible == false)   // explicit comparison — full diagnostic context
#expect(items.isEmpty == false)
#expect(isVisible)            // positive assertion — fine
#expect(count == 3)
```

### Violating Examples
```swift
#expect(!isVisible)       // negation defeats sub-expression capture
#expect(!items.isEmpty)   // negation inside expect
```

---
