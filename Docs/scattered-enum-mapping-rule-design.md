# Rule Design: Scattered Enum Mapping (+ companion: Parallel Enum Shape)

**Status:** Both rules **implemented** — Rule 1
[`rules/scattered-enum-mapping.md`](rules/scattered-enum-mapping.md),
Rule 2 [`rules/parallel-enum-shape.md`](rules/parallel-enum-shape.md). Rule 2 ships
exact-set clustering only (the superset case noted below is deferred).
**Category:** Architecture
**Severity:** Info *(opt-in)*
**Proposed identifiers:** `Scattered Enum Mapping`, `Parallel Enum Shape`

## Origin

A manual protocol-usage review of the sibling project **SwiftCompilerFlagStudio**
surfaced a duplication that *no existing rule caught*: the same severity → UI
mapping was hand-written in four separate view files, keyed on two near-identical
severity enums.

- `ConflictSeverity` — cases `error`, `info`, `warning` (+ a `sortOrder` switch)
- `ValidationResult.Severity` — cases `info`, `warning`, `error`

…and the identical `error → .red / warning → .orange / info → .blue` color map
(plus the `xmark.circle.fill / exclamationmark.triangle.fill / info.circle.fill`
icon map) was copy-pasted across:

| File | Subject enum | Mapping |
|---|---|---|
| `Views/SeverityBadge.swift` | `ConflictSeverity` | → `Color` |
| `Views/SeverityHeader.swift` | `ConflictSeverity` | → `Color` + `String` (SF Symbol) |
| `Views/EditValidationSection.swift` | `ValidationResult.Severity` | → `Color` + `String` |
| `Views/SimulationIssuesList.swift` (extension) | `ValidationResult.Severity` | → `Color` + `String` |

`Duplicate Struct Shape` did not fire: it fingerprints **stored properties**, and
enums-without-associated-values have none — the duplication here is **behavioral**
(repeated `switch` arms returning literals), not structural. SwiftLint cannot see
it either: each `switch` is locally valid; only a cross-file view reveals that four
files implement one mapping. This is precisely the cross-file/behavioral gap the
two rules below fill.

---

## Rule 1 — Scattered Enum Mapping (primary)

### Rationale

When the same enum is exhaustively `switch`ed in several places and every arm
returns a literal/initializer of one uniform type, those switches are *one mapping*
copy-pasted. Centralizing it into a single computed property (or one extension on
the enum) gives the mapping a single source of truth: change "warning" from orange
to yellow in one place instead of N, and a newly-added case forces every consumer
to update via one exhaustiveness error rather than silently falling through scattered
`default`s.

This is the **behavioral analogue of `Duplicate Struct Shape`** (which detects a
missing *data* abstraction). It is also the inverse of nothing currently in the
catalog — no rule today detects a mapping that should be hoisted onto its type.

### Detection (two-phase, cross-file)

Implement as `ScatteredEnumMappingVisitor: CrossFileVisitorBase,
CrossFilePatternVisitorProtocol` (same base/finalize pattern as
`DuplicateStructShapeVisitor`).

**Phase 1 — walk each file:**

1. **Enum catalog.** On `EnumDeclSyntax`, record `name → Set<caseName>`, whether it
   has any associated values, and its declaration file/line. Used in Phase 2 to
   *name* the subject enum in the message and to power the Parallel-Enum companion.

2. **Enclosing-type / extension stack.** Track the nearest enclosing nominal type
   and `ExtensionDeclSyntax` (extended type name). This identifies a switch that
   lives *on the enum itself* — `var color: Color { switch self … }` inside `enum
   Severity` or `extension Severity` — which is the **centralized (good) form**, not
   a scattered copy.

3. **Mapping-switch collection.** On `SwitchExprSyntax`, record a `MappingSite` when
   **all** of these hold:
   - **≥ 3 explicit `case .label:` arms** whose patterns are leading-dot member
     accesses (`.error`, `.warning`, …). Two-arm switches are coincidental
     (on/off); 3+ biases toward specific enums. Capture `caseLabels: Set<String>`.
   - **Exhaustive-ish:** no `default:` arm, *or* a `default:` alongside ≥ 3 explicit
     case arms (covers the real pattern where one case folds into `default`).
   - **Every arm body is a single expression** (no statements/side effects) of a
     **uniform return kind** (see below). Mixed-kind arms ⇒ not a mapping ⇒ skip.
   - Record `MappingSite { caseLabels, returnKind, memberSet?, file, line,
     contextLabel, isCentralized }` where `isCentralized` is true when the switch's
     subject is `self` *and* the enclosing decl is the enum (or an `extension` of it).

