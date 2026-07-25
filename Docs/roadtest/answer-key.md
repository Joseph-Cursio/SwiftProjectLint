# Answer key — SwiftProjectLint as road-test subject (FROZEN)

**Subject SHA:** `feeea0f` · **Scope:** `Sources/Core` + the seven nested
`Packages/SwiftProjectLint*` · **Written:** 2026-07-24, *before* any toolchain
command was run against this subject.

> ## The freeze commitment
>
> This file is the hand-written ground truth for the road test in
> `Docs/roadtest/README.md`. It was produced by reading the source only. At the
> time of writing, **no** `swift-infer index`, `swift-infer discover`, nor
> `swiftprojectlint --format pbt-seeds` had been run against this subject.
>
> **Nothing the tools find may be added to this file.** Appendix C records that
> this is the rule that nearly broke — folding a tool-found kernel into the key
> improves the score by moving the denominator. Anything the tools surface that
> is absent here is recorded in the road-test write-up as **UNSCORED**, and
> adjudicated on the refutability test, not on the tool's say-so.
>
> Corrections permitted after freeze: **none to the candidate list.** If a
> candidate below turns out to be misread (e.g. the function is not pure), that
> is recorded as a *key defect* in the write-up — it is not silently deleted.
> The key is allowed to be wrong; it is not allowed to be edited toward the
> tools.

## Method

Every declaration in the scope was enumerated, and each function with a
value-in / value-out shape was read. A candidate earns a place here only if it
carries at least one **refutable** law in the Appendix C sense: some
type-correct, plausible implementation of the function is *rejected* by the law.
`f(x) == f(x)` earns nothing. Each law below therefore names the wrong
implementation it kills.

## Pre-existing property tests — excluded from scoring

Five property suites already exist in `Tests/CoreTests` and predate this road
test. They are **not** candidates: the tools cannot be credited with finding
them, and they are not counted in the denominator.

| Suite | Covers |
|---|---|
| `EffectSymbolTableLawsTests` | cross-file merge confluence; multi-hop fixpoint idempotence |
| `UpwardInferenceMonotonicityTests` | `inferEffects` monotone in its resolver |
| `DetectorRobustnessPropertyTests` | detection determinism; in-bounds line numbers; malformed-input totality |
| `RuleSelectionFilteringPropertyTests` | rule-subset selection is pure filtering *at the detector* |
| `SuppressionSoundnessPropertyTests` | inline suppression removes exactly the targeted rules |

Note `RuleSelectionFilteringPropertyTests` covers the *detector's* honouring of
a rule set. It does **not** cover `LintConfiguration.resolveRules`, which
computes that set. K6 below is therefore open, not a duplicate.

---

## The candidates

Ten kernels, in descending order of the value I judge their laws to carry.

### K1 — `CleanInstanceMethodCatalog.build(from:)`

`([SourceFileSyntax]) -> CleanInstanceMethodCatalog`
(`Packages/SwiftProjectLintVisitors/…/CleanInstanceMethodCatalog.swift:66`)

The strongest candidate in the subject, because **the code states its own law in
prose**: *"The loop is what lets `serialize` qualify on the pass after
`orderedTopLevelPairs` did, so declaration order — and file order — does not
decide the answer."* That sentence is a property.

| # | Law | Kills |
|---|---|---|
| L1.1 | **File-order independence.** `build(sources) == build(sources.shuffled())` | a single-pass resolver; any resolver whose promotion depends on iteration order of `types` |
| L1.2 | **Fixpoint stability.** Every name in the result still passes `isClean` given the *final* `known` set | a loop that stops one pass early |
| L1.3 | **Empty ⇒ empty.** `build([]) == .empty` | a resolver that seeds a default catalog |
| L1.4 | **Monotone in the loop.** `known` only ever grows within `resolve` | a resolver that demotes on a later pass (would not terminate) |
| L1.5 | **Actors excluded.** No actor-declared type appears in the catalog | dropping the `where !members.isActor` guard |

L1.1 is the money law: it is exactly the claim the doc comment makes, it is
cheap to check, and the fixpoint loop is the *only* reason it holds.

### K2 — `RuleIdentifier.suppressionKey`

`RuleIdentifier -> String`
(`Packages/SwiftProjectLintModels/…/RuleIdentifier.swift:241`)

197 cases. `InlineSuppressionParser.keyToRule` builds
`Dictionary(uniqueKeysWithValues:)` over all of them — **a collision is a
runtime trap**, on the first file parsed, in a static initialiser.

