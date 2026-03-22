[← Back to Rules](RULES.md)

## Print Statement

**Identifier:** `Print Statement`
**Category:** Code Quality
**Severity:** Info

### Rationale
`print()` and `debugPrint()` write to standard output, which is not appropriate for production apps. Use structured logging (e.g., `os.Logger`) for diagnostics, or remove print statements before release.

### Discussion
`PrintStatementVisitor` detects bare `print()` and `debugPrint()` calls by matching `FunctionCallExprSyntax` where the called expression is a `DeclReferenceExprSyntax` with the name "print" or "debugPrint". Member access calls like `textField.print()` are not flagged.

This rule is automatically suppressed in two cases:

- **Test files** — files whose path contains `Test` or `Tests` are exempt. `print()` is a common and acceptable pattern in test code for diagnostic output during test runs.
- **Executable targets in Swift Packages** — if a `Package.swift` is detected at the project root, source directories belonging to `.executableTarget` declarations are exempt. In a CLI program, `print()` is the correct mechanism for writing to stdout; replacing it with `os.Logger` would write to the unified logging system instead of the terminal, silently breaking user-facing output. Both the default source convention (`Sources/<name>/`) and explicit `path:` parameters are recognised.

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
