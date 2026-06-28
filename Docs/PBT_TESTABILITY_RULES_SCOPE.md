# Scope: Testability / PBT-Readiness Rules for SwiftProjectLint

_Date: 2026-06-27 · Implements Idea #1 from `~/xcode_projects/PBT_ECOSYSTEM_REVIEW.md`_

> **Status (2026-06-28): core shipped.** The `.testability` category and its three
> purely-syntactic Tier-A rules are on `main`, each with bundled docs and tests:
> - **Global Mutable State** (warning) — PR #36
> - **Non-Injected Nondeterminism** (warning) — PR #39 (orig. #37)
> - **Pure Function Property-Test Candidate** (info) — PR #40 (orig. #38), the keystone seed producer
>
> The seed handoff to `swift-infer` (Idea #2) is shipped: `--format pbt-seeds` emits a
> `{file,line,symbol,rule}` manifest from PureFunctionCandidate findings, consumed by
> `swift-infer discover --seeds`. Remaining optional Tier-A/B rules below are **not yet
> built**: Unabstracted I/O, Missing Equatable on State Type, Impure Call in View Body.

## Goal

Turn SwiftProjectLint from "linter that drives idempotency" into "linter that tells a
developer **why their code is hard to property-test and how to refactor it**." Concretely:
ship a coherent set of rules under a new `.testability` category, ending with a
machine-readable handoff that seeds `swift-infer discover` (Idea #2).

The thesis rule is **PureFunctionCandidate** (Rule 5): the positive signal that says
"this function is now pure + total + Equatable — go property-test it." Everything else
either removes a blocker to that state or feeds the same pipeline.

---

## Architecture decisions

### New category: `.testability`
Add one case to `PatternCategory`
(`Packages/SwiftProjectLintModels/Sources/SwiftProjectLintModels/PatternCategory.swift`,
the enum at lines 24–36):

```swift
case testability
```

Each new `RuleIdentifier` case maps to `.testability` in the `category` switch
(`RuleIdentifier.swift` lines 231–248 region). This is free in the JSON output —
`CodableLintIssue.category` is already `String(describing: ruleName.category)`, so
consumers can filter `category == "testability"` immediately.

### Two tiers by dependency → two implementation homes

| Tier | Needs SwiftEffectInference? | Home |
|------|------|------|
| **A — purely syntactic** (Rules 1–4) | No | New `Testability/` group in `SwiftProjectLintRules` (main rules package) |
| **B — effect-aware** (Rules 5–6) | Yes (`EffectSymbolTable`, `HeuristicEffectInferrer`, `UpwardEffectInferrer`) | Beside the idempotency rules, which already wire SEI: `SwiftProjectLintIdempotencyRules` (or a sibling `SwiftProjectLintTestabilityRules` package that depends on `SwiftProjectLintVisitors`) |

Rationale: only Tier B needs the effect machinery (which lives in
`SwiftProjectLintVisitors` + `SwiftProjectLintIdempotencyRules`, both already pinned to
SEI revision `6722e260…`). Keeping Tier A out of that dependency keeps the cheap rules
cheap. This mirrors the existing split where idempotency rules are their own package.

### Per-rule authoring recipe (verified against current conventions)
1. Add `case x = "Display Name"` to `RuleIdentifier`; add `x` to the `.testability` arm of the `category` switch.
2. Visitor: subclass `BasePatternVisitor`, override the relevant `visit(_:)`, call `addIssue(...)`. (Template: `Architecture/Visitors/SingletonUsageVisitor.swift`.)
3. Registrar: `struct X: PatternRegistrarProtocol { var pattern: SyntaxPattern { … } }`. (Template: `CodeQuality/PatternRegistrars/ForceTry.swift`.)
4. Wire it into the category registrar's `registry.register(registrars: [ … ])` list, or, for a new package, add a `BasePatternRegistrar` subclass + a `SourcePatternRegistry.registerFactory { … }` in `BuiltInRules.swift`.

`addIssue` direct form (custom message), from `BasePatternVisitor.swift:266`:
```swift
addIssue(severity: .warning, message: "…", filePath: getFilePath(for: Syntax(node)),
         lineNumber: getLineNumber(for: Syntax(node)), suggestion: "…", ruleName: .x)
```

---

## Rule catalog

### Tier A — purely syntactic (Phase 1)

#### Rule 1 — Non-Injected Nondeterminism  `.nonInjectedNondeterminism`
- **Category/severity:** `.testability` / `.warning` (start `.info` to gauge noise).
- **What:** flag a nondeterministic *source* called inline in logic when it is **not injected**.
- **Source set** (broader than the existing modernization rules): `Date()`, `Date.now`,
  `UUID()`, `Int/Double/Bool/Float.random(in:)`, `.randomElement()`, `.shuffled()`,
  `arc4random*`, `CFAbsoluteTimeGetCurrent()`, `DispatchTime.now()`, `ContinuousClock().now`
  used inline, `Locale.current`, `TimeZone.current`, `ProcessInfo.processInfo.environment`.
- **"Not injected" heuristic:** the call is inside a function/computed-property body and is
  **not** in a parameter default-value position. Reuse the parent-walk from
  `SingletonUsageVisitor.isParameterDefaultValue` (stops at `ClosureExprSyntax`/`CodeBlockSyntax`,
  matches `FunctionParameterSyntax`). Exempt test/fixture files via `isTestOrFixtureFile()`
  exactly as the singleton rule does.
- **Suggestion:** "Inject a clock / UUID / RNG provider (e.g. `() -> Date`, `RandomNumberGenerator`) so this value is controllable in tests."
- **Overlap to settle:** `DateNowVisitor` (`.dateNow`), `LegacyRandomVisitor` (`.legacyRandom`),
  `CFAbsoluteTimeVisitor` (`.cfAbsoluteTime`) already fire `.info` on a subset. Decision (open):
  let this rule co-fire (different category/framing) **or** scope it to the sources those
  rules *don't* cover (UUID, `.random(in:)`, `Locale.current`, …) to avoid duplicate
  diagnostics on the same token. Recommendation: co-fire is fine — the framing differs and
  users can disable per-rule — but exclude the exact `Date()` zero-arg token to avoid two
  findings on one node.
- **Effort:** S–M. Single `FunctionCallExprSyntax` / `MemberAccessExprSyntax` visitor.

#### Rule 2 — Global Mutable State  `.globalMutableState`
- **Category/severity:** `.testability` / `.warning`.
- **What:** flag stored mutable global state: top-level `var` declarations and `static var`
  stored properties on types. These defeat PBT isolation (properties can't reset them).
- **Detection:** visit `VariableDeclSyntax`; require `bindingSpecifier.text == "var"`, a
  binding with **no accessor block** (stored, not computed), and either parent is
  `SourceFileSyntax` (top-level) or the decl carries the `static` modifier inside a type body.
  Exempt `let`, computed `var`, SwiftUI property wrappers (`@State`/`@StateObject`/…), and
  test files.
- **Suggestion:** "Move mutable state behind an injected, instance-scoped owner; globals can't be reset between property-test runs."
- **Effort:** S.

#### Rule 3 — Unabstracted I/O Dependency  `.unabstractedIODependency` *(extend existing)*
- **Note:** Architecture already registers `UnabstractedFileIO()`. **Audit it first** — it may
  already cover `FileManager`. Scope here = extend coverage to concrete `URLSession`,
  `UserDefaults`, `FileManager` appearing as **parameter types or stored-property types**
  (not behind a protocol), suggesting a protocol seam.
- **Category/severity:** `.testability` (or keep `.architecture`) / `.warning`.
- **Detection:** visit `FunctionParameterSyntax` and stored `VariableDeclSyntax`; match the
  concrete type names; skip if the declared type is a protocol (heuristic: known protocol
  suffixes or a project-collected protocol set).
- **Effort:** S if extending `UnabstractedFileIO`; M if new.

### Tier A — cross-file (Phase 1.5)

#### Rule 4 — Missing Equatable on State Value Type  `.missingEquatableOnStateType`
- **Category/severity:** `.testability` (or `.stateManagement`) / `.info`.
- **Why it matters most for the pipeline:** every value type made `Equatable` becomes a
  direct **SwiftPropertyLaws** target and unlocks PBT shrinking/assertions.
- **What:** flag a value type used in `@State`/`@Published`/`@Binding` (or returned from a
  candidate-pure function) that has no `Equatable`/`Hashable` conformance found in the project.
- **Detection:** needs project-wide knowledge → use `CrossFileAnalysisEngine`. Pass 1: collect
  `struct`/`enum` decls and whether they declare `Equatable`/`Hashable` (including
  `@PropertyLawSuite`-style derivations). Pass 2: collect state-var types. Flag the gap.
- **Limitation (document):** can't see conformances declared in other modules; info-severity
  keeps false positives low-cost.
- **Effort:** M.

### Tier B — effect-aware (Phase 2)

#### Rule 5 — Pure Function · Property-Test Candidate  `.pureFunctionCandidate`  ⭐ thesis rule
- **Category/severity:** `.testability` / `.info`, **opt-in** (off by default to avoid noise).
- **What (positive signal):** "This function looks pure, total, and Equatable-typed — a good
  property-based-testing candidate."
- **Detection is a composition** (no single tier suffices — SEI has no `pure` tier):
  1. Inferred effect ≤ `.observational` via `EffectSymbolTable` / `HeuristicEffectInferrer` /
     `UpwardEffectInferrer` (same path `IdempotencyViolationVisitor` uses).
  2. **No** nondeterministic source in the body (reuse Rule 1's detector — observational still
     permits clock/RNG reads, which disqualify a PBT candidate).
  3. **Total:** no `try!`, force-unwrap `!`, `as!`, `fatalError`/`precondition`.
  4. All parameter types + return type are `Equatable`-or-primitive (reuse Rule 4's project
     conformance index).
- **Suggestion:** "Run `swift-infer discover` on this function, or add a `PropertyLawKit` test."
- **This is the Idea #2 seam** — these findings are the seed list. See Handoff below.
- **Effort:** L (composes four analyses + project index).

#### Rule 6 — Impure Call in View Body  `.impureCallInViewBody`
- **Category/severity:** `.testability` (or `.performance`) / `.warning`.
- **What:** inside a SwiftUI `var body` / `@ViewBuilder`, flag calls to functions inferred
  non-observational (writes / non-idempotent) or to nondeterministic sources — these make the
  view untestable and re-render nondeterministic.
- **Detection:** reuse the body-detection from `Performance/Visitors` (`expensiveOperationInViewBody`,
  `formatterInViewBody` already locate the `body` accessor) + effect inference + Rule 1 detector.
- **Effort:** M (body-location logic already exists to mirror).

---

## Cross-cutting: the handoff seam (Idea #2)

The candidate rule (5) is only useful downstream if the emitted finding names the **symbol**.
Today `CodableLintIssue` (`Sources/Core/Export/CodableLintIssue.swift:14`) carries
`severity, message, locations, suggestion, ruleName, category` — **no function name/signature**.

**Minimal change:** add an optional field:
```swift
public let symbol: String?   // e.g. "func reduce(_:_:) -> State"  — nil for most rules
```
Populate it for Rule 5 (and any future candidate rules). Then a documented contract emerges
for free:

> A PBT-candidate seed = any issue in the JSON report with
> `ruleName == "Pure Function · Property-Test Candidate"`, giving `{file, line, symbol}`.

Optionally add a focused `--format pbt-seeds` to the CLI that projects the report down to
`[{file, line, symbol}]` so `swift-infer discover --seeds <file>` can consume it directly
instead of scanning blind. (Defer until SwiftInferProperties grows a `--seeds` input; the
`category`-filtered JSON is enough to prototype.)

---

## Phasing

1. **Phase 1 (Tier A, no new deps):** category `.testability` + Rules 1, 2, 3. Ships the
   "why it's hard to test" warnings. ~1–2 sessions.
2. **Phase 1.5:** Rule 4 (cross-file Equatable gap) — directly feeds SwiftPropertyLaws.
3. **Phase 2 (Tier B, effect-aware):** Rules 5 + 6. Rule 5 is the thesis rule and the
   pipeline seam.
4. **Phase 3 (handoff):** `symbol` field + optional `--format pbt-seeds`; document the seed
   contract; wire `swift-infer discover --seeds`.

Order rationale: Phase 1 is pure value with zero dependency risk; Rule 5 is deliberately last
because it composes everything before it.

---

## Testing

- Mirror `Tests/CoreTests/` structure; each rule gets a positive-fixture file (should fire)
  and a negative-fixture file (injected/total/Equatable cases — should stay quiet), following
  the idempotency tests under `Tests/CoreTests/Idempotency/`.
- Dogfood: the repo already adds property-based tests over its own rules (recent commits
  "Add detector robustness properties"). Add detector-robustness properties for the new
  visitors (idempotent detection, no crash on malformed input).
- Exemption coverage: assert test/fixture files are exempt (Rules 1, 2), and parameter
  default-value positions are exempt (Rule 1).
- `#expect` style: use `== false` not leading `!`, per CLAUDE.md.

---

## Open decisions (need a call before coding)

1. **New package vs. group:** Tier B in `SwiftProjectLintIdempotencyRules` (reuses wired SEI)
   vs. a new `SwiftProjectLintTestabilityRules` package. Recommendation: start Tier B inside
   the idempotency package's neighborhood to avoid new-package wiring; split later if it grows.
2. **Rule 1 co-fire vs. dedupe** with existing `.dateNow`/`.legacyRandom`/`.cfAbsoluteTime`.
   Recommendation: co-fire but exclude the exact tokens those already cover.
3. **Rule 3:** extend `UnabstractedFileIO` vs. new rule. Recommendation: audit + extend.
4. **`symbol` field** on `CodableLintIssue` — accept the model change now (Phase 1) so the
   schema is stable before Rule 5, or defer. Recommendation: add it in Phase 1 (cheap, additive).
5. **Default on/off:** Rule 5 opt-in (info, advisory); Rules 1–2 default-on (warning). Confirm.

---

## First commit (smallest shippable slice)

`.testability` category + **Rule 2 (Global Mutable State)** — it's the simplest end-to-end
(one `VariableDeclSyntax` visitor, no cross-file, no SEI), so it proves the category wiring
and the test pattern before the harder rules. Then Rule 1, then the rest per phasing.
