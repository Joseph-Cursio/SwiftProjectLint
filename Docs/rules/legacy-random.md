[← Back to Rules](RULES.md)

## Legacy Random

**Identifier:** `Legacy Random`
**Category:** Code Quality
**Severity:** Info

### Rationale
`arc4random()`, `arc4random_uniform()`, and `drand48()` are C-era random number functions. Swift provides type-safe alternatives like `Int.random(in:)`, `Double.random(in:)`, and `Bool.random()` that are clearer, safer, and integrate with Swift's type system.

### Discussion
`LegacyRandomVisitor` detects calls to legacy C random functions. These functions return untyped or C-typed values that require casting, and `drand48()` requires explicit seeding for non-deterministic output.

```swift
// Before
let value = arc4random_uniform(100)
let fraction = drand48()

// After
let value = Int.random(in: 0..<100)
let fraction = Double.random(in: 0.0..<1.0)
```

### Non-Violating Examples
```swift
// Swift random APIs
let roll = Int.random(in: 1...6)
let coin = Bool.random()
let fraction = Double.random(in: 0.0...1.0)
```

### Violating Examples
```swift
// Legacy C random functions
let value = arc4random()
let bounded = arc4random_uniform(10)
let fraction = drand48()
```

---