| # | Law | Kills |
|---|---|---|
| L2.1 | **Injectivity.** `allCases.map(\.suppressionKey)` has no duplicates | any future rule whose `rawValue` differs from another only by whitespace-vs-hyphen (`"Non-Actor Agent"` vs `"Non Actor Agent"`) — which traps the app |
| L2.2 | **Lowercase-stable.** `key == key.lowercased()` | a `rawValue` carrying a non-ASCII uppercase that `lowercased()` maps differently — `parseRules` looks up `token.lowercased()`, so such a key would be unreachable forever |
| L2.3 | **Non-empty, whitespace-free.** No key is `""` or contains a space | a `rawValue` with a leading/trailing space, which silently yields an unusable directive |

L2.1 is a *crash* guard, not a style guard. That is the highest-severity law in
the key.

### K3 — `InlineSuppressionParser.parse(fileContent:)`

`String -> [SuppressionDirective]`
(`Packages/SwiftProjectLintConfig/…/InlineSuppressionParser.swift:51`)

| # | Law | Kills |
|---|---|---|
| L3.1 | **Directive round-trip.** For every rule `r` and kind `k`, parsing the rendered line `"// swiftprojectlint:\(k) \(r.suppressionKey)"` yields exactly `[(k, {r})]` | the `disable` / `disable:next` prefix-ordering bug — if `("disable", .disable)` were listed before `("disable:next", …)`, every `disable:next` would parse as `disable` with rules `":next …"`. The current order is load-bearing and untested. |
| L3.2 | **Line numbers are 1-based and exact.** A directive on line *n* reports `line == n` | an off-by-one from `enumerated()` |
| L3.3 | **Unknown tokens are ignored, not fatal.** Parsing garbage rule names yields a directive with a smaller rule set, never a crash or a dropped directive | a strict parser that discards the whole directive on one bad token |
| L3.4 | **Empty rule set means "all".** `"…:disable"` with no names parses to `rules == []` | a parser that returns `nil` for the bare form |
| L3.5 | **Non-directive content is inert.** A file with no `// swiftprojectlint:` prefix yields `[]` | over-eager matching on `swiftprojectlint` anywhere in a line |

L3.1 is the one that matters: it is a genuine round-trip and it crosses K2.

### K4 — `DirectoryNode.computeExcludedPaths` ↔ `applyExcludedPaths`

`() -> [String]` and `([String]) -> Void`
(`Packages/SwiftProjectLintConfig/…/DirectoryNode.swift:84,106`)

A true **inverse pair** — the GUI writes the tree out as exclusion patterns and
reads them back in.

| # | Law | Kills |
|---|---|---|
| L4.1 | **Round-trip.** For a tree `t`, applying `t.computeExcludedPaths()` to a fresh all-checked clone of `t`'s shape reproduces `t`'s check states everywhere | a writer that emits bare `id` without the trailing `/` (reader matches on `hasPrefix`, so `Sources/App` would also unexclude nothing / mis-match `Sources/AppKit`) |
| L4.2 | **Output sorted and duplicate-free** | the pruning optimisation regressing to emit children of an unchecked parent |
| L4.3 | **Pruning is sound.** No emitted path is a proper prefix-descendant of another emitted path | same |
| L4.4 | **`mixed` is never a leaf state.** After `recomputeAllDescendantStates`, a childless node is `.checked` or `.unchecked` | the recompute branch running on empty `children` |
| L4.5 | **Empty patterns are a no-op.** `applyExcludedPaths([])` leaves the tree unchanged | the `guard paths.isEmpty == false` being dropped, which would run `recomputeAllDescendantStates` and silently rewrite ancestor states |

**Suspected defect, recorded in advance:** L4.1 is expected to be *false* at the
root. `collectExcluded` emits `""` for an unchecked root (empty `id`), and
`applyExclusions` matches `nodePath.hasPrefix("")` — which is true for **every**
node. Writing out a fully-excluded root and reading it back should therefore
work, but any pattern list containing `""` unchecks the entire tree. Whether
that is reachable in the GUI is a separate question; the law is refutable either
way.

### K5 — `LintConfigurationWriter.render` ↔ `LintConfigurationLoader.load`

`(LintConfiguration) -> String` / `(String) -> LintConfiguration`
(`…/LintConfigurationWriter.swift:8`, `…/LintConfigurationLoader.swift:34`)

