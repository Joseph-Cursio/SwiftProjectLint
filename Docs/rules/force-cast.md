[← Back to Rules](RULES.md)

## Force Cast

**Identifier:** `Force Cast`
**Category:** Code Quality
**Severity:** Warning

### Rationale
`as!` traps when the value is not of the target type. Like `try!` and force unwrap, the trap is a fatal signal rather than an error, so nothing can catch it: a property test that draws one unlucky input loses the trial, the shrink, and every property queued behind it in the same process. `as?` is the same operator with the failure returned instead of raised.

### Discussion
`ForceCastVisitor` handles both node kinds a cast can take. `AsExprSyntax` is the folded form; `UnresolvedAsExprSyntax` is what SwiftParser leaves inside a `SequenceExprSyntax` when the operator sequence has not been resolved. A visitor handling only the first would miss every `as!` written in an ordinary expression. Plain `as` and `as?` carry a different `questionOrExclamationMark` and are not flagged.

```swift
// Before
func label(from value: Any) -> String {
    value as! String
}

// After
func label(from value: Any) -> String? {
    value as? String
}
```

### Non-Violating Examples
```swift
// Conditional cast — returns nil rather than trapping
let name = value as? String

// Widening cast — cannot fail
let anything = number as Any
```

### Violating Examples
```swift
// Force cast — traps on a type mismatch
let name = value as! String
let controller = segue.destination as! DetailViewController
```

---
