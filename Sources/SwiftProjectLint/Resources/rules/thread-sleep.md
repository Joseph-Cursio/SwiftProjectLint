[← Back to Rules](RULES.md)

## Thread Sleep

**Identifier:** `Thread Sleep`
**Category:** Code Quality
**Severity:** Warning

### Rationale
`Thread.sleep(forTimeInterval:)` blocks the current thread entirely, preventing any other work from executing on it. In async contexts, `Task.sleep(for:)` suspends the current task cooperatively, freeing the thread for other work.

### Discussion
`ThreadSleepVisitor` detects calls to `Thread.sleep(...)`. Blocking a thread is especially harmful on the main thread (causes UI freezes) and wasteful on background threads in a cooperative concurrency environment.

```swift
// Before
Thread.sleep(forTimeInterval: 1.0)

// After
try await Task.sleep(for: .seconds(1))
```

### Non-Violating Examples
```swift
// Task.sleep — cooperative suspension
try await Task.sleep(for: .seconds(1))

// Other Thread properties
let isMain = Thread.isMainThread
```

### Violating Examples
```swift
// Thread.sleep blocks the thread
Thread.sleep(forTimeInterval: 1.0)
Thread.sleep(until: Date().addingTimeInterval(2.0))
```

---
