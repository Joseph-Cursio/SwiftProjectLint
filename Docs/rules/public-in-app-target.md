[← Back to Rules](RULES.md)

## Public in App Target

**Identifier:** `Public in App Target`
**Category:** Code Quality
**Severity:** Info

### Rationale
In an app target (as opposed to a framework or library), no declaration needs `public` or `open` access. There are no external consumers — `internal` (the default) is sufficient. Unnecessary `public` modifiers widen the interface surface without benefit and can mislead readers into thinking the API is designed for external use.

### Discussion
`PublicInAppTargetVisitor` scans all declarations (types, functions, properties, initializers, protocols, typealiases) for `public` or `open` access modifiers and flags each one. The fix is simply to remove the modifier — the declaration becomes `internal` by default.

This rule is most useful for single-target app projects. It is automatically suppressed in two cases:

- **Swift Packages** — if a `Package.swift` is detected at the project root, the rule is suppressed entirely. In a package, `public` is required for cross-target visibility between library and executable targets.
- **Test files** — files whose path contains `Test` or `Tests` are exempt. Test targets routinely use `public` for cross-module access (e.g., `@testable import`) and mock types, so flagging them produces only noise.

### Scope
- Flags any declaration with `public` or `open` access
- Checks structs, classes, enums, actors, protocols, functions, variables, initializers, and typealiases
- Does **not** flag `internal`, `fileprivate`, or `private` declarations

### Non-Violating Examples
```swift
// Default (internal) access — fine for app targets
struct UserProfile {
    let name: String
    func displayName() -> String { name }
}
```

### Violating Examples
```swift
// Unnecessary public access in an app target
public struct UserProfile {
    public let name: String
    public func displayName() -> String { name }
}
```

---
