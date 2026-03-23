[← Back to Rules](RULES.md)

## Dispatch Semaphore in Async

**Identifier:** `Dispatch Semaphore in Async`
**Category:** Performance
**Severity:** Warning

### Rationale
Swift Concurrency uses a cooperative thread pool with a limited number of threads. Calling `DispatchSemaphore.wait()` inside an async function blocks the current thread, preventing it from executing other tasks. If enough threads are blocked, the entire cooperative thread pool stalls, leading to deadlocks and hangs.

### Discussion
`DispatchSemaphoreInAsyncVisitor` inspects `FunctionCallExprSyntax` nodes for `DispatchSemaphore(value:)` calls and walks up the parent chain to determine whether the call is inside an async function or async closure. Synchronous functions and non-async closures are not flagged, even when nested inside an async function.

Replace semaphore-based synchronization with Swift Concurrency primitives:

```swift
// Before — blocks the cooperative thread pool
func fetchData() async {
    let semaphore = DispatchSemaphore(value: 0)
    legacyAPI { result in
        process(result)
        semaphore.signal()
    }
    semaphore.wait()
}

// After — uses withCheckedContinuation
func fetchData() async {
    await withCheckedContinuation { continuation in
        legacyAPI { result in
            process(result)
            continuation.resume()
        }
    }
}
```

### Non-Violating Examples
```swift
// Synchronous function — semaphore is appropriate
func fetchDataSync() {
    let semaphore = DispatchSemaphore(value: 0)
    URLSession.shared.dataTask(with: url) { _, _, _ in
        semaphore.signal()
    }.resume()
    semaphore.wait()
}

// Non-async closure inside async function — not flagged
func fetchData() async {
    let callback = {
        let semaphore = DispatchSemaphore(value: 0)
        semaphore.wait()
    }
}
```

### Violating Examples
```swift
// Semaphore in async function — blocks the thread pool
func fetchData() async {
    let semaphore = DispatchSemaphore(value: 0)
    legacyAPI { semaphore.signal() }
    semaphore.wait()
}

// Semaphore in async throws function
func loadItems() async throws {
    let semaphore = DispatchSemaphore(value: 1)
    performLegacyCall()
    semaphore.wait()
}
```

---
