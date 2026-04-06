[← Back to Rules](RULES.md)

## Task Sleep Nanoseconds

**Identifier:** `Task Sleep Nanoseconds`
**Category:** Modernization
**Severity:** Warning

### Rationale
`Task.sleep(nanoseconds:)` was the original async sleep API but requires error-prone manual arithmetic to express common durations (e.g. `1_000_000_000` for one second). Swift 5.7 introduced `Task.sleep(for:)` which accepts a `Duration` value, making intent clear and eliminating unit-conversion bugs.

### Discussion
`TaskSleepNanosecondsVisitor` detects `Task.sleep(nanoseconds:)` calls. These should be replaced with the `Duration`-based overload.

```swift
// Before
try await Task.sleep(nanoseconds: 1_000_000_000) // one second?
try await Task.sleep(nanoseconds: 500_000_000)   // half a second?

// After
try await Task.sleep(for: .seconds(1))
try await Task.sleep(for: .milliseconds(500))
```

### Non-Violating Examples
```swift
try await Task.sleep(for: .seconds(2))
try await Task.sleep(for: .milliseconds(250))
try await Task.sleep(until: deadline, clock: .continuous)
```

### Violating Examples
```swift
try await Task.sleep(nanoseconds: 1_000_000_000)
try await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
```

---
