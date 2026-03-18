[← Back to Rules](RULES.md)

## Missing Error Handling

**Identifier:** `Missing Error Handling`
**Category:** Networking
**Severity:** Warning

### Rationale
A `URLSession.dataTask` completion handler that ignores the `error` parameter silently drops network failures. Users see stale data or a spinning indicator with no indication that an error occurred. Proper error handling enables the UI to display meaningful feedback.

### Discussion
`NetworkingVisitor` examines the trailing closure of `URLSession.dataTask` calls. It checks whether the third parameter is named `error` (and handled with `if let`, `guard let`, `error != nil`, `error.`, or `error as` patterns), or whether the third parameter is `_` (ignored), or whether error handling patterns appear in the closure body text even without a named third parameter. If none of these patterns are found, a warning is reported. The visitor also reports a separate issue when the third parameter is explicitly `_` (discarded), because ignoring the error parameter is a distinct anti-pattern.

### Non-Violating Examples
```swift
// Named error parameter handled with if let
URLSession.shared.dataTask(with: url) { data, response, error in
    if let error = error {
        print(error)
    }
}.resume()

// Guard let pattern
URLSession.shared.dataTask(with: url) { data, response, error in
    guard let error = error else { return }
    print(error)
}.resume()

// Error != nil check
URLSession.shared.dataTask(with: url) { data, response, error in
    if error != nil {
        print("Error occurred")
    }
}.resume()
```

### Violating Examples
```swift
// No error handling — error parameter ignored
URLSession.shared.dataTask(with: url) { data, response, _ in
    // No error handling
}.resume()

// No closure at all for error
URLSession.shared.dataTask(with: url) { data, response in
    // only two params — no error handling
}.resume()
```

---
