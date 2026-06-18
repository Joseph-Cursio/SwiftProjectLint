[← Back to Rules](RULES.md)

## Shared Domain-Enum Field

**Identifier:** `Shared Domain-Enum Field`
**Category:** Architecture
**Severity:** Info *(opt-in)*

### Rationale
A project-declared enum is a *domain axis* — `IssueSeverity`, `LoadState`, `RiskLevel`. When
three or more unrelated types each carry the same enum as a stored field under the same name,
but share no protocol, the codebase has an implicit relationship the type system cannot see.
Any behavior keyed on that axis — sorting by severity, filtering to errors, grouping by state
— must be re-written for each type, and the convention drifts as one copy is updated and the
others are not. Extracting a marker protocol (`protocol SeverityRanked { var severity:
IssueSeverity { get } }`) makes the axis explicit and gives that behavior a single home as an
extension on `Sequence where Element: SeverityRanked`.

This is the behavioral sibling of [Duplicate Struct Shape](duplicate-struct-shape.md). That
rule needs a *wide* shared shape (four identical fields by default) to fire, because generic
field names overlap by coincidence. This rule fires on a *single* shared field — which is only
safe because the field's type is a project-declared enum, a far stronger signal than one more
`id: UUID` or `name: String`.

### Discussion
`SharedDomainEnumFieldVisitor` uses cross-file analysis: the clustered types and the enum they
share usually live in separate files, so a single-file linter never sees the relationship.

The visitor proceeds in two phases:

1. **Collect.** Record every project enum declaration, every protocol's property-requirement
   names, and — for each `struct`/`class`/`actor` — its stored instance properties as
   `(name, type)` pairs plus its declared conformances. Computed, `static`/`class`, and `lazy`
   properties are excluded: the rule describes instance *state*, not behavior or constants.

2. **Cluster and report.** Keep only fields whose type is a project-declared enum, then group
   types by the `(propertyName, enumType)` signature. A cluster with at least
   `minimumCluster` (default **3**) types fires once per participating type, naming the peers
   and the shared field. A type that already conforms to a protocol declaring that property is
   dropped first — the abstraction is present, so there is nothing to extract; if that drops
   the cluster below threshold, nothing is reported.

#### The project-enum requirement is the false-positive guard
Lowering Duplicate Struct Shape's threshold to one field would drown in noise: nearly every
value type shares `id`, `name`, or an `isEnabled: Bool`. This rule sidesteps that by only
counting fields whose type is an enum *declared in the analyzed sources*. Framework enums and
primitives (`String`, `Int`, `Bool`, `UUID`) never qualify, so a shared `id: String` across
three types is ignored — only a shared *domain* axis fires.

#### Why same name and same type
The suggestion is a single protocol requirement, `var <name>: <Enum> { get }`. Three types
that hold `IssueSeverity` under different names (`severity`, `level`, `rank`) cannot satisfy
one requirement without a rename, so they do not cluster. The key is the pair, not the enum
alone.

#### Known limitations
- **v1 matches the bare, non-optional enum field.** `severity: IssueSeverity` clusters;
  `severity: IssueSeverity?` and `[IssueSeverity]` do not. An optional or boxed enum is a
  weaker domain-axis signal and complicates the suggested requirement, so it is left out for
  now.
- **Nested types report by simple name.** A nested `ValidationResult.Issue` is reported as
  `Issue`. Suppress per-type with `// swiftprojectlint:disable Shared Domain-Enum Field`.
- **Deliberately separate types.** Two types may share a domain enum yet be kept apart on
  purpose; the rule is `Info` and opt-in for that reason.

#### Real-world discovery
Proposed after a review of a sibling project (SwiftCompilerFlagStudio) found `SettingConflict`,
`SimulationIssue`, and `ValidationResult.Issue` each declaring `severity: IssueSeverity` with
no common protocol — and the sort-by-severity / "any error?" logic duplicated across them.
Duplicate Struct Shape stays silent (the types share only that one field); only the
project-enum signal makes the cluster meaningful.

### Non-Violating Examples
```swift
// The shared axis is already named by a protocol — nothing to extract.
enum IssueSeverity { case error, warning, info }
protocol SeverityRanked { var severity: IssueSeverity { get } }

struct SettingConflict: SeverityRanked { let severity: IssueSeverity; let title: String }
struct SimulationIssue: SeverityRanked { let severity: IssueSeverity; let message: String }
struct ValidationIssue: SeverityRanked { let severity: IssueSeverity; let detail: String }
```

```swift
// Shared field is a primitive, not a project enum — not a domain axis. No finding.
struct Alpha { let id: String }
struct Beta  { let id: String }
struct Gamma { let id: String }
```

### Violating Examples
```swift
// Three unrelated types carry the same project-enum field (severity: IssueSeverity) with no
// shared protocol. The rule fires on each, naming the others.
enum IssueSeverity { case error, warning, info }

struct SettingConflict {
    let severity: IssueSeverity
    let title: String
}

struct SimulationIssue {
    let severity: IssueSeverity
    let message: String
}

struct ValidationIssue {
    let severity: IssueSeverity
    let detail: String
}
```

**Suggestion:** Extract a protocol (e.g. `SeverityRanked`) declaring `var severity:
IssueSeverity { get }` and conform each type to it, so sorting, filtering, and grouping keyed
on `IssueSeverity` are written once over `Sequence where Element: SeverityRanked`.

---
