[← Back to Rules](RULES.md)

## Nonisolated Unsafe

**Identifier:** `Nonisolated Unsafe`
**Category:** Code Quality
**Severity:** Warning

### Rationale
`nonisolated(unsafe)` silences the compiler's data-race checking without fixing the underlying issue. This annotation tells the compiler to trust the developer that no data race exists, but it hides potential concurrency bugs that could lead to crashes or data corruption.

### Discussion
`NonisolatedUnsafeVisitor` detects `nonisolated(unsafe)` annotations on variable declarations by inspecting `VariableDeclSyntax` modifiers for a `nonisolated` modifier with an `unsafe` detail.

Instead of silencing the compiler, prefer using an actor to isolate the state, passing the value as a parameter, or using `Mutex` for synchronization.

### Suppression: Lock-Guarded Properties

The warning is suppressed when the enclosing type declares a stored property of a recognized lock type, indicating the developer is managing synchronization explicitly rather than silencing the compiler without a safety net.

Recognized lock types: `OSAllocatedUnfairLock`, `Mutex`, `NSLock`, `NSRecursiveLock`. Detection covers both explicit type annotations and inferred types from initializer calls (e.g. `let lock = OSAllocatedUnfairLock()`), including generic specializations such as `OSAllocatedUnfairLock<()>`.

### Non-Violating Examples
```swift
// Plain nonisolated computed property
nonisolated var value: Int { 42 }

// Regular stored property
private var normal: Int = 0

// MainActor-isolated property
@MainActor var value = 0

// Lock-guarded — OSAllocatedUnfairLock protects all accesses
final class FSEventsWatcher {
    private let lock = OSAllocatedUnfairLock()
    private nonisolated(unsafe) var handler: (() -> Void)?
}

// Generic lock specialization also suppresses the warning
final class Cache {
    private let mutex = Mutex<[String: Int]>([:])
    nonisolated(unsafe) var data: [String: Int] = [:]
}
```

### Violating Examples
```swift
// Silences data-race checking with no lock in sight
nonisolated(unsafe) var detectorOverride: Foo?

// Private variable with unsafe annotation, no synchronization
nonisolated(unsafe) private var cache: [String]

// Enclosing type has no lock — warning is not suppressed
final class BadActor {
    nonisolated(unsafe) var state: Int = 0
}
```

---
