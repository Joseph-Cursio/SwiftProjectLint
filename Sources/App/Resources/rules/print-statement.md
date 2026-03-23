[← Back to Rules](RULES.md)

## Print Statement

**Identifier:** `Print Statement`
**Category:** Code Quality
**Severity:** Info

### Rationale
`print()` and `debugPrint()` write to standard output, which is not appropriate for production apps. Use structured logging (e.g., `os.Logger`) for diagnostics, or remove print statements before release.

### Discussion
`PrintStatementVisitor` detects bare `print()` and `debugPrint()` calls by matching `FunctionCallExprSyntax` where the called expression is a `DeclReferenceExprSyntax` with the name "print" or "debugPrint". Member access calls like `textField.print()` are not flagged.

```swift
// Before
print("User logged in: \(user.name)")
debugPrint(response)

// After
logger.info("User logged in: \(user.name)")
logger.debug("\(response)")
```

### Non-Violating Examples
```swift
// Structured logging
logger.info("hello")

// Member access — not a bare print call
textField.print()

// Other logging functions
NSLog("something")
```

### Violating Examples
```swift
// Bare print calls
print("hello")
debugPrint(object)
print("x:", someValue)
```

---
