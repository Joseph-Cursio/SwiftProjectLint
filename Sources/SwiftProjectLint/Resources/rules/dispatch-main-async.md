[← Back to Rules](RULES.md)

## Dispatch Main Async

**Identifier:** `Dispatch Main Async`
**Category:** Code Quality
**Severity:** Info

### Rationale
`DispatchQueue.main.async` and `DispatchQueue.main.sync` are legacy GCD patterns for scheduling work on the main thread. Swift concurrency provides `MainActor.run` and `@MainActor` annotations that integrate cleanly with async/await and are checked at compile time.

### Discussion
`DispatchMainAsyncVisitor` detects calls to `DispatchQueue.main.async { }` and `DispatchQueue.main.sync { }`. These can be replaced with `MainActor.run { }` for one-off main-thread work, or by marking the enclosing function `@MainActor` for broader main-thread isolation.

```swift
// Before
DispatchQueue.main.async {
    self.label.text = "Done"
}

// After
await MainActor.run {
    self.label.text = "Done"
}

// Or mark the function
@MainActor
func updateLabel() {
    self.label.text = "Done"
}
```

### Non-Violating Examples
```swift
// MainActor.run — preferred concurrency API
await MainActor.run {
    self.updateUI()
}

// @MainActor function
@MainActor func refresh() { }

// Global queue dispatch — different queue, not flagged
DispatchQueue.global().async { self.doWork() }
```

### Violating Examples
```swift
// DispatchQueue.main.async
DispatchQueue.main.async {
    self.updateUI()
}

// DispatchQueue.main.sync
DispatchQueue.main.sync {
    self.flushChanges()
}
```

---
