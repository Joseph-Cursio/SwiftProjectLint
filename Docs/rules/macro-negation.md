[← Back to Rules](RULES.md)

## Macro Negation

**Identifier:** `Macro Negation`
**Category:** Code Quality
**Severity:** Warning

### Rationale
`#expect(!expression)` and `#require(!expression)` negate inside the macro. When the assertion fails, Swift Testing's expression decomposition handles unary `!` differently from binary operators like `==`: it cannot evaluate the inner sub-expression and shows it as `<not evaluated>`, giving you no diagnostic context about what went wrong.

`#expect(expression == false)` and `#require(expression == false)` capture both sides of the binary comparison, so the failure message shows what `expression` actually evaluated to.

This was originally observed by Paul Hudson (Hacking with Swift) and has been verified against **Swift 6.3 / Xcode 26.4** (stable, Testing 6.2.4) and **swift-testing `main`** (6.4-dev) — the underlying limitation is unchanged in both.

### Verified Failure Output (Swift 6.3 / Xcode 26.4, Testing 6.2.4)

| Form | Failure output |
|------|----------------|
| `#expect(!flag)` | `!(flag → <not evaluated>)` |
| `#expect(flag == false)` | `(flag → true) == false` |
| `#expect(!empty.isEmpty)` | `!((empty → []).isEmpty → true → true)` |
| `#expect(empty.isEmpty == false)` | `(empty.isEmpty → true) == false` |

The negation form loses the sub-expression value (`<not evaluated>`) or produces a confusing multi-arrow chain. The `== false` form always shows the actual value.

### Verified Failure Output (swift-testing `main`, 6.4-dev)

The tree-format diagnostic in the upcoming release makes the same limitation even more visible:

```
Expectation failed: !flag
↳ !flag → <not evaluated>
↳   flag → <not evaluated>

Expectation failed: flag == false
↳ flag == false → false
↳   flag → true
```

Under `!`, the inner operand is still `<not evaluated>`; under `== false`, you get the real value.

The same applies to `#require`.

### Scope
- Flags `#expect(!expr)` and `#require(!expr)` — prefix `!` negation as the first argument
- Does not flag `#expect(expr == false)` or `#require(expr == false)` — the recommended alternative
- Does not flag positive assertions like `#expect(isVisible)`
- Does not flag negation outside these macros (e.g., in `if` conditions or variable bindings)

### Non-Violating Examples
```swift
#expect(isVisible == false)      // explicit comparison — full diagnostic context
#expect(items.isEmpty == false)
#require(value == false)
#expect(isVisible)               // positive assertion — fine
#expect(count == 3)
```

### Violating Examples
```swift
#expect(!isVisible)              // negation defeats sub-expression capture
#expect(!items.isEmpty)
#require(!isVisible)             // same problem in #require
#require(!items.isEmpty)
```

---
