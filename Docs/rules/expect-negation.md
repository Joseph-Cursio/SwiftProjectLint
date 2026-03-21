[← Back to Rules](RULES.md)

## Expect Negation

**Identifier:** `Expect Negation`
**Category:** Code Quality
**Severity:** Warning

### Rationale
`#expect(!expression)` negates inside the macro. When the assertion fails, Swift Testing captures the result of the `!` operator — which is simply `false` — rather than the value of `expression` itself. This produces an unhelpful failure message with no diagnostic context.

`#expect(expression == false)` captures both sides of the comparison, so the test report shows what `expression` actually evaluated to.

### Failure Output Comparison

With negation (poor diagnostics):
```
◇ Test failed
↳ #expect(!items.isEmpty)
  → false
```

With explicit comparison (rich diagnostics):
```
◇ Test failed
↳ #expect(items.isEmpty == false)
  → items.isEmpty → true ≠ false
```

### Scope
- Flags `#expect(!expr)` — prefix `!` negation as the first argument
- Does not flag `#expect(expr == false)` — the recommended alternative
- Does not flag positive assertions like `#expect(isVisible)`
- Does not flag negation outside `#expect` (e.g., in `if` conditions or variable bindings)

### Known Limitation
`#require(!expr)` has the same diagnostics problem but is not currently flagged by this rule.

### Non-Violating Examples
```swift
#expect(isVisible == false)      // explicit comparison — full diagnostic context
#expect(items.isEmpty == false)
#expect(isVisible)               // positive assertion — fine
#expect(count == 3)
```

### Violating Examples
```swift
#expect(!isVisible)              // negation defeats sub-expression capture
#expect(!items.isEmpty)
```

---
