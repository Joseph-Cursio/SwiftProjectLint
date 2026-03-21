[← Back to Rules](RULES.md)

## Swallowed Task Error

**Identifier:** `Swallowed Task Error`
**Category:** Code Quality
**Severity:** Warning

### Rationale
When a `Task { }` closure contains bare `try` expressions without a `do/catch` block, any thrown errors are silently lost. The task fails but the caller is never notified, leading to bugs that are difficult to diagnose. This is one of the most common pitfalls in Swift concurrency.

### Discussion
`SwallowedTaskErrorVisitor` detects `Task { }` closures (not `Task.detached`) where the trailing closure body contains at least one bare `try` (not `try?` or `try!`) but no `do/catch` block. `try?` and `try!` are excluded because they handle the error inline (by converting to nil or crashing). The search does not descend into nested closures or function declarations to avoid false positives.

The rule suppresses the warning when the Task's result is consumed, since errors propagate to the caller in those cases:
- `try await Task { ... }.value` — errors rethrown to the awaiter
- `await Task { ... }.result` — errors captured in the `Result`
- `let task = Task { ... }` — stored for later `.value`/`.result` access

Wrap throwing code in `do/catch` inside the Task, or consume the Task's result from the caller.

### Non-Violating Examples
```swift
// Task with do/catch
Task {
    do {
        try await riskyWork()
    } catch {
        logger.error("\(error)")
    }
}

// Task without throwing code
Task {
    await nonThrowingWork()
}

// try? handles the error inline (converts to nil)
Task {
    let data = try? await fetch()
    process(data)
}

// .value propagates errors to the caller
try await Task { @MainActor in
    try await riskyWork()
}.value

// .result captures errors for the caller to inspect
let result = await Task {
    try await fetch()
}.result

// Assigned Task — caller can await .value/.result later
let task = Task {
    try await riskyWork()
}
try await task.value
```

### Violating Examples
```swift
// Fire-and-forget — error is silently lost
Task {
    try await riskyWork()
}

// Assigned result is lost when try throws
Task {
    let data = try await fetch()
}
```

---
