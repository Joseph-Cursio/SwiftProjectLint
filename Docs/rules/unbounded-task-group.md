[<- Back to Rules](RULES.md)

## Unbounded Task Group

**Identifier:** `Unbounded Task Group`
**Category:** Performance
**Severity:** Warning

### Rationale
`withTaskGroup` and `withThrowingTaskGroup` are powerful structured concurrency primitives, but when tasks are added in a loop without limiting concurrency, the runtime may spawn thousands of concurrent tasks. This exhausts thread pool resources, causes memory pressure, and can deadlock the cooperative thread pool.

### Discussion
`UnboundedTaskGroupVisitor` detects `group.addTask` calls inside `for` or `while` loops within a task group closure, where no `group.next()` call is present in the same loop body to provide backpressure. A `for await ... in group` loop that consumes the group is recognized as backpressure and suppresses the warning.

### Non-Violating Examples
```swift
// Manual backpressure with group.next()
await withTaskGroup(of: Data.self) { group in
    let maxConcurrency = 10
    for (index, url) in urls.enumerated() {
        if index >= maxConcurrency {
            _ = await group.next()
        }
        group.addTask {
            try await fetchData(from: url)
        }
    }
}

// Consuming results with for-await (separate loop)
await withTaskGroup(of: Data.self) { group in
    for url in urls {
        group.addTask { await fetch(url) }
    }
    for await result in group {
        process(result)
    }
}
// Note: The above is flagged because the addTask loop lacks backpressure.
// The for-await loop is separate and runs after all tasks are spawned.
```

### Violating Examples
```swift
// Unbounded task creation — may exhaust thread pool
await withTaskGroup(of: Data.self) { group in
    for url in urls {
        group.addTask {
            try await fetchData(from: url)
        }
    }
    for await result in group { /* ... */ }
}
```

---
