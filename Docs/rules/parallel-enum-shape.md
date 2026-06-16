[← Back to Rules](RULES.md)

## Parallel Enum Shape

**Identifier:** `Parallel Enum Shape`
**Category:** Architecture
**Severity:** Info *(opt-in)*

### Rationale
When two or more enums declare an identical set of case names — with no associated values
and no protocol tying them together — the codebase models one concept twice. Any code that
wants to treat them uniformly must convert between them by hand, and a case added to one is
silently missing from the other. Unifying them (one enum, or a shared protocol both conform
to) makes the relationship explicit and gives per-case behavior a single home.

This is the **structural twin of [Scattered Enum Mapping](scattered-enum-mapping.md)** and
the enum analogue of [Duplicate Struct Shape](duplicate-struct-shape.md): that rule finds a
missing abstraction over *types with the same stored-property core*; this one finds a missing
abstraction over *enums with the same case set*. The two enum rules compose — once a shared
protocol exists, it is the natural place to centralize the mapping that Scattered Enum Mapping
flags.

### Discussion
`ParallelEnumShapeVisitor` runs cross-file — the parallel enums usually live in different
files, so a single-file linter never sees them together.

**Phase 1 (walk).** It catalogs every `enum`, recording its case-name set, whether any case
has associated values, and its conformances — both from the enum's own inheritance clause and
from any separate `extension Foo: P {}` (collected by extended-type name and merged in Phase 2).
Enums with associated values, or with fewer than **3** cases, are skipped: an associated value
makes a case a constructor rather than a label, and two-case enums (`on`/`off`, `yes`/`no`)
coincide too often to be meaningful.

**Phase 2 (`finalizeAnalysis`).** Enums are clustered by *identical* case-name set. A cluster
of two or more fires, one issue per member, naming the peers and the shared cases.

A cluster is **suppressed when every member already shares a domain protocol** — they are
already unified, so there is nothing to suggest. Crucially, raw-value types and ubiquitous
standard protocols (`String`, `Int`, `CaseIterable`, `Equatable`, `Hashable`, `Codable`,
`Sendable`, …) do **not** count as a domain protocol: two enums both declared `: String,
CaseIterable` are not "already unified," so the rule still fires. Only a non-ubiquitous shared
conformance (a real domain protocol like `SeverityDisplaying`) suppresses it.

#### Known limitations / false-positive posture
- **Distinct domains can share case names** (`{north, south, east, west}` as both a compass
  and a wind direction). The rule cannot know intent; it is `Info` and opt-in. Suppress with
  `// swiftprojectlint:disable Parallel Enum Shape`.
- **Exact-set clustering only.** Two enums where one case set is a superset of the other are
  not currently clustered — the rule targets the high-signal "identical cases" case.
- **Conformance detection is by name**, covering both the enum's own inheritance clause and
  conformances added in a separate `extension Foo: P {}` (collected cross-file and merged in
  Phase 2). It does not resolve a protocol that is itself only reachable through a chain of
  refinements, and it keys on the extended type's simple name (so `extension Outer.Severity: P`
  is attributed to `Severity`).
- Nested enums are named by their simple name (`Severity`, not `ValidationResult.Severity`).

### Non-Violating Examples
```swift
// Already unified by a domain protocol — nothing to suggest.
protocol SeverityDisplaying { var color: Color { get } }

enum LogSeverity: SeverityDisplaying { case error, warning, info; var color: Color { .red } }
enum UISeverity: SeverityDisplaying  { case error, warning, info; var color: Color { .red } }
```

```swift
// Fewer than three cases — coincidental overlap, not flagged.
enum ToggleA { case on, off }
enum ToggleB { case on, off }
```

### Violating Examples
```swift
// The same concept modeled twice, with no shared protocol. One issue per enum.

// ConflictSeverity.swift
enum ConflictSeverity: String, CaseIterable { case error, info, warning }

// ValidationResult.swift
enum Severity: String, Equatable { case error, info, warning }
```

**Suggestion:** Consolidate the enums into one, or declare a shared protocol both conform to.
If the enums also map to UI values (colors, icons) by hand, that protocol is the natural home
for the centralized mapping — see [Scattered Enum Mapping](scattered-enum-mapping.md).

#### Real-world discovery
A manual protocol-usage review of the sibling project **SwiftCompilerFlagStudio** found
`ConflictSeverity` (`error`/`info`/`warning`) and `ValidationResult.Severity`
(`info`/`warning`/`error`) — the same three-case concept declared as two unrelated enums,
each switched over independently to produce the same colors and icons. Running this rule on
that project reports both enums as parallel, with a suggestion that dovetails with the
Scattered Enum Mapping findings on the duplicated color/icon switches.

---
