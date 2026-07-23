[← Back to Rules](RULES.md)

## Parallel Enum Shape

**Identifier:** `Parallel Enum Shape`
**Category:** Architecture
**Severity:** Info *(opt-in)*

### Rationale
When two or more **name lists** are identical — the same set of names declared in two places —
the codebase states one concept twice. Nothing is broken while they agree, which is exactly why
this is worth reporting: it is the cheap moment to consolidate, before an entry is added to one
and not the other and the divergence becomes a bug.

Two carriers count as a name list:

- an **enum**'s case names (associated-value-free), where a second copy also means any code
  wanting to treat them uniformly must convert by hand; and
- an **array or set literal** whose elements are uniformly name-like.

This is the **structural twin of [Scattered Enum Mapping](scattered-enum-mapping.md)** and the
analogue of [Duplicate Struct Shape](duplicate-struct-shape.md): that rule finds a missing
abstraction over *types with the same stored-property core*; this one finds a missing
abstraction over *lists with the same members*. The enum rules compose — once a shared protocol
exists, it is the natural place to centralize the mapping that Scattered Enum Mapping flags.

Together with [Parallel List Drift](parallel-list-drift.md) this covers both halves of the
same hazard:

| | lists agree exactly | lists nearly agree |
|---|---|---|
| **enums** | **Parallel Enum Shape** | Parallel List Drift |
| **arrays / sets** | **Parallel Enum Shape** | Parallel List Drift |

The array carrier closes what was a genuine gap. Parallel List Drift deliberately ignores
similarity 1.0 — that is agreement, not drift — and no other rule looked at literal lists, so
two byte-identical hand-maintained lists were invisible to the entire suite until the day
someone edited one of them.

### Discussion
`ParallelEnumShapeVisitor` runs cross-file — the parallel enums usually live in different
files, so a single-file linter never sees them together.

**Phase 1 (walk).** It catalogs every `enum`, recording its case-name set, whether any case
has associated values, and its conformances — both from the enum's own inheritance clause and
from any separate `extension Foo: P {}` (collected by extended-type name and merged in Phase 2).
Enums with associated values, or with fewer than **3** cases, are skipped: an associated value
makes a case a constructor rather than a label, and two-case enums (`on`/`off`, `yes`/`no`)
coincide too often to be meaningful.

It also catalogs every **array or set literal** whose elements are uniformly name-like — single
segment string literals, leading-dot members, or type references. A mixed array is a data
structure, not a list of names, and is skipped. Two thresholds differ from the enum carrier:

- The floor is **5** entries, not 3. Short literal arrays coincide far more readily than enums
  do; `["a", "b", "c"]` is not a concept.
- **Test and fixture files are excluded** for this carrier. A test restating a production list
  verbatim is the expected shape there, not a duplication to fix. Enums keep their original
  behaviour, so the rule's established findings do not move.

Names are **normalized** before clustering — lowercased with separators stripped — so
`UIPatterns`, `uiPatterns` and `"ui-patterns"` compare equal, and an enum can cluster with an
array that spells its cases differently. Messages quote the original spelling.

**Phase 2 (`finalizeAnalysis`).** Lists are clustered by *identical* normalized name set. A
cluster of two or more fires, one issue per member, naming the peers and the shared names.

Peers are identified **by location, not by name**, and reported as `` `name` (File.swift:line) ``.
This matters more than it sounds: when two copies share a name — two `FilterType` enums, or two
`expensiveOperations` arrays — filtering peers by name produced an empty list, in exactly the
case where the reader most needs to be told where the other copy is.

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
- **Exact-set clustering only.** Two lists where one is a superset of the other are not
  clustered here — that is [Parallel List Drift](parallel-list-drift.md)'s finding, and it
  carries the more urgent message because the divergence has already happened.
- **A literal list has no conformances**, so the shared-protocol suppression below can never
  apply to the array carrier. Two identical arrays always report.
- **Array clustering ignores the surrounding type.** Two identical private arrays in unrelated
  visitors are reported the same as two that genuinely want a shared home; the rule cannot tell
  whether consolidating them would couple things that should stay apart.
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

```swift
// Fewer than five array entries — literal lists coincide too easily to report.
let a = ["one", "two", "three", "four"]
let b = ["one", "two", "three", "four"]
```

```swift
// Not identical — one entry differs. That is Parallel List Drift's finding.
let a = ["Mock", "Fake", "Stub", "Spy", "Dummy"]
let b = ["Mock", "Fake", "Stub", "Spy", "Phony"]
```

### Violating Examples
```swift
// The same concept modeled twice, with no shared protocol. One issue per enum.

// ConflictSeverity.swift
enum ConflictSeverity: String, CaseIterable { case error, info, warning }

// ValidationResult.swift
enum Severity: String, Equatable { case error, info, warning }
```

```swift
// The same list maintained in two visitors. One issue per copy, each naming the other's location.

// ConcreteTypeUsageVisitor.swift
private static let mockSuffixes: Set<String> = ["Mock", "Fake", "Stub", "Spy", "Dummy"]

// ProtocolExemption.swift
private static let mockMarkers: Set<String> = ["Mock", "Fake", "Stub", "Spy", "Dummy"]
```

**Suggestion:** For enums, consolidate into one or declare a shared protocol both conform to.
If the enums also map to UI values (colors, icons) by hand, that protocol is the natural home
for the centralized mapping — see [Scattered Enum Mapping](scattered-enum-mapping.md). For
literal lists, declare the list once and reference the single copy.

#### Real-world discovery
A manual protocol-usage review of the sibling project **SwiftCompilerFlagStudio** found
`ConflictSeverity` (`error`/`info`/`warning`) and `ValidationResult.Severity`
(`info`/`warning`/`error`) — the same three-case concept declared as two unrelated enums,
each switched over independently to produce the same colors and icons. Running this rule on
that project reports both enums as parallel, with a suggestion that dovetails with the
Scattered Enum Mapping findings on the duplicated color/icon switches.

The **array carrier** came from dogfooding [Parallel List Drift](parallel-list-drift.md) on
SwiftProjectLint itself. That run reported `primitiveCarriers` in two visitors against a *third*
list, which prompted the question of why the two copies of `primitiveCarriers` — byte-identical,
all 20 entries — were not themselves reported. They could not be: drift excludes similarity 1.0,
and nothing else read literal lists.

Adding the carrier found **five duplicated pairs** on this repository, every one of them a
genuine copy rather than a coincidence:

| List | Copies |
|---|---|
| `primitiveCarriers` | `PrimitiveBypassingDomainTypeVisitor`, `PrimitiveNamedForDomainTypeVisitor` |
| `osLogMethods` / `loggerLevelMethods` | `LoggingSensitiveDataVisitor`, `HeuristicEffectInferrer` |
| `calleeNames` / `escapingCalleeNames` | `EscapingClosurePolicy`, `ContextSymbolTable` |
| `mockSuffixes` / `mockMarkers` | `ConcreteTypeUsageVisitor`, `ProtocolExemption` |
| `expensiveOperations` | `CustomModifierPerformanceVisitor`, `PerformanceVisitor` |

The precision contrast with its sibling is instructive. Parallel List Drift's 14 findings on the
same codebase were mostly deliberate subsets — roughly three actionable out of ten distinct
pairs — because "these lists nearly agree" has an innocent explanation. "These lists agree
exactly" has far fewer: all five pairs here were real.

---
