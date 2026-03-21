[← Back to Rules](RULES.md)

## Protocol Could Be Private

**Identifier:** `Protocol Could Be Private`
**Category:** Code Quality
**Severity:** Info

### Rationale
Protocols with default (`internal`) access that are only conformed to and referenced within their declaring file have a wider scope than necessary. Narrowing them to `private` makes the codebase easier to reason about — readers know the protocol is an implementation detail, not a public contract.

### Discussion
This is a **cross-file rule**. It scans all project files in two phases:

1. **Collection phase:** Records all protocol declarations without explicit access modifiers, and tracks every reference to protocol names (inheritance clauses, type annotations, generic constraints, identifier expressions).
2. **Analysis phase:** Flags protocols whose name does not appear in any file other than the one where they are declared.

Note: protocols defined for testability (e.g., `ServiceProtocol` with a mock in test files) may be flagged because test files are excluded from the scan. These are intentional false positives — the protocol is `internal` so test targets can conform to it.

### Scope
- Flags `internal` (default access) protocols only referenced in their declaring file
- Does **not** flag protocols with explicit access modifiers (`private`, `fileprivate`, `public`, `open`, `internal`)
- Does **not** flag protocols in test files

### See Also
For more thorough access-level analysis with full type resolution, consider [Periphery](https://github.com/peripheryapp/periphery). It uses SourceKit's build index to precisely track protocol conformances across targets including test targets.

### Non-Violating Examples
```swift
// File: Protocols.swift
protocol Loadable { func load() }

// File: Service.swift
struct DataService: Loadable {  // cross-file conformance
    func load() { }
}
```

### Violating Examples
```swift
// File: Service.swift
protocol Loadable { func load() }  // only conformed to below

struct DataService: Loadable {
    func load() { }
}
```

---
