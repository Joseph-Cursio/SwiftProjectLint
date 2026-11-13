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
| **Error variable reference** | The implicit `error` binding, or any name the catch pattern binds (`e` in `catch let e as DecodingError`, `message` in `catch AppError.invalid(let message)`), appears anywhere in the body — covers `self.lastError = error`, `completion(.failure(error))`, `"Failed: \(error)"`, error captured in a closure. It must be the binding itself: a member, implicit member or key path spelled the same (`result.error`, `self.error = nil`, `state = .error`, `jobs.filter(\.error)`) belongs to another value and does not count. A typed arm that binds nothing (`catch is CancellationError`) does not bind `error` either, so only rethrowing, logging or terminating handles it |
| **Explicit termination** | `assertionFailure(...)`, `fatalError(...)`, `preconditionFailure(...)` |

**Rethrow boundary**: a `throw` inside a nested closure or function does not satisfy the check — that throw belongs to the inner scope, not the catch body.

**Error reference crosses closures**: the error variable is considered referenced even if it appears inside a closure inside the catch block (e.g. `DispatchQueue.main.async { self.error = error }`), since it is captured from the catch scope.

### Intentional graceful degradation
A common — and legitimate — pattern is a catch that deliberately degrades: returning the original input, an empty collection, or `nil` on failure (often documented in the function's doc comment, e.g. *"Returns the original on any failure"*). These are not bugs, but the swallowed error is still invisible. **Prefer logging over suppression**: a single `logger.warning("…: \(error)")` makes the failure diagnosable, preserves the fallback, and satisfies the rule. Reserve the suppression directive for cases where even a log line is unwanted (a hot path where the failure is truly expected and noise-free).

```swift
// Graceful degradation done right — fallback preserved, failure logged
func format(_ swift: String) async -> String {
    do { return try await formatter.format(swift) }
    catch {
        logger.warning("Formatting failed, returning original: \(error)")
        return swift
    }
}
```

### A `try?` with a default
**`(try? f()) ?? fallback` is not flagged, by design.** It swallows the error just as `do { return try f() } catch { return fallback }` does, but it states the fallback at the call site: a reader can see that a failure becomes `fallback`. Treat it as the one-line equivalent of the suppression directive. Other rules draw the line in the same place. [Swallowed Task Error](swallowed-task-error.md) counts `try?` as handling the error inline, and [Discarded Try Result](discarded-try-result.md) flags a `try?` only when its value is thrown away.

```swift
func countViaCatch(_ text: String) -> Int {
    do { return try parse(text) } catch { return 0 }   // flagged: the fallback hides in a catch arm
}

func countViaTryOptional(_ text: String) -> Int {
    (try? parse(text)) ?? 0                              // not flagged: the fallback is spelled inline
}
```

The rule checks only `catch` clauses, and no other rule targets this shape. Most uses are deliberate best-effort reads, such as a directory listing, `resourceValues(…).isDirectory ?? false` or an existence check. A rule matching the spelling would mostly flag code that is fine.

Use it only where the default really is the whole answer. A `try?` default can make a failure look like a real empty result: `(try? identities(of: sources)) ?? []` turns a read or parse failure into an empty set. Any later code that explains that empty set will then blame the wrong component. Where someone may need to diagnose the failure, use `do`/`catch` with a log line, as in the example above.

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