#### Return-kind fingerprint (AST-only, no type resolution)

Per arm's single-expression body, classify into a coarse kind; require all arms in a
switch to agree:

| Arm expression | `returnKind` | Extra captured |
|---|---|---|
| `TypeName(...)` initializer (`Color(...)`, `Image(...)`, `UIColor(...)`) | `TypeName` | — |
| Qualified member `Color.red`, `Font.title` | `TypeName` | — |
| Bare leading-dot `.red`, `.orange` | `implicit-member` | `memberSet` = `{red, orange, blue}` |
| String literal | `String` | — |
| Integer / float literal | `Int` / `Double` | — |

Precision lever: for the **weak** `implicit-member` kind (can't tell `Color.red`
from `MyEnum.red` without types), Phase 2 additionally requires the **`memberSet`
to match across sites** — two switches over `{error,warning,info}` both returning
implicit members `{red,orange,blue}` is a strong duplicate even unresolved.

**Phase 2 — `finalizeAnalysis()`:**

4. **Group** mapping sites by key `(sortedCaseLabels, returnKind [, memberSet for
   implicit-member])`.
5. **Fire** a group when it has **≥ 3 sites across ≥ 2 distinct files** (the
   cross-file requirement is the whole point; a single file's two switches are often
   a view + its `#Preview`). Centralized sites do **not** count toward the scatter
   total but *do* change the message (below).
6. **Attribute the subject enum:** if exactly one catalogued enum's case-name set
   equals `sortedCaseLabels`, name it. If two+ enums match (the twin case), name
   them all and cross-reference Rule 2.
7. **Emit one Info issue per scattered site:**
   - *No centralized site in the group:*
     > `ConflictSeverity` is mapped to `Color` by hand in 4 places
     > (SeverityHeader.swift:45, EditValidationSection.swift:42, …). Extract the
     > mapping into a single computed property (e.g. `var displayColor: Color` in an
     > extension) and call it from each site.
   - *A centralized site exists:*
     > This re-implements the `ConflictSeverity → Color` mapping already defined as
     > `displayColor`; call that instead of re-switching.
   - *Twin enums detected:* append —
     > The same mapping is duplicated across two enums with identical cases
     > (`ConflictSeverity`, `ValidationResult.Severity`); consider unifying them or a
     > shared `SeverityDisplaying` protocol. See **Parallel Enum Shape**.

### Constraints that keep signal high (mirroring Duplicate Struct Shape's discipline)

- ≥ 3 case labels; ≥ 3 sites; ≥ 2 files.
- Single-expression, uniform-kind arms only.
- Switch-on-`self`-inside-the-enum counted as centralized, never as scatter.
- Skips are by AST shape, not type resolution — see limitations.

### Known limitations / false-positive posture

- **Name-keyed, not type-keyed.** Two unrelated enums sharing a 3+ case-name set and
  the same return kind would group. With ≥ 3 matching labels *and* matching return
  kind/`memberSet`, coincidence is low — but real. ⇒ `Info` + opt-in, suppressible
  with `// swiftprojectlint:disable Scattered Enum Mapping`.
- **`String` mappings are noisier** (many enums have legit per-site display strings;
  enums with a `String` rawValue already have `.rawValue`). First version may gate
  `returnKind == String` behind a config flag (default off) and ship `Color`/`Image`/
  `Font`/initializer kinds first.
- **Tuple/multi-type arms** are intentionally not uniform ⇒ never flagged.
- A switch whose subject is a non-enum (e.g. an `Int` range map) won't match the
  `.label` pattern requirement ⇒ not flagged.

---

## Rule 2 — Parallel Enum Shape (companion, secondary)

The **structural** twin: two enums whose case-name sets are identical (or one is a
≥ 3-case superset of the other), with associated values on neither, that do not both
refine a shared protocol. Reuses the Phase-1 enum catalog above — minimal extra
cost. Directly flags `ConflictSeverity` vs `ValidationResult.Severity`.

