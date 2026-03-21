[← Back to Rules](RULES.md)

## Public in App Target

**Identifier:** `Public in App Target`
**Category:** Code Quality
**Severity:** Info

### Rationale
In an app target (as opposed to a framework or library), no declaration needs `public` or `open` access. There are no external consumers — `internal` (the default) is sufficient. Unnecessary `public` modifiers widen the interface surface without benefit and can mislead readers into thinking the API is designed for external use.

### Discussion
`PublicInAppTargetVisitor` scans all declarations (types, functions, properties, initializers, protocols, typealiases) for `public` or `open` access modifiers and flags each one. The fix is simply to remove the modifier — the declaration becomes `internal` by default.

This rule is most useful for app targets. For framework/library targets where `public` is intentional, disable this rule via configuration.

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
