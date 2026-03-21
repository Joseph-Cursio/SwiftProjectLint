[← Back to Rules](RULES.md)

## Force Unwrap

**Identifier:** `Force Unwrap`
**Category:** Code Quality
**Severity:** Info

### Rationale
Force unwrapping an optional with `!` will crash at runtime if the value is nil. Prefer safe alternatives like `if-let`, `guard-let`, or the nil-coalescing operator (`??`).

### Discussion
`ForceUnwrapVisitor` detects `ForceUnwrapExprSyntax` nodes in the AST. This specifically targets runtime force unwraps (e.g., `value!`), not implicitly unwrapped optional declarations (e.g., `var x: String!`).

```swift
// Before
let name = user.name!
let first = array.first!

// After
guard let name = user.name else { return }
let first = array.first ?? "default"
```

### Non-Violating Examples
```swift
// Implicitly unwrapped optional declaration
let value: String! = "hello"

// Optional chaining
let name = user?.name

// Nil coalescing
let value = optional ?? "default"
```

### Violating Examples
```swift
// Force unwrap — crashes on nil
let value = optional!
let name = foo.bar!.baz
```

---
