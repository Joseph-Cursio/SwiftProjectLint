[<- Back to Rules](RULES.md)

## Legacy Array Init

**Identifier:** `Legacy Array Init`
**Category:** Modernization
**Severity:** Info *(opt-in)*

### Rationale
`Array<Element>()`, `Dictionary<Key, Value>()`, and `Optional<Wrapped>.none` can be written more concisely using Swift's sugar syntax: `[Element]()`, `[Key: Value]()`, and `nil`. While functionally identical, the verbose forms are non-idiomatic.

### Discussion
`LegacyArrayInitVisitor` detects empty initializer calls to `Array<T>()` and `Dictionary<K, V>()` with explicit generic arguments but no arguments. It also detects `Optional<T>.none` member accesses. `Set<T>()` is not flagged since it is already the shortest form.

This rule is opt-in because it is a pure style preference.

### Non-Violating Examples
```swift
// Shorthand syntax
let items: [String] = []
let map: [String: Int] = [:]
let nothing: String? = nil

// Array with arguments (not empty init)
let items = Array(repeating: 0, count: 10)

// Set — already shortest form
let unique = Set<String>()
```

### Violating Examples
```swift
// Verbose empty initializers
let items = Array<String>()
let map = Dictionary<String, Int>()
let nothing: Optional<String> = Optional<String>.none
```

---