| # | Law | Kills |
|---|---|---|
| L5.1 | **Round-trip on the persisted fields.** `load(render(c))` preserves `disabledRules`, `enabledOnlyRules`, `excludedPaths`, `ruleOverrides` | a writer that forgets to quote a rule name containing a `:`; a severity spelled one way by the writer and another by the parser |
| L5.2 | **Partial-fidelity is total.** `render` never emits a key `load` cannot parse | any new config field written but not read |
| L5.3 | **Empty config renders to something `load` maps back to `.default`'s persisted fields** | a writer emitting a stray `rules:` header with no entries |

**Recorded in advance:** `render` deliberately drops `architecturalLayers`,
`enabledFrameworkAllowlists`, and `includeNestedPackages`. So the *full*
round-trip is false by construction and L5.1 is correctly stated over the
four persisted fields only. A tool proposing an unrestricted `codable-round-trip`
here would be proposing a law that fails for a benign reason — worth noting as a
false positive if it happens.

### K6 — `LintConfiguration.resolveRules(cliCategories:cliRuleIdentifiers:)`

`([PatternCategory]?, [RuleIdentifier]?) -> [RuleIdentifier]?`
(`…/LintConfiguration.swift:120`)

Pure set algebra over a 197-element enum.

| # | Law | Kills |
|---|---|---|
| L6.1 | **Disabled rules never survive.** `Set(result) ∩ disabledRules == ∅` | reordering the `subtract(disabledRules)` above the `enabledOnly` intersection |
| L6.2 | **Sentinels never survive.** `.unknown`, `.fileParsingError` ∉ result | dropping either `remove` |
| L6.3 | **Opt-in rules stay off** unless `enabledOnlyRules` names them | dropping `subtract(Self.optInRules)` |
| L6.4 | **CLI identifiers take full precedence** — result is exactly `cliRuleIdentifiers` when non-nil, regardless of every other field | moving the early return below the set construction |
| L6.5 | **Category restriction is a filter.** With `cliCategories = C`, every result rule has `category ∈ C`, and the result equals the uncategorised result filtered by `C` | a category check against the wrong side of the mapping |
| L6.6 | **`nil` means exactly "no restriction".** `result == nil` iff the effective set equals the default set and `cliCategories == nil` | the `allRules` recomputation drifting out of sync with the construction above it — the two are written twice and must agree |

L6.6 is a **duplicated-expression** law: lines 129–140 and lines 151–153 compute
the same set independently. Any edit to one and not the other is a bug this law
catches and nothing else does.

### K7 — `LintConfiguration.applyOverrides(to:projectRoot:)`

`([LintIssue], String?) -> [LintIssue]`
(`…/LintConfiguration.swift:166`)

`compactMap` — filter + transform.

| # | Law | Kills |
|---|---|---|
| L7.1 | **Subset & order-preserving.** Result is a subsequence of the input | a `compactMap` replaced by a set-based dedup |
| L7.2 | **Identity when no overrides.** `ruleOverrides.isEmpty ⇒ result == issues` | the guard being dropped |
| L7.3 | **Only severity changes.** For every surviving issue, `message`, `locations`, `suggestion`, `ruleName` are unchanged from its input counterpart | the rebuild at line 203 dropping a field — it re-constructs by hand, so a *new* `LintIssue` field silently defaults here |
| L7.4 | **Idempotence.** Applying the same config twice equals applying it once | a severity override that reads the *current* severity rather than the override |
| L7.5 | **Untouched rules pass through unchanged** — an issue whose `ruleName` has no override is `===`-equivalent to its input | the `guard let override` returning a rebuilt copy |

L7.3 is a real maintenance hazard: `LintIssue` is rebuilt field-by-field with a
defaulted initialiser, which is precisely the shape the subject's *own*
`lossyStructRebuild` rule exists to flag. The linter should arguably be flagging
itself here.

### K8 — `InlineSuppressionFilter.filter(_:fileContent:)`

`([LintIssue], String) -> [LintIssue]`
(`…/InlineSuppressionFilter.swift:22`)

**Partially covered** by `SuppressionSoundnessPropertyTests` (blanket-disable
soundness/completeness). What that suite does *not* cover, and is open:

| # | Law | Kills |
|---|---|---|
| L8.1 | **Order-preserving subsequence** | a reordering rewrite |
| L8.2 | **Idempotence.** `filter(filter(xs, c), c) == filter(xs, c)` | a stateful range builder |
| L8.3 | **No directives ⇒ identity** | over-eager range construction |
| L8.4 | **`disable:next` covers exactly one line** — an issue two lines below is *not* suppressed | an off-by-one in `appendSingleLineRange` |
| L8.5 | **Unclosed `disable` runs to EOF** | `closeDisableRegions` dropping the tail region |

