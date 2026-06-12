[← Back to Rules](RULES.md)

## Unused Protocol Abstraction

**Identifier:** `Unused Protocol Abstraction`
**Category:** Architecture
**Severity:** Info

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

Matching is scoped by visibility. A `private`/`fileprivate` protocol is invisible outside
its declaring file, so only conformers and uses **in that same file** are credited to it —
a same-named, unrelated type referenced in another file can no longer mask it (a false
negative the earlier name-global matching allowed). `internal` and `public` protocols stay
name-global: AST-only analysis can't resolve modules, and within one module a same-named
reference plausibly *is* the protocol, so crediting it is the safe choice.

#### Scope gating
The rule is on by default, but it only fires when the analysis scope is **complete** — i.e.
every potential consumer of a protocol is in scope. Concretely:

- **Single-package / single-target projects** — always complete; the rule runs.
- **Whole-project runs** (`--include-nested-packages`) — every first-party package is pulled
  in, so the rule runs.
- **A project with first-party nested packages run *without* `--include-nested-packages`** —
  those packages are excluded, so a protocol declared in one of them (or in the root) and
  consumed only in an excluded sibling would be falsely flagged. The rule **auto-suppresses
  itself** for the whole run in this case rather than emit unreliable findings.

Run with `--include-nested-packages` to lint a multi-package project as one unit and keep the
rule active across the boundary.

#### Known limitations
- **Cross-module blindness.** The gating above relies on detecting excluded first-party
  packages from the project root. If the tool is pointed *directly* at a sub-package of a
  larger workspace, it cannot know an external consumer exists and may report a false
  positive — lint the workspace root instead. This residual uncertainty is why the rule's
  severity is `Info` rather than `Warning`.
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
