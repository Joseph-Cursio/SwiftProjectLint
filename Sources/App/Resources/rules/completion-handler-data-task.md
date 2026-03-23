[← Back to Rules](RULES.md)

## Completion Handler Data Task

**Identifier:** `Completion Handler Data Task`
**Category:** Code Quality
**Severity:** Info

### Rationale
`dataTask(with:completionHandler:)`, `downloadTask(with:completionHandler:)`, and `uploadTask(with:from:completionHandler:)` use callback-based networking that predates Swift concurrency. The completion handler variants require manual error handling, make it easy to forget calling the completion handler on all paths, and produce deeply nested code. The async/await equivalents are linear, throw errors naturally, and integrate with structured concurrency.

### Discussion
`CompletionHandlerDataTaskVisitor` detects calls to `dataTask`, `downloadTask`, or `uploadTask` where the call includes either a `completionHandler:` labeled argument or a trailing closure. Calls without a closure (e.g., `session.dataTask(with: url)` for delegate-based usage) are not flagged.

```swift
// Before — completion handler
URLSession.shared.dataTask(with: url) { data, response, error in
    guard let data = data else { return }
    // handle data
}.resume()

// After — async/await
let (data, response) = try await URLSession.shared.data(from: url)
// handle data
```

### Non-Violating Examples
```swift
// Async data fetch — preferred approach
let (data, response) = try await session.data(from: url)

// Async download
let (localURL, response) = try await URLSession.shared.download(from: url)

// Delegate-based dataTask (no closure)
let task = session.dataTask(with: url)
task.resume()
```

### Violating Examples
```swift
// dataTask with trailing closure
session.dataTask(with: url) { data, response, error in
    guard let data = data else { return }
    print(data)
}

// dataTask with completionHandler label
URLSession.shared.dataTask(with: request, completionHandler: handler)

// downloadTask with trailing closure
session.downloadTask(with: url) { tempURL, response, error in
    process(tempURL)
}

// uploadTask with completionHandler label
session.uploadTask(with: request, from: bodyData, completionHandler: handler)
```

---
