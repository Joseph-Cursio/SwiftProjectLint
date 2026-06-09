[← Back to Rules](RULES.md)

## Could Adopt Protocol

**Identifier:** `Could Adopt Protocol`
**Category:** Architecture
**Severity:** Info *(opt-in)*

### Rationale
When a concrete type declares every stored property a project protocol requires but does not
declare conformance, it has reinvented the protocol's shape by accident. Adopting the
existing protocol replaces an incidental structural match with an explicit one — the type
joins the others the abstraction already covers, and any generic code over the protocol
gains a new participant for free.

This is the inverse of [Duplicate Struct Shape](duplicate-struct-shape.md): there a shared
shape exists with *no* protocol to name it; here a matching protocol *already exists* and the
type simply hasn't adopted it.

### Discussion
`CouldAdoptProtocolVisitor` runs cross-file. It collects **property-only** protocols — those
whose every requirement is a property — recording each requirement as a
`(name, normalizedType, isOptional)` signature, and it collects concrete types with their
stored-property signatures and declared conformances (unwrapping isolated conformances such
as `: @MainActor P`). In `finalizeAnalysis`, a type is reported for protocol `P` when its
stored-property signatures are a **superset** of `P`'s requirements and it does not already
conform to `P`.

Constraints that keep the signal high:

- **Property-only protocols.** A protocol with any method, initializer, subscript, or
  associated-type requirement is excluded — structural matching on properties alone cannot
  confirm the type satisfies those, so suggesting adoption would be unsound.
- **At least three requirements.** Matching one or two properties (`id`, `name`) is
  coincidental; the threshold biases toward protocols specific enough that a full match is
  meaningful.
- **SwiftUI views skipped.** Types conforming to `View`/`ViewModifier` are excluded, matching
  [Duplicate Struct Shape](duplicate-struct-shape.md) — a view matching a data protocol's
  shape is almost always coincidental.

#### Known limitations
- Matching is by directly-declared requirements; requirements inherited from a refined
  protocol (especially a framework one) are not checked, so a type may be reported that
  satisfies the property shape but not an inherited non-property requirement.
- A coincidental match remains possible — two unrelated concepts can share a property set.
  The rule is `Info` and opt-in for this reason; suppress with
  `// swiftprojectlint:disable Could Adopt Protocol`.

### Non-Violating Examples
```swift
protocol Identity {
    var rawKey: String { get }
    var name: String { get }
    var category: String { get }
}

// Already conforms — nothing to suggest.
struct EffectiveSetting: Identity {
    let rawKey: String
    let name: String
    let category: String
}

// Missing `category` — not a full match.
struct PartialThing {
    let rawKey: String
    let name: String
}
```

### Violating Examples
```swift
protocol Identity {
    var rawKey: String { get }
    var name: String { get }
    var category: String { get }
}

// Has every required property but does not declare `: Identity`.
struct Widget {
    let rawKey: String
    let name: String
    let category: String
    let extra: Int
}
```

**Suggestion:** Declare `struct Widget: Identity` to reuse the existing abstraction instead
of relying on an incidental structural match.

---
