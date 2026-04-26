[← Back to Rules](RULES.md)

## Catch Without Handling

**Identifier:** `Catch Without Handling`
**Suppression key:** `catch-without-handling`
**Category:** Code Quality
**Severity:** Warning

### Rationale
A `catch` block that doesn't rethrow, log, or propagate the error is a silent failure. The program continues as if nothing went wrong, making bugs extremely difficult to diagnose. This is equally true whether the block is completely empty or whether it updates unrelated state (e.g. `isLoading = false`) without touching the error.

### Discussion
`EmptyCatchVisitor` checks every `CatchClauseSyntax`. A catch block is considered **handled** when its body contains at least one of:

| Signal | Examples |
|--------|---------|
| **Rethrow** | `throw error`, `throw e` (not crossing closure/function boundaries) |
| **Logging** | `print(error)`, `NSLog(...)`, `os_log(...)`, `logger.error(...)`, `Logger.shared.debug(...)`, any method call with a logging-suggestive name (`log`, `error`, `warning`, `warn`, `debug`, `info`, `critical`, `fault`, `verbose`, `trace`, `notice`) |
| **Swift Testing diagnostic** | `Issue.record(...)` — receiver-gated on the `Issue` type identifier so adopter-defined `record(...)` methods on unrelated types still fire |
| **Error variable reference** | The implicit `error` binding (or the typed catch pattern name) appears anywhere in the body — covers `self.lastError = error`, `completion(.failure(error))`, `"Failed: \(error)"`, error captured in a closure |
| **Explicit termination** | `assertionFailure(...)`, `fatalError(...)`, `preconditionFailure(...)` |

**Rethrow boundary**: a `throw` inside a nested closure or function does not satisfy the check — that throw belongs to the inner scope, not the catch body.

**Error reference crosses closures**: the error variable is considered referenced even if it appears inside a closure inside the catch block (e.g. `DispatchQueue.main.async { self.error = error }`), since it is captured from the catch scope.

### Suppression
Use the standard directive when swallowing the error is genuinely intentional:

```swift
// swiftprojectlint:disable:next catch-without-handling
} catch { }
```

### Non-Violating Examples
```swift
// Rethrow
do {
    try work()
} catch {
    throw error
}

// Logging
do {
    try work()
} catch {
    logger.error("Operation failed: \(error)")
}

do {
    try work()
} catch {
    print("Error: \(error)")
}

// Error state propagation
do {
    try work()
} catch {
    self.errorMessage = error.localizedDescription
}

do {
    try work()
} catch {
    completion(.failure(error))
}

// Typed catch pattern — variable name extracted correctly
do {
    try work()
} catch let failure as NetworkError {
    self.lastFailure = failure
}

// Explicit termination
do {
    try work()
} catch {
    assertionFailure("This path should be unreachable: \(error)")
}

// Swift Testing diagnostic — the canonical "unexpected error in
// a test body" idiom. The bare `catch` arm routes the message
// into the test runner's diagnostic stream.
do {
    try work()
} catch is ExpectedError {
    // expected — assertion below confirms the throw site
} catch {
    Issue.record("unexpected error type: \(error)")
}
```

### Violating Examples
```swift
// Empty body
do {
    try work()
} catch { }

// Updates state but ignores the error
do {
    try work()
} catch {
    isLoading = false
}

// Returns without conveying the error
do {
    try work()
} catch {
    return nil
}

// Comment-only body
do {
    try work()
} catch {
    // TODO: handle this later
}
```

---
