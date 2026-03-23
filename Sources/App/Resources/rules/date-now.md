[← Back to Rules](RULES.md)

## Date Now

**Identifier:** `Date Now`
**Category:** Code Quality
**Severity:** Info

### Rationale
`Date()` and `Date.now` both return the current date, but `.now` is shorter, reads more naturally, and avoids an unnecessary initializer call. `Date.now` has been available since iOS 15 / macOS 12.

### Discussion
`DateNowVisitor` detects `Date()` calls with no arguments. These can be replaced with `Date.now` (or just `.now` when the type is already known).

```swift
// Before
lastRunDate = Date()
let elapsed = Date().timeIntervalSince(lastRun)

// After
lastRunDate = .now
let elapsed = Date.now.timeIntervalSince(lastRun)
```

### Non-Violating Examples
```swift
// Date.now — preferred API
let now = Date.now

// Date with arguments — different initializer
let epoch = Date(timeIntervalSince1970: 0)

// Other types named similarly
let formatter = DateFormatter()
```

### Violating Examples
```swift
// Date() with no arguments
let now = Date()
let elapsed = Date().timeIntervalSince(lastRun)
lastRunDate = Date()
```

---
