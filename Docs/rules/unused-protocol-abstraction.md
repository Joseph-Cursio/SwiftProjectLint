[← Back to Rules](RULES.md)

## Unused Protocol Abstraction

**Identifier:** `Unused Protocol Abstraction`
**Category:** Architecture
**Severity:** Info *(opt-in)*

### Rationale
A protocol earns its keep by being *used* — as a generic constraint, an existential
parameter, a return type, or a stored property type — so that code can operate on many
conforming types uniformly. A protocol that types *conform to* but that is never referenced
as a type is an abstraction in name only: it documents a shared shape but consolidates no
behavior. It is the mirror image of [Single Implementation Protocol](single-implementation-protocol.md)
(too few conformers) — here there may be many conformers, but no consumers.

This commonly arises right after extracting a protocol from a cluster of look-alike types
(see [Duplicate Struct Shape](duplicate-struct-shape.md)): the conformances are added, the
build goes green, but the generic code that justified the protocol is never written.

### Discussion
`UnusedProtocolAbstractionVisitor` runs cross-file. During the walk it records every
protocol declared in the analyzed sources, and classifies every type reference: a reference
inside the inheritance clause of a concrete type (struct/class/enum/actor) or an extension
is a *conformance* and bumps that protocol's conformer count; every other reference —
`any P`, `some P`, `<T: P>`, a parameter/property/return typed `P`, a cast, or a
`protocol Q: P` refinement — is a *use*. In `finalizeAnalysis`, a protocol with at least one
conformer and zero uses is reported at its declaration.

Only protocols declared in the analyzed sources are considered, so framework protocols
(`Identifiable`, `Codable`, `Hashable`, `View`) are never flagged — their "use" lives in
the framework. Conformances written with isolated-conformance syntax (`: @MainActor P`,
common under Swift 6 strict concurrency) are still counted, because the attributed type is
unwrapped to its base name.

Refinement and extension count as uses deliberately: a protocol that backs a refinement
hierarchy (`protocol Q: P`) or carries default implementations (`extension P { … }`) is
providing value even without a direct existential, so it is kept.

#### Known limitations
- **Cross-module blindness.** If the protocol is consumed by code in another module not
  included in the analysis, the rule cannot see that use and may report a false positive.
  This is why the rule is `Info` and opt-in.
- A protocol used *only* in a refinement chain that itself is unused is still considered
  used (the refinement counts), so a fully dead refinement hierarchy is not reported.

### Non-Violating Examples
```swift
// Used as a constraint — the abstraction does work.
protocol Identifiable2 { var id: String { get } }
struct Row: Identifiable2 { let id: String }
func indexed<T: Identifiable2>(_ items: [T]) -> [String: T] {
    Dictionary(uniqueKeysWithValues: items.map { ($0.id, $0) })
}
```

```swift
// Used as an existential.
protocol Exportable { var payload: Data { get } }
struct Report: Exportable { let payload: Data }
func write(_ value: any Exportable) { /* … */ }
```

### Violating Examples
```swift
// Five conformers, zero consumers — the protocol is never referenced as a type.
protocol BuildSettingIdentity: Identifiable {
    var rawKey: String { get }
    var name: String { get }
    var category: String { get }
}
struct CompilerFlag: BuildSettingIdentity { /* … */ }
struct EffectiveSetting: BuildSettingIdentity { /* … */ }
struct SettingOverride: BuildSettingIdentity { /* … */ }
struct DeprecatedSetting: BuildSettingIdentity { /* … */ }
struct SettingDiff: BuildSettingIdentity { /* … */ }
// No `any BuildSettingIdentity`, no `<T: BuildSettingIdentity>` anywhere.
```

**Suggestion:** Introduce a consumer — e.g. a generic `filter<T: BuildSettingIdentity>` or a
function taking `any BuildSettingIdentity` — to replace per-type duplication, or remove the
protocol if no shared behavior is actually needed.

---
