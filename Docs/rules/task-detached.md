[← Back to Rules](RULES.md)

## Task Detached

**Identifier:** `Task Detached`
**Category:** Code Quality
**Severity:** Info

### Rationale
`Task.detached` creates an unstructured task that does not inherit the current actor context, task-local values, or priority. This breaks structured concurrency guarantees and makes reasoning about task lifetimes harder. In most cases, a plain `Task { }` is sufficient and preserves the structured concurrency model.

### Discussion
`TaskDetachedVisitor` detects `Task.detached { }` and `Task.detached(priority:) { }` calls by checking for `MemberAccessExprSyntax` where the base is `Task` and the member is `detached`.

Use `Task.detached` only when you explicitly need to escape the current actor context — for example, to perform CPU-bound work off the main actor without inheriting `@MainActor` isolation.

### Non-Violating Examples
```swift
// Plain Task — inherits current actor context
Task {
    await work()
}

// Task with priority — still structured
Task(priority: .high) {
    await work()
}
```

### Violating Examples
```swift
// Task.detached — breaks structured concurrency
Task.detached {
    await work()
}

// Task.detached with priority
Task.detached(priority: .background) {
    await work()
}
```

---
