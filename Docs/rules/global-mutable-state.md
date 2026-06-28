[← Back to Rules](RULES.md)

## Global Mutable State

**Identifier:** `Global Mutable State`
**Category:** Testability
**Severity:** Warning

### Rationale
A top-level `var` or a `static var` is shared, process-wide mutable state. Property-based testing runs the same code across hundreds of randomized trials and expects each trial to start from a clean slate. Global mutable state survives between trials, so a value written in one trial leaks into the next — making failures non-reproducible and shrinking unreliable. The same state also makes parallel test execution unsafe.

### Discussion
`GlobalMutableStateVisitor` flags a `VariableDeclSyntax` that is `var`, is *stored* (has no accessor block — computed `var`s are pure and exempt), and is either declared with the `static` modifier or at file scope (its declaration chains directly up to the `SourceFileSyntax`). `let` constants, computed properties, and instance-level stored properties are not flagged.

```swift
// Before — process-wide mutable state
var sharedCounter = 0

enum Config {
    static var retryLimit = 3
}

// After — instance-scoped, injectable, resettable per trial
struct Counter { var value = 0 }

struct Config {
    var retryLimit: Int
}
```

### Non-Violating Examples
```swift
// Top-level constant
let maxRetries = 3

// Computed (no stored state)
var now: Date { Date() }

// Instance stored property
struct Session { var token: String }

// Static constant
enum Config { static let baseURL = "https://example.com" }
```

### Violating Examples
```swift
// File-scope stored var
var currentUser: String?

// Static stored var
final class Cache {
    static var entries: [String: Data] = [:]
}
```

---
