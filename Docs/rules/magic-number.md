[← Back to Rules](RULES.md)

## Magic Number

**Identifier:** `Magic Number`
**Category:** Code Quality
**Severity:** Info

### Rationale
An integer or float literal of 10 or greater that appears without a named constant is a "magic number." Its meaning is not self-evident to future readers, and if the same value appears in multiple places, a change requires finding and updating every occurrence.

### Discussion
`CodeQualityVisitor` checks integer and float literals in variable initializers and function call arguments. Values below 10 are exempt because small numbers (0, 1, 2) are conventional in many contexts. The threshold is configurable via `CodeQualityVisitor.Configuration.magicNumberThreshold` (default: 10; strict mode: 5). The fix is to declare a named constant: `let maxRetries = 3` and then reference it by name.

### Non-Violating Examples
```swift
let maxRetries = 3
let defaultTimeout: TimeInterval = 30

func configure() {
    connection.timeout = defaultTimeout
    retry(count: maxRetries)
}
```

### Violating Examples
```swift
var count = 100  // magic number ≥ 10

func fetch() {
    URLSession.shared.dataTask(with: url).resume()
    waitFor(seconds: 30)  // literal 30 in function argument
}
```

---
