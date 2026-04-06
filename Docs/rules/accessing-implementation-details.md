[← Back to Rules](RULES.md)

## Accessing Implementation Details

**Identifier:** `Accessing Implementation Details`
**Category:** Architecture
**Severity:** Warning

### Rationale
Two patterns indicate a caller is reaching into an object's implementation rather than using its public interface: accessing underscore-prefixed members on external objects, and force-casting through a protocol reference to access concrete-type-specific members. Both patterns create tight coupling to internal implementation details that may change without notice.

### Discussion
`AccessingImplementationDetailsVisitor` detects two heuristics:

1. **Underscore prefix:** A member access `obj._someProperty` where `obj` is not `self`, `Self`, or `super`. Underscore-prefixed names are a Swift convention for internal or implementation-detail members. `self._member` and `Self._member` are exempt because accessing your own type's internals (including property wrapper storage and static members) is expected. Test files are also exempt, since test code commonly accesses internals for verification.

2. **Force-cast bypass:** A member access whose base expression contains `as! ConcreteServiceType`, where `ConcreteServiceType` ends with a service-like suffix. Force-casting to a concrete type to access members that are not on the protocol is a clear violation of the interface contract.

### Non-Violating Examples
```swift
// Accessing self's own underscore property (property wrapper storage)
class MyClass {
    var _prop: Int = 0
    func read() -> Int { return self._prop }
}

// Accessing Self's own static underscore member
struct Config {
    static var _all: [Config] = []
    static func reset() { Self._all.removeAll() }
}

// Optional cast — not flagged (only as! triggers this rule)
func safe(n: Networking) {
    _ = (n as? NetworkService)?.pool
}
```

### Violating Examples
```swift
// Accessing underscore member on another object
class Manager {
    let cache = Cache()
    func clear() { _ = cache._data }  // accessing implementation detail
}

// Force-cast to bypass protocol abstraction
func hack(n: Networking) {
    _ = (n as! NetworkService).connectionPool  // force-cast to concrete type
}
```

---
