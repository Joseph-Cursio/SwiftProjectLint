[← Back to Rules](RULES.md)

## Swallowed Task Error

**Identifier:** `Swallowed Task Error`
**Category:** Code Quality
**Severity:** Warning

### Rationale
When a `Task { }` closure contains bare `try` expressions without a `do/catch` block, any thrown errors are silently lost. The task fails but the caller is never notified, leading to bugs that are difficult to diagnose. This is one of the most common pitfalls in Swift concurrency.

### Discussion
`SwallowedTaskErrorVisitor` detects `Task { }` closures (not `Task.detached`) where the trailing closure body contains at least one bare `try` (not `try?` or `try!`) but no `do/catch` block. `try?` and `try!` are excluded because they handle the error inline (by converting to nil or crashing). The search does not descend into nested closures or function declarations to avoid false positives.

Wrap throwing code in `do/catch` inside the Task, or handle the error via `Task.result` from the caller.

### Non-Violating Examples
```swift
// Task with proper error handling
Task {
    do {
        try await riskyWork()
    } catch {
        print(error)
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
```

### Violating Examples
```swift
// Error from try is silently lost
Task {
    try await riskyWork()
}

// Assigned result is lost when try throws
Task {
    let data = try await fetch()
}
```

---
