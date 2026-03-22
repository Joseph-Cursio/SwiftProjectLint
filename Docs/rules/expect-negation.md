[← Back to Rules](RULES.md)

## Expect Negation

**Identifier:** `Expect Negation`
**Category:** Code Quality
**Severity:** Warning

### Rationale
`#expect(!expression)` negates inside the macro. When the assertion fails, Swift Testing's expression decomposition handles unary `!` differently from binary operators like `==`: it cannot evaluate the inner sub-expression and shows it as `<not evaluated>`, giving you no diagnostic context about what went wrong.

`#expect(expression == false)` captures both sides of the binary comparison, so the failure message shows what `expression` actually evaluated to.

This was originally observed by Paul Hudson (Hacking with Swift) and has been verified against **Swift 6.3 / Xcode 26.4 beta** — the behaviour is unchanged in the latest toolchain.

### Verified Failure Output (Swift 6.3 / Xcode 26.4 beta)

Plain boolean — negation form loses the value entirely:
```swift
let flag = true
#expect(!flag)
// Expectation failed: !(flag → <not evaluated>)

#expect(flag == false)
// Expectation failed: (flag → true) == false
```

Chained call — negation form produces a confusing triple-arrow chain:
```swift
let empty: [Int] = []
#expect(!empty.isEmpty)
// Expectation failed: !((empty → []).isEmpty → true → true)

#expect(empty.isEmpty == false)
// Expectation failed: (empty.isEmpty → true) == false
```

The `== false` form is consistently cleaner and immediately shows the actual value.

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
