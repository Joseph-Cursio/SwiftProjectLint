[← Back to Rules](RULES.md)

## Unchecked Sendable

**Identifier:** `Unchecked Sendable`
**Category:** Code Quality
**Severity:** Warning

### Rationale
`@unchecked Sendable` tells the compiler to trust the developer that a type is safe to pass across concurrency boundaries — without verifying that claim. In practice, it is frequently applied as a quick fix to silence Swift 6 strict-concurrency errors, silently converting compiler errors into potential data races at runtime.

### Discussion
`UncheckedSendableVisitor` detects `@unchecked Sendable` conformances on `class`, `struct`, and `enum` declarations by inspecting their inheritance clauses for an `AttributedTypeSyntax` whose attribute list contains `@unchecked` and whose base type is `Sendable`.

In the SwiftSyntax AST, `@unchecked Sendable` in the inheritance clause is represented as an `InheritedTypeSyntax` where the `type` is an `AttributedTypeSyntax` with `@unchecked` in its `attributes` list and `Sendable` as the `baseType`.

### Suppression: Lock-Guarded Types

The warning is suppressed when the type's member block contains a stored property of a recognized synchronization primitive, indicating the developer is managing thread safety explicitly rather than silencing the compiler without a safety net.

Recognized lock types: `OSAllocatedUnfairLock`, `Mutex`, `NSLock`, `NSRecursiveLock`. Detection covers both explicit type annotations and inferred types from initializer calls (e.g. `let lock = NSLock()`), including generic specializations such as `OSAllocatedUnfairLock<()>`.

### Non-Violating Examples
```swift
// Plain Sendable — compiler verifies conformance
struct Point: Sendable {
    let x: Double
    let y: Double
}

// Lock-guarded — OSAllocatedUnfairLock protects mutable state
final class ThreadSafeCache: @unchecked Sendable {
    private let lock = OSAllocatedUnfairLock()
    private var cache: [String: Data] = [:]
}

// Mutex also suppresses the warning
final class Counter: @unchecked Sendable {
    private let lock = Mutex<Int>(0)
}

// NSLock and NSRecursiveLock are recognized
class Service: @unchecked Sendable {
    private let lock: NSLock = NSLock()
    private var value: Int = 0
}
```

### Violating Examples
```swift
// Unprotected mutable state — @unchecked is a lie
class NetworkCache: @unchecked Sendable {
    var cache: [String: Data] = [:]
}

// Struct with mutable var and no synchronization
struct Config: @unchecked Sendable {
    var value: String = ""
}

// Enum — @unchecked adds no value here; remove it
enum State: @unchecked Sendable {
    case idle
    case running
}
```

---