- **Fire:** ≥ 2 enums, shared case-name set of ≥ 3 labels, no associated values, no
  common protocol conformance.
- **Suggest:** consolidate into one enum, or, if they must stay distinct, introduce a
  shared protocol they both conform to (`SeverityDisplaying`) — which becomes the
  natural home for the mapping Rule 1 wants to centralize. The two rules compose:
  Rule 2 names the missing type, Rule 1 names the behavior to hang on it.
- **Posture:** `Info`, opt-in. Higher FP risk than Rule 1 (distinct domains can share
  case names: `{north,south,east,west}`), so it ships *second*, after Rule 1 proves
  out on real projects.

**Recommendation:** ship **Scattered Enum Mapping first** — it pinpoints concrete
duplicated code (high signal, clear fix), whereas Parallel Enum Shape is a softer
"consider consolidating." Rule 1 already surfaces the twin-enum insight in its
message, so Rule 2 is additive, not prerequisite.

---

## Implementation plan (integration points, verified against the codebase)

1. **`RuleIdentifier.swift`** (`Packages/SwiftProjectLintModels/…/RuleIdentifier.swift`)
   — add, near the other protocol/shape rules:
   ```swift
   case scatteredEnumMapping = "Scattered Enum Mapping"
   case parallelEnumShape   = "Parallel Enum Shape"
   ```
2. **Visitor** — `Architecture/Visitors/ScatteredEnumMappingVisitor.swift`, subclass
   `CrossFileVisitorBase` + `CrossFilePatternVisitorProtocol`; Phase-1 overrides
   `visit(EnumDeclSyntax)`, `visit(SwitchExprSyntax)`,
   `visit/visitPost(ExtensionDeclSyntax)` + enclosing-type stack; Phase-2
   `finalizeAnalysis()`. Model it directly on `DuplicateStructShapeVisitor`
   (collect → cluster → emit; `currentFilePath`, `getLineNumber(for:)`, `addIssue`).
3. **Registrar** — `Architecture/PatternRegistrars/ScatteredEnumMapping.swift`
   (`PatternRegistrarProtocol`, `severity: .info, category: .architecture`); register
   in `Architecture.swift`'s `registry.register(registrars: [ … ])` list.
4. **Opt-in** — add `.scatteredEnumMapping` (and later `.parallelEnumShape`) to
   `LintConfiguration.optInRules` (`SwiftProjectLintConfig/…/LintConfiguration.swift`),
   matching `.duplicateStructShape`'s posture.
5. **Thresholds** — compile-time constants on the visitor (`minLabels = 3`,
   `minSites = 3`, `minFiles = 2`), matching the hardcoded-threshold convention
   (`DuplicateStructShape.minimumShared`, `MirrorProtocol`'s 80%); note planned YAML.
6. **Tests** — `Tests/CoreTests/Architecture/ArchitectureScatteredEnumMappingTests.swift`:
   - **positive:** 3 cross-file switches over `{a,b,c}` → `Color` ⇒ one issue per site.
   - **negative:** centralized extension present (no scatter); < 3 sites; < 3 cases;
     non-uniform arm kinds; `default`-heavy switch; single-file duplicates only.
   - **message:** twin-enum note appears when two enums share the case set; centralized
     wording appears when a `var color` exists on the enum.
7. **Docs** — promote this file's Rule 1 into `Docs/rules/scattered-enum-mapping.md`
   (live format: Rationale / Discussion / Non-Violating / Violating), add a `RULES.md`
   row, and bump the Architecture rule count.

## Validation target

Once enabled on **SwiftCompilerFlagStudio**, the rule should report a `Color` mapping
group over case set `{error, info, warning}` spanning `SeverityBadge.swift`,
`SeverityHeader.swift`, `EditValidationSection.swift`, and `SimulationIssuesList.swift`
(4 sites, 4 files, no centralized form), plus an SF-Symbol `String`/`Image` mapping
group over the same case set across three of those files — with a twin-enum note for
`ConflictSeverity` / `ValidationResult.Severity`. That is exactly the duplication the
manual review found and the current catalog misses; it is the acceptance test for the
rule.
