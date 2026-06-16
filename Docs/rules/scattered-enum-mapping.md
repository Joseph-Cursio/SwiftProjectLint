[← Back to Rules](RULES.md)

## Scattered Enum Mapping

**Identifier:** `Scattered Enum Mapping`
**Category:** Architecture
**Severity:** Info *(opt-in)*

### Rationale
When the same enum is exhaustively `switch`ed in several places and every arm returns a
literal or initializer of one uniform type, those switches are *one mapping* copy-pasted.
Centralizing it into a single computed property (or one extension on the enum) gives the
mapping a single source of truth: change "warning" from orange to yellow in one place
instead of N, and a newly-added case forces every consumer to update through one
exhaustiveness error rather than slipping through scattered `default`s.

This is the **behavioral analogue of [Duplicate Struct Shape](duplicate-struct-shape.md)**.
That rule detects a missing *data* abstraction (types sharing a stored-property core with
no protocol); this one detects a missing *behavioral* abstraction (an enum→value mapping
that should live on the type). No other rule in the catalog detects duplicated behavior
keyed on an enum.

### Discussion
`ScatteredEnumMappingVisitor` runs cross-file — the duplicated switches live in separate
files, so a single-file linter never sees more than one at a time.

**Phase 1 (walk).** It catalogs every enum (`name → case-name set`) and collects *mapping
switches*. A `switch` qualifies when:

- It has **≥ 3** `case .label:` arms whose patterns are leading-dot enum constants
  (`.error`, `.warning`, …). Two-case switches map by coincidence; three biases toward
  specific enums. Value-binding or associated-value patterns (`.foo(let x)`) disqualify it.
- **Every arm body is a single expression** (`return .red` or the implicit-return
  switch-expression form `.red`) — no multi-statement or side-effecting arms.
- **Every arm has the same return kind.** Kinds are classified without type resolution:
  a named initializer/factory (`Color(...)`, `Image(...)`) or qualified member
  (`Color.red`) keys on the type name; a string/number literal keys on `String`/`Int`/
  `Double`; a bare leading-dot member (`.red`) keys on `implicit-member` and additionally
  records the member name. Mixed kinds disqualify the switch.

**Phase 2 (`finalizeAnalysis`).** Sites are grouped by `(case-label set, return kind)` —
and, for the `implicit-member` kind, by the member set too, so two switches over the same
cases returning `.red/.orange/.blue` are matched even unresolved. A group fires when it has
**≥ 3 scattered sites across ≥ 2 files**.

A `switch self` inside the enum (or an `extension` of it) whose label set equals the enum's
cases is the **centralized (good) form** — it is never counted as scatter. Its presence only
changes the message: instead of "extract a mapping," the rule reports that the other sites
**re-implement** a mapping that already exists and should call it.

When two or more catalogued enums share the firing case set (e.g. a project with both
`ConflictSeverity` and a nested `ValidationResult.Severity`, both `error/warning/info`), the
suggestion adds a note to consider unifying them or introducing a shared protocol — the
natural home for the centralized mapping.

#### Known limitations / false-positive posture
- **Name-keyed, not type-keyed.** Two unrelated enums sharing a 3+ case-name set and the
  same return kind would group. With ≥ 3 matching labels plus a matching return kind/member
  set, coincidence is low — but possible. The rule is `Info` and opt-in; suppress with
  `// swiftprojectlint:disable Scattered Enum Mapping`.
- **`String` mappings are noisier** than typed ones (display strings legitimately vary per
  site; a `String`-rawValue enum already has `.rawValue`).
- **Nested enums are named by their simple name** (`Severity`, not `ValidationResult.Severity`)
  because the catalog keys on the declared name.
- Thresholds (3 labels / 3 sites / 2 files) are compile-time constants; per-rule YAML is a
  planned follow-up, matching the other Architecture cross-file rules.

### Non-Violating Examples
```swift
// Centralized once on the type — every consumer calls `severity.color`. Nothing to flag.
enum Severity { case error, warning, info }

extension Severity {
    var color: Color {
        switch self {
        case .error:   return .red
        case .warning: return .orange
        case .info:    return .blue
        }
    }
}

struct Badge {
    let severity: Severity
    var body: some View { Circle().fill(severity.color) }   // reuses the single mapping
}
```

### Violating Examples
```swift
// The same Severity → Color mapping hand-written in three different files, with no
// computed property on the enum. The rule fires on each site, naming the peers.

// Badge.swift
func badgeColor(_ s: Severity) -> Color {
    switch s {
    case .error:   return .red
    case .warning: return .orange
    case .info:    return .blue
    }
}

// Header.swift
func headerColor(_ s: Severity) -> Color {
    switch s {
    case .error:   return .red
    case .warning: return .orange
    case .info:    return .blue
    }
}

// IssueRow.swift
func rowColor(_ s: Severity) -> Color {
    switch s {
    case .error:   return .red
    case .warning: return .orange
    case .info:    return .blue
    }
}
```

**Suggestion:** Move the mapping into a single `var color: Color` on `Severity` (or an
extension) and call it from each site. If a centralized mapping already exists elsewhere,
call it instead of re-switching.

#### Real-world discovery
A manual protocol-usage review of the sibling project **SwiftCompilerFlagStudio** found the
`error/warning/info` → `Color` mapping re-implemented in `SeverityBadge`, `SeverityHeader`,
and `EditValidationSection`, while `SimulationIssuesList` already defined the same mapping as
`var issueColor` in an `extension ValidationResult.Severity`. Neither SwiftLint (single-file)
nor `Duplicate Struct Shape` (stored-property shapes only; enums have none) surfaced it. This
rule reports the three scattered copies as re-implementations of the existing centralized
mapping, with a note that `ConflictSeverity` and `ValidationResult.Severity` are twin enums.

---
