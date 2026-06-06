[← Back to Rules](RULES.md)

## Missing Cancellation Check

**Identifier:** `Missing Cancellation Check`
**Category:** Code Quality
**Severity:** Warning

### Rationale
An `async` function that spawns `Task { }`, `withTaskGroup`, or `withThrowingTaskGroup` but never checks `Task.isCancelled` or calls `Task.checkCancellation()` will continue doing work even after its parent task has been cancelled. This wastes CPU, memory, and I/O for results that will never be used.

### Discussion
`MissingCancellationCheckVisitor` walks each `FunctionDeclSyntax` in the file. For every `async` function whose body contains at least one task-creation call, it checks whether the same body (not counting nested function declarations) contains either:

- A `Task.isCancelled` property access, or
- A `Task.checkCancellation()` method call

If neither is found, the rule fires once on the function declaration line.

Nested `func` declarations inside the flagged function are treated as separate scopes: a cancellation check buried inside a nested helper does not satisfy the outer function's requirement, and vice versa.

### When the warning is acceptable
The rule is a heuristic — it fires on *any* `async` function that creates a task, even when cancellation is already handled or simply irrelevant. Common cases where it is a false positive:

- **Structured concurrency.** `withTaskGroup` / `withThrowingTaskGroup` / `async let` propagate cancellation to their child tasks automatically, and the children's `await`s throw `CancellationError` when cancelled. A function whose only task creation is structured concurrency usually needs no manual check. The exception is a long drain loop that *swallows* child errors — e.g. `for try await x in group { … }` where the child returns `nil` on failure. There an explicit `try Task.checkCancellation()` in the loop makes the batch abort promptly instead of churning through every remaining item as a no-op.
- **Tests.** Test bodies spawn tasks for setup/teardown (`defer { Task { await server.stop() } }`) or to exercise concurrency. They have no meaningful parent to cancel them, so the check is noise — in practice essentially every occurrence inside a test is fine.
- **Fire-and-forget side effects.** A function flagged only because it kicks off `Task { await logMetrics() }`-style telemetry doesn't need the *enclosing* function to check cancellation.

For these, suppress with `// swiftprojectlint:disable:next missing-cancellation-check`. Add a real check only when the function performs a long, cancellable unit of work that would otherwise run to completion after its parent is cancelled.

Because essentially every occurrence inside a test is a false positive, consider **disabling this rule for test directories entirely** rather than peppering test files with suppression comments — via a per-rule path exclusion in `.swiftprojectlint.yml`:

```yaml
rules:
  "Missing Cancellation Check":
    excluded_paths:
      - "Tests/"
```

This keeps the rule active on production code while silencing the test noise in one place.

### Suppression key
`missing-cancellation-check`

### Non-Violating Examples
```swift
// Guard with isCancelled before spawning work
func sync() async {
    guard !Task.isCancelled else { return }
    Task { await step1() }
}

// isCancelled checked inside the Task closure
func fetchData() async {
    Task {
        guard !Task.isCancelled else { return }
        await doWork()
    }
}

// checkCancellation() used with withTaskGroup
func process() async throws {
    try Task.checkCancellation()
    try await withThrowingTaskGroup(of: Data.self) { group in
        group.addTask { try await fetch() }
    }
}

// Async function with no task creation — rule does not fire
func compute() async -> Int {
    await heavyCalculation()
}
```

### Violating Examples
```swift
// Task { } spawned with no cancellation check
func fetchData() async {
    Task {
        await doWork()
    }
}

// withTaskGroup without any cancellation guard
func process() async throws {
    await withTaskGroup(of: Void.self) { group in
        group.addTask { await doWork() }
    }
}

// Multiple tasks, still no check
func sync() async {
    Task { await step1() }
    Task { await step2() }
}

// Check is only inside a nested function — outer still flagged
func outer() async {
    Task { await doWork() }
    func helper() async {
        guard !Task.isCancelled else { return }
    }
    await helper()
}
```

---
