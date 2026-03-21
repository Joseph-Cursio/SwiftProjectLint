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

### Non-Violating Examples
```swift
// Plain nonisolated computed property
nonisolated var value: Int { 42 }

// Regular stored property
private var normal: Int = 0

// MainActor-isolated property
@MainActor var value = 0
```

### Violating Examples
```swift
// Silences data-race checking
nonisolated(unsafe) var detectorOverride: Foo?

// Private variable with unsafe annotation
nonisolated(unsafe) private var cache: [String]
```

---
