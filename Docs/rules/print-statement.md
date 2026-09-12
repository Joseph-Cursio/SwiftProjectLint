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

### Executable targets are excluded
`print` to stdout is a command-line tool's interface, not logging — routing it to `os.Logger` would send the output to the unified log and print nothing. Source under an `.executableTarget` is therefore excluded, and that now includes executable targets declared in **nested** packages: an Xcode project has no manifest at its root, so a CLI living in a package beside the app used to be reported for the output the user asked for.

**A library target is not excluded**, even in a package that also ships a CLI. `print(error)` inside a `catch` is exactly what this rule is for, wherever it lives.

**Known gap.** The common swift-argument-parser layout puts a thin `@main` in the executable target and all the command logic — including the program's output — in a *library* target it depends on. The exclusion covers the stub and not the code that prints: 37 findings in one such package. A suppression comment is the tool for that today.

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
