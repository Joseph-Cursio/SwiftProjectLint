[← Back to Rules](RULES.md)

## Empty Catch

**Identifier:** `Empty Catch`
**Category:** Code Quality
**Severity:** Warning

### Rationale
An empty catch block silently swallows errors, making it difficult to diagnose failures. Always log or handle caught errors, even if just printing them during development.

### Discussion
`EmptyCatchVisitor` detects `CatchClauseSyntax` nodes where `body.statements` is empty. Catch blocks that contain any statement (logging, rethrowing, assignment, etc.) are not flagged.

```swift
// Before
do {
    try riskyOperation()
} catch {
}

// After
do {
    try riskyOperation()
} catch {
    logger.error("Operation failed: \(error)")
}
```

### Non-Violating Examples
```swift
// Catch with logging
do {
    try riskyOperation()
} catch {
    print(error)
}

// Catch with rethrow
do {
    try riskyOperation()
} catch {
    throw error
}
```

### Violating Examples
```swift
// Empty catch — error silently swallowed
do {
    try riskyOperation()
} catch {
}

do {
    try loadData()
} catch {
}
```

---
