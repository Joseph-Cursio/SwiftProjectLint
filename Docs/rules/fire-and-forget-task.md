[← Back to Rules](RULES.md)

## Fire And Forget Task

**Identifier:** `Fire And Forget Task`
**Category:** Code Quality
**Severity:** Warning

### Rationale
A `Task { }` whose handle is immediately discarded cannot be cancelled, awaited, or observed. Any error thrown inside the closure is silently lost, and the task may outlive the object that spawned it. This pattern is extremely common in AI-generated Swift code and is one of the most frequent sources of subtle concurrency bugs.

### Discussion
`FireAndForgetTaskVisitor` visits every `FunctionCallExprSyntax`. When the callee is the bare `Task` type (not `Task.detached`, which is already covered by `TaskDetachedVisitor`) and the expression is used as a statement rather than being assigned or chained, the rule fires.

The result is considered **consumed** (and the rule suppressed) in these cases:

| Pattern | Reason |
|---------|--------|
| `let task = Task { }` | Handle stored for later cancellation/awaiting |
| `var handle = Task { }` | Same |
| `existingHandle = Task { }` | Handle assigned to an existing property/var (e.g. `analysisTask = Task { }`, cancelled later via `analysisTask?.cancel()`) |
| `try await Task { }.value` | Error propagates to caller |
| `Task { }.result` | Result captured by caller |

Use the standard inline suppression directive when the pattern is intentional:

```swift
// swiftprojectlint:disable:next fire-and-forget-task
Task { await logMetrics() }
```

`Task.detached` is intentionally excluded from this rule; it is already flagged by `TaskDetachedVisitor`.

### Legitimate fire-and-forget
Some contexts genuinely cannot store or await the handle, and a fire-and-forget `Task` is the idiomatic bridge. Suppress these with the directive rather than restructuring:

- **SwiftUI event handlers** — `Button("Save") { Task { await viewModel.save() } }`, `.onSubmit { Task { await search() } }`. The closure is synchronous and returns `Void`, so awaiting isn't possible.
- **Sync→async callback bridges** — a non-`async` delegate or closure (file-system watcher, MCP continuation) that needs to call into async code.
- **`defer { Task { await cleanup() } }`** and test teardown.
- **Telemetry / side effects** that must not block the caller and whose errors are already handled, e.g. `Task { try? await recorder.record(decision) }`.

There is usually nothing meaningful to cancel in these, and storing a handle would add complexity without benefit. The exception worth a real fix: when the task represents *re-triggerable* work where a stale in-flight run could clobber shared state — a search or detail-load that the user can fire repeatedly. There, store the handle in the owner and cancel the previous run (or guard the result assignment by identity) instead of suppressing.

### Suppression key
`fire-and-forget-task`

### Non-Violating Examples
```swift
// Handle stored — can be cancelled or awaited later
let task = Task {
    await doWork()
}
task.cancel()

// Handle assigned to an existing property — can be cancelled later
analysisTask = Task {
    await runAnalysis()
}
// elsewhere: analysisTask?.cancel()

// .value propagates errors to the caller
try await Task {
    try await riskyWork()
}.value

// .result lets the caller inspect success or failure
let result = await Task {
    try await fetch()
}.result

// Intentional fire-and-forget — suppressed with the standard directive
// swiftprojectlint:disable:next fire-and-forget-task
Task { await logMetrics() }
```

### Violating Examples
```swift
// Handle discarded — cannot cancel, errors silently lost
Task {
    await doWork()
}

// Multiple fire-and-forget tasks — each fires independently
func sync() {
    Task { await step1() }
    Task { await step2() }
}

// Task with throw — error is silently lost
Task {
    try await riskyWork()
}
```

---