L8.4 and L8.5 are the boundary cases the existing blanket-disable suite steps
around by construction.

### K9 — `FileAnalysisUtils.extractSwiftBasename(from:)`

`String -> String` (`…/FileAnalysisUtils.swift:19`)

Included for the Appendix C §2.4.2 reason: **the docstring states a reference
definition the code may not meet.** The doc says the result is "the base file
name without its extension … derived from the file name by removing the
`.swift` extension" — singular, a suffix. The code is
`replacingOccurrences(of: ".swift", with: "")`, which removes **every**
occurrence, anywhere.

| # | Law | Kills |
|---|---|---|
| L9.1 | **Suffix-strip round-trip.** For any basename `n` not containing `".swift"`, `extract(n + ".swift") == n` | nothing yet — this one should hold |
| L9.2 | **Only the extension is removed.** For a path whose *basename* contains an interior `".swift"` — e.g. `"My.swiftUI.helper.swift"` — the result retains the interior text | **the current implementation**, which yields `"MyUI.helper"` |
| L9.3 | **Idempotence.** `extract(extract(p)) == extract(p)` | a version that strips a further component |
| L9.4 | **Basename-only.** The result never contains `/` or `\` | dropping the Windows normalisation |

L9.2 is a **predicted refutation**. I am recording it here, pre-freeze, as a
prediction the road test will settle: I expect this law to fail against the
current code, and I expect the failure to be *benign in practice* (no real
Swift file is named that way) but a true doc-vs-code drift.

### K10 — `RuleIdentifier.category` totality

`RuleIdentifier -> PatternCategory`
(`…/RuleIdentifier+Category.swift:14`)

| # | Law | Kills |
|---|---|---|
| L10.1 | **Totality without a fallback sink.** No rule other than `.unknown` / `.fileParsingError` maps to `.other` | a `default:` arm absorbing newly added rules — a new rule silently becomes uncategorised and drops out of every category-filtered run |
| L10.2 | **Category filtering is exhaustive.** Every rule is reachable from some `PatternCategory` | same |

L10.1 is the "spell-checker missing a word" shape from Appendix C, aimed at the
subject itself: a new rule that quietly lands in `.other` is never checked by a
category run, and nothing announces it.

---

## Scoring rows

Recorded in advance so the write-up cannot choose a flattering row afterwards.

**The one row that matters:** *of the 10 candidates above, how many does the
toolchain surface with at least one refutable law?* Everything else is
instrumentation.

Instrumentation rows:

1. **Seed reach** — how many of K1–K10 appear in `--format pbt-seeds` at all,
   and with which `PBTSeedKind`. (`extractable-kernel` is `isAnalysable ==
   false`, so it reaches the reader but not `discover`.)
2. **Discovery reach** — how many appear in `swift-infer discover` output.
3. **Refutability** — of the laws proposed for reached candidates, how many are
   refutable vs. `f(x) == f(x)`.
4. **Law overlap** — of the 39 laws enumerated above, how many does the
   toolchain independently name?
5. **Unscored finds** — candidates the tools surface that are *not* in this key,
   adjudicated by the refutability test. Recorded separately; they do **not**
   improve the score.
6. **Key defects** — candidates here that turn out to be misread. Recorded, not
   deleted.

## Predictions, logged pre-run

Also frozen, because a prediction made after the fact is worthless:

- **K9/L9.2 will refute.** The doc and the code disagree.
- **K1 will not be reached by `discover`.** `[SourceFileSyntax] ->
  CleanInstanceMethodCatalog` has no derivable generator — SwiftSyntax nodes are
  not constructible from a `Gen`. I expect "not derived (no strategy matched
  this type)". This is the *generator* boundary, not the template boundary.
- **K2 will not be reached.** `suppressionKey` is a computed property on an enum
  with no arguments; injectivity-over-`allCases` is a law about the *type*, not
  about a function's inputs, and I do not expect the catalog to name it.
- **K6 will be reached but under-lawed.** Set-algebra shapes exist in the
  catalog (`filter-subset`, `selection-subset` shipped from the
  SwiftLintRuleStudio road test), so I expect a subset law, and I expect L6.6
  — the duplicated-expression law — to be missed.
- **K4 and K5 are the round-trip family**, which the catalog does name. If the
  toolchain reaches anything here, I expect it to be these two.
- **Overall guess: 3 of 10 reached with a refutable law.**
