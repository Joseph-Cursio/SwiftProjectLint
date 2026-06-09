[← Back to Rules](RULES.md)

## Duplicate Struct Shape

**Identifier:** `Duplicate Struct Shape`
**Category:** Architecture
**Severity:** Info *(opt-in)*
**Status:** Proposed — not yet implemented

### Rationale
When several unrelated types declare the same cluster of stored properties — identical
name, type, and optionality — but share no protocol or base type, the codebase has an
*implicit* abstraction that the type system cannot see. Any code that wants to treat those
types uniformly (a search filter, a clipboard exporter, a logger, a sort comparator) must
be written once per type or must take the shared fields apart and pass them individually.
Extracting a protocol that names the shared shape makes the relationship explicit, unlocks
generic code over `any SharedProtocol`, and gives a single place to evolve the common
contract.

This rule fires on the *inverse* of the patterns caught by [Fat Protocol](fat-protocol.md),
[Single Implementation Protocol](single-implementation-protocol.md), and
[Mirror Protocol](mirror-protocol.md). Those three start from an existing protocol and ask
whether it earns its keep. This rule starts from the concrete types and asks whether a
*missing* protocol should exist. No other rule in the catalog detects an abstraction that
ought to be introduced — only abstractions that ought to be removed or narrowed.

### Discussion
`DuplicateStructShapeVisitor` uses cross-file analysis. SwiftLint cannot detect this pattern
because the duplicated declarations live in separate types, often in separate files, and a
single-file linter never sees more than one of them at a time. This is the same cross-file
niche that motivated [Related Duplicate State Variable](related-duplicate-state-variable.md).

The visitor proceeds in three passes:

1. **Fingerprint.** For every `struct`, `class`, and `enum` declaration, collect its stored
   properties as a set of `(name, normalizedType, isOptional)` triples. Computed properties
   (those with a `{ get }`-style accessor block and no stored backing), `static`/`class`
   members, and `lazy` members are excluded — the fingerprint describes instance *state*,
   not behavior or shared constants.

2. **Cluster.** Group types whose fingerprints share at least `minimumSharedProperties`
   members (default **4**). A pair qualifies only when the shared members are *identical* in
   name, type, and optionality — `description: String?` and `description: String` do not
   match. Two types may be clustered even if each also has unique properties of its own; the
   rule cares about the common core, not total equality.

3. **Filter and report.** A cluster is suppressed when the types *already* share the common
   core through an existing protocol or superclass that declares those members — the
   abstraction is present, so there is nothing to extract. Surviving clusters fire once,
   reported at the location of each participating type, naming the other members of the
   cluster and the shared property set.

#### Why a threshold of 4
Two or three shared fields are common by coincidence — countless value types carry
`id`/`name`, or `title`/`subtitle`. Requiring four identical members biases the rule toward
genuine structural twins and away from incidental overlap. The threshold is configurable so
teams can tune signal-to-noise for their codebase.

#### Configuration
The thresholds (`minimumShared` = 4, `minimumClusterSize` = 2) are currently compile-time
constants on `DuplicateStructShapeVisitor`, matching the hardcoded-threshold convention used
by the other Architecture visitors (`MirrorProtocol`'s 80%, `LawOfDemeter`'s chain depth).
Surfacing them as per-rule YAML keys is a planned follow-up:
```yaml
# Planned — not yet wired through LintConfigurationLoader
rules:
  "Duplicate Struct Shape":
    minimum_shared_properties: 4   # lower = more findings, more noise
    minimum_cluster_size: 2        # how many types must share the shape to fire
```

#### Known limitations and false positives
- **Deliberately separate types.** Some structurally-identical types are kept apart on
  purpose (a wire-format DTO vs. a domain model that happen to coincide today but evolve
  independently). The rule cannot know intent; it is `Info` severity and opt-in for exactly
  this reason. Suppress per-type with `// swiftprojectlint:disable Duplicate Struct Shape`.
- **Type aliases and generics.** `normalizedType` must canonicalize `Array<T>`/`[T]`,
  `Optional<T>`/`T?`, and resolve same-module type aliases, or near-twins will be missed.
- **Property order is irrelevant** — fingerprints are sets, so reordered declarations still
  cluster.

#### Real-world discovery
This rule was proposed after a manual review of a sibling project (SwiftCompilerFlagStudio)
found five model structs — `CompilerFlag`, `EffectiveSetting`, `SettingOverride`,
`DeprecatedSetting`, and `SettingDiff` — each declaring exactly `rawKey: String`,
`name: String`, `description: String?`, and `category: String` as its first four stored
properties, with no shared protocol. Neither SwiftLint nor PMD's copy-paste detector (CPD)
surfaced it: the declarations are not a contiguous duplicated token run, and the field names
sit among differing members (`id`, `source`, `diffType`). Only semantic, cross-file
shape-matching catches it — precisely the gap this rule fills.

### Non-Violating Examples
```swift
// The shared shape is already named by a protocol — nothing to extract.
protocol BuildSettingIdentity {
    var rawKey: String { get }
    var name: String { get }
    var description: String? { get }
    var category: String { get }
}

struct EffectiveSetting: BuildSettingIdentity {
    let rawKey: String
    let name: String
    let description: String?
    let category: String
    let value: String
}

struct SettingOverride: BuildSettingIdentity {
    let rawKey: String
    let name: String
    let description: String?
    let category: String
    let source: BuildSettingSource
}
```

```swift
// Only two fields in common (id, name) — below the default threshold of 4. No finding.
struct User {
    let id: UUID
    let name: String
    let email: String
}

struct Product {
    let id: UUID
    let name: String
    let price: Decimal
}
```

### Violating Examples
```swift
// Four identical stored properties (rawKey, name, description, category) repeated across
// five unrelated structs with no shared protocol. The rule fires on each, naming the others.
struct CompilerFlag {
    let id = UUID()
    let rawKey: String
    let name: String
    let description: String?
    let category: String
    let source: BuildSettingSource
}

struct EffectiveSetting {
    let rawKey: String
    let name: String
    let description: String?
    let category: String
    let value: String
}

struct SettingOverride {
    let rawKey: String
    let name: String
    let description: String?
    let category: String
    let source: BuildSettingSource
}

struct DeprecatedSetting {
    let rawKey: String
    let name: String
    let description: String?
    let category: String
    let currentValue: String
}

struct SettingDiff {
    let rawKey: String
    let name: String
    let description: String?
    let category: String
    let diffType: DiffType
}
```

**Suggestion:** Extract a protocol (e.g. `BuildSettingIdentity`) declaring the four shared
members and conform each struct to it. Stored properties need not change — the existing
declarations already satisfy the protocol.

---
