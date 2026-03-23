[← Back to Rules](RULES.md)

## CF Absolute Time

**Identifier:** `CF Absolute Time`
**Category:** Code Quality
**Severity:** Info

### Rationale
`CFAbsoluteTimeGetCurrent()` is a legacy Core Foundation function that returns a `CFAbsoluteTime` (a `Double` of seconds since Jan 1, 2001). For timing measurements, `ContinuousClock` provides a monotonic clock that is not affected by system clock changes. For timestamps, `Date.now` is more idiomatic Swift.

### Discussion
`CFAbsoluteTimeVisitor` detects calls to `CFAbsoluteTimeGetCurrent()`. A common pattern is measuring elapsed time between two calls, which is better served by `ContinuousClock` since it is monotonic and not subject to NTP adjustments.

```swift
// Before
let start = CFAbsoluteTimeGetCurrent()
doWork()
let elapsed = CFAbsoluteTimeGetCurrent() - start

// After
let clock = ContinuousClock()
let elapsed = try await clock.measure {
    doWork()
}
```

### Non-Violating Examples
```swift
// ContinuousClock for timing
let clock = ContinuousClock()
let elapsed = try await clock.measure { doWork() }

// Date.now for timestamps
let timestamp = Date.now
```

### Violating Examples
```swift
// Legacy Core Foundation timing
let start = CFAbsoluteTimeGetCurrent()
doWork()
let elapsed = CFAbsoluteTimeGetCurrent() - start
```

---
