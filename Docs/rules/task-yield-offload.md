[← Back to Rules](RULES.md)

## Task Yield Offload

**Identifier:** `Task Yield Offload`
**Category:** Code Quality
**Severity:** Info

### Rationale
`Task.yield()` gives up the executor momentarily but does not offload work to another thread. If the code following the yield is CPU-intensive, it will resume on the same executor and still block it. Developers sometimes use `Task.yield()` thinking it offloads work, when they actually need `@concurrent` or `Task.detached`.

### Discussion
`TaskYieldOffloadVisitor` detects `Task.yield()` calls by checking for `MemberAccessExprSyntax` where the base is `Task` and the member is `yield`, with no arguments.

If the intent is to offload CPU-intensive work from the current actor, use `@concurrent` (Swift 6.2+) or `Task.detached` instead.

### Scope
- Flags `Task.yield()` calls (with no arguments) in production code
- **Skipped in test files** — `Task.yield()` is a standard testing pattern for giving the cooperative scheduler a chance to process pending tasks before assertions. Files containing "Test" or "Tests" in their path or name are excluded automatically.

### Non-Violating Examples
```swift
// Task.sleep — cooperative delay, not yield
await Task.sleep(for: .seconds(1))

// Task cancellation check
Task.checkCancellation()

// Instance method on a task variable
task.cancel()
```

### Violating Examples
```swift
// Yields the executor but does not offload work
await Task.yield()

// Without await
Task.yield()
```

---
