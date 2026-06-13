[← Back to Rules](RULES.md)

## Swallowed Injection Downcast

**Identifier:** `Swallowed Injection Downcast`
**Category:** Code Quality
**Severity:** Info

### Rationale
An initializer that accepts a dependency through a protocol *advertises* that any conforming type will do — that's the whole point of injecting an abstraction, and it's what lets tests pass a mock. When the body then downcasts that parameter to one specific concrete type with `as?` / `as!`, the seam is a fiction: anything that isn't that exact type is silently discarded (an `as?` falls back to a default; an `as!` crashes). A substituted test double compiles, runs, and has **no effect** — the most expensive kind of bug, because the tests look like they exercise the injected behavior but don't.

This rule generalizes a real bug: an actor took a `CacheManagerProtocol?` and did `cache as? CacheManager`, throwing away any injected `MockCacheManager` in favor of a fresh real cache. The root cause was an isolation mismatch the author worked around with a downcast — it compiled and was concurrency-safe, but quietly broke injection.

### Discussion
`SwallowedInjectionDowncastVisitor` works within initializers:

1. It records each parameter whose type is an **abstraction** — written `any P`, or a nominal type whose name ends in `Protocol` (optionals and `(any P)?` unwrapped first).
2. It then flags any `as?` / `as!` whose operand is one of those parameters and whose **target is a concrete type** — not itself a protocol or `any`, which would be legitimate narrowing between abstractions.

The severity is **Info**: occasionally the downcast is genuinely intentional (e.g. an optional fast-path that still works for every conformer). Treat a flag as a prompt to confirm the injected value is actually honored.

### Non-Violating Examples
```swift
// Honors whatever is injected.
init(service: any ServiceProtocol) {
    self.service = service
}

// Narrowing one protocol to another is fine.
init(service: ServiceProtocol) {
    self.extra = service as? ExtraCapabilityProtocol
}
```

### Violating Examples
```swift
init(cache: CacheManagerProtocol? = nil) {
    if let provided = cache as? CacheManager {   // honors only CacheManager
        self.cache = provided
    } else {
        self.cache = CacheManager()              // injected mock dropped
    }
}

init(store: StoreProtocol) {
    self.concrete = store as! DiskStore          // defeats the protocol; crashes on others
}
```

### See Also
- [Concrete Type Usage](concrete-type-usage.md) — preferring protocol abstractions for dependencies.
- [Single Implementation Protocol](single-implementation-protocol.md) — the inverse smell (an abstraction with no real substitution).
