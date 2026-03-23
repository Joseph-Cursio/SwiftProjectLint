[← Back to Rules](RULES.md)

## Synchronous Network Call

**Identifier:** `Synchronous Network Call`
**Category:** Networking
**Severity:** Error

### Rationale
`Data(contentsOf: url)` performs a synchronous network request on the calling thread. When called on the main thread, this blocks the UI for the full duration of the network round trip — potentially several seconds — causing the app to become unresponsive and the system watchdog to terminate it.

### Discussion
`NetworkingVisitor` detects calls to `Data(contentsOf:)` by looking for `Data` as the called expression and `contentsOf` as a labeled argument. The error severity reflects that this is a correctness issue in production apps. The fix is to use `URLSession.shared.dataTask(with:completionHandler:)` or `URLSession.shared.data(from:)` in a `Task` for concurrent code.

### Non-Violating Examples
```swift
// Async with URLSession
Task {
    let (data, _) = try await URLSession.shared.data(from: url)
    // process data
}

// Data() without contentsOf — fine
let emptyData = Data()
let fixedData = Data([1, 2, 3])
```

### Violating Examples
```swift
let url = URL(string: "https://example.com")!
let data = try Data(contentsOf: url)  // synchronous network call — blocks main thread
```

---
