[← Back to Rules](RULES.md)

## Missing Documentation

**Identifier:** `Missing Documentation`
**Category:** Code Quality
**Severity:** Info

### Rationale
Public APIs without documentation comments force callers to read the implementation to understand how to use a type or function. Documentation comments attached to `public` declarations appear in Quick Help, improve searchability, and enable automated documentation generation.

### Discussion
`CodeQualityVisitor` checks for the presence of `///` doc-line-comment or `/** */` doc-block-comment trivia on the leading trivia of `public` struct, class, and function declarations. In the default configuration only `public` symbols are checked. In strict mode (`checkPublicAPIsOnly: false`) all functions are checked regardless of access level. The info severity reflects that internal documentation is valuable but not urgent.

**Protocol-required stubs are exempted.** Documentation for these
methods belongs at the protocol declaration site (Apple's stdlib
or SwiftSyntax), not at every conforming type — adopters writing a
boilerplate stub shouldn't have to copy the protocol's documentation
into their conformance. Currently exempted:

| Shape | Source protocol |
|-------|-----------------|
| `static func expansion(...)` | `Macro` / `PeerMacro` / `MemberMacro` / `ExtensionMacro` / `FreestandingMacro` (SwiftSyntax) |
| `func encode(to:)` | `Encodable` (Foundation) — single parameter with external label `to` |

Both shapes are receiver-gated to avoid silencing adopter methods
that coincidentally share a name. `static func expansion(...)` requires
the `static` modifier (matches the macro protocol family); a non-static
`expansion()` method still fires. `encode(to:)` requires the `to`
external parameter label; `encode(_:)` and other shapes still fire.

### Non-Violating Examples
```swift
/// Fetches the user profile for the given identifier.
///
/// - Parameter id: The user's unique identifier.
/// - Returns: The user profile, or nil if not found.
public func fetchProfile(id: String) -> UserProfile? { ... }
```

### Violating Examples
```swift
public func fetchProfile(id: String) -> UserProfile? { ... }
// No documentation comment above a public function
```

---
