[← Back to Rules](RULES.md)

## URLSession Unhandled Error

**Identifier:** `URLSession Unhandled Error`
**Category:** Networking
**Severity:** Warning

### Rationale
`dataTask`, `downloadTask`, and `uploadTask` completion handlers receive an `Error?` as their last parameter. This is the only reliable signal that a network request failed — the HTTP status code lives in `URLResponse` and requires separate validation. Ignoring the error parameter means failures are silently swallowed and data may be processed from a failed request.

### Discussion
`URLSessionUnhandledErrorVisitor` checks every `FunctionCallExprSyntax` whose member name is `dataTask`, `downloadTask`, or `uploadTask`. For each, it extracts the completion closure (trailing or labeled `completionHandler:`), reads the last parameter name from the closure signature, and verifies that name appears somewhere in the closure body.

Not flagged when:
- The error parameter is explicitly `_` (developer opted out — suppress if intentional)
- No named closure signature (e.g. `$0/$1/$2` shorthand or a named function reference)

> **Note:** The visitor is name-based, not type-based. Any method named `dataTask`/`downloadTask`/`uploadTask` on any receiver will match. Use `swiftprojectlint:disable:next url-session-unhandled-error` for non-URLSession types with the same method name.

### Non-Violating Examples
```swift
URLSession.shared.dataTask(with: url) { data, response, error in
    if let error {
        logger.error("Request failed: \(error)")
        return
    }
    guard let data else { return }
    process(data)
}.resume()

// Explicit wildcard — intent is clear
URLSession.shared.dataTask(with: url) { data, response, _ in
    guard let data else { return }
    process(data)
}.resume()
```

### Violating Examples
```swift
// error parameter declared but never referenced
URLSession.shared.dataTask(with: url) { data, response, error in
    guard let data = data else { return }
    process(data)
}.resume()

// error parameter omitted from the guard — failures invisible
session.downloadTask(with: url) { location, response, error in
    guard let location else { return }
    handle(location)
}.resume()
```

---
