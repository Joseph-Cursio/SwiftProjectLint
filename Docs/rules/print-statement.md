[← Back to Rules](RULES.md)

## Print Statement

**Identifier:** `Print Statement`
**Category:** Code Quality
**Severity:** Warning (was Info — elevated for production code)

### Rationale
`print()` and `debugPrint()` write to standard output, which is not appropriate for production apps. Use structured logging (e.g., `os.Logger`) for diagnostics, or remove print statements before release.

### Discussion
`PrintStatementVisitor` detects bare `print()` and `debugPrint()` calls by matching `FunctionCallExprSyntax` where the called expression is a `DeclReferenceExprSyntax` with the name "print" or "debugPrint". Member access calls like `textField.print()` are not flagged.

**Context-aware severity:**
- `print()`/`debugPrint()` inside `#if DEBUG` → **suppressed** (compiled out in release builds)
- `print()` in production code → **warning**: "use os.Logger for structured logging"
- `debugPrint()` in production code → **warning**: "likely left over from debugging"

This rule is also suppressed for test files and executable targets in Swift Packages (where `print()` is the correct stdout mechanism).

### Non-Violating Examples
```swift
// Structured logging
logger.info("hello")

// Inside #if DEBUG — compiled out, suppressed
#if DEBUG
print("debug info: \(data)")
debugPrint(response)
#endif

// Member access — not a bare print call
textField.print()
```

### Violating Examples
```swift
// Production code — warning
print("User logged in: \(user.name)")
print("x:", someValue)

// debugPrint outside #if DEBUG — likely left over from debugging
debugPrint(object)
```

---
