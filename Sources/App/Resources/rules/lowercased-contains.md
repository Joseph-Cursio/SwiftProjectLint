[← Back to Rules](RULES.md)

## Lowercased Contains

**Identifier:** `Lowercased Contains`
**Category:** Code Quality
**Severity:** Warning

### Rationale
`.lowercased().contains(query)` is a naive approach to case-insensitive search. It ignores locale-specific rules, diacritics (e.g., "cafe" won't match "caf\u{00E9}"), and Unicode normalization. Apple provides `localizedStandardContains()` which handles all of these correctly and matches the behavior users expect from system search.

### Discussion
`LowercasedContainsVisitor` detects `.contains(...)` calls where the receiver is a `.lowercased()` or `.uppercased()` call with no arguments. This is the common pattern for hand-rolled case-insensitive search in filter closures.

The fix is straightforward — replace the chain with a single `localizedStandardContains()` call:

```swift
// Before
items.filter { $0.name.lowercased().contains(query.lowercased()) }

// After
items.filter { $0.name.localizedStandardContains(query) }
```

### Non-Violating Examples
```swift
// localizedStandardContains — correct API
items.filter { $0.localizedStandardContains(query) }

// Plain .contains() on a collection — not a string search
let hasItem = numbers.contains(42)

// .lowercased() used for something other than .contains()
let normalized = name.lowercased()
dictionary[normalized] = value

// .contains(where:) on a collection
items.contains(where: { $0.isActive })
```

### Violating Examples
```swift
// .lowercased().contains() — naive case-insensitive search
items.filter { $0.name.lowercased().contains(query) }

// .uppercased().contains() — same problem
names.filter { $0.uppercased().contains(search.uppercased()) }
```

---
