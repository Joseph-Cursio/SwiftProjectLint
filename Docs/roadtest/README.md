# Road test — the PBT toolchain against SwiftProjectLint (2026-07-24)

A **scored** road test, in the Appendix C sense: a hand-written answer key frozen
before any tool was run, then the pipeline pointed at the subject and graded
against it.

- **Subject:** SwiftProjectLint @ `feeea0f` — `Sources/Core` plus the seven
  nested `Packages/SwiftProjectLint*`. ~37k lines, 197 rules.
- **Answer key:** [`answer-key.md`](answer-key.md), 10 candidates / 39 laws,
  committed at `9abcfde` **before** the first `discover` or `pbt-seeds` run.
- **Tools:** `swift-infer` @ `491de16` (debug build), SwiftProjectLint's own CLI
  as the linter, SwiftEffectInference @ `097181a`.
- **Baseline:** 2931 tests in 352 suites, all green, before any change.

This is a dogfooding run — the linter is one of the five packages, pointed at
itself. That makes it a weaker benchmark than an unrelated subject in one way
(shared authorship) and a sharper one in another: it is a compiler-adjacent
codebase, which is exactly the shape the generator layer struggles with.

## The headline

**The scored row — of 10 keyed candidates, how many does the toolchain surface
with at least one refutable law?**

| Configuration | Reached | |
|---|---|---|
| `discover` default (templates only) | **1 / 10** | K8 |
| `discover --include-possible` | **2 / 10** | K8, K9 |
| `discover --seeds` (linter manifest) | **2 / 10** | unchanged; seeding added 14 tautologies |
| linter seed manifest alone | **6 / 10** | K1, K5, K6, K7, K8, K9 |
| `discover --docstring-advice` | **8 / 10** | K1–K6, K9, K10 |
| **union of all surfaces** | **9 / 10** | only K7 missed — correctly, it is impure |

Prediction logged pre-run was "3 of 10". The template catalog's answer was **2**
with `--include-possible`, **1** without.

> **Correction (2026-07-25).** The first version of this table gave the default
> run as 2/10 (K8, K9). That was wrong: it was the `--include-possible` figure.
> Both K8 and K9 score `Possible`, and only K8 survives a default run — the tier
> cut promotes a Possible-tier law only when it is **role-entailed**
> (`Refutability.roleEntailedTemplates`), which `filter-subset` is and
> `idempotence` is not. K9's idempotence proposal is hidden by default.
>
> Found while verifying fix 2, by checking a claim rather than re-deriving it.
> The split now has its own row instead of one conflated number.

The result that matters is not the 1 or the 2. It is the spread between it and
**9**, because every configuration in that table was already shipping. The
candidates were not out of reach — they were behind a flag that is off by
default.

## What the pipeline actually did

### The linter half — thorough

`swiftprojectlint . --format pbt-seeds --include-nested-packages` produced **588
seeds**: 386 `pure-function`, 202 `extractable-kernel`, 0 `idempotency`.

Against the key it reaches 6 of 10, which is more than either `discover` surface
managed. Notably it seeds **K1 `CleanInstanceMethodCatalog.build`** — the
strongest candidate in the key — as a first-class `pure-function`.

The linter is not the weak link. This reproduces Finding B from the
SwiftLintRuleStudio road test, independently, on a different subject: *the
"linter under-seeds" hypothesis is a phantom.*

### The inference half — thin, and mostly tautologies

Unseeded `discover` across the whole scope: **47 suggestions** (40 on a default
run, after the refutability tier cut).

| Template | Count |
|---|---|
| predicate | 36 |
| idempotence | 4 |
| monotonicity | 4 |
| round-trip | 1 |
| filter-subset | 1 |

**28 of 47 (60%) print `Generator: not derived (no strategy matched this
type)`.** They are proposals that cannot be run.

Seeding made it worse, not better. `discover --seeds` on the Config package
returned 19 suggestions — the same 5 real ones, plus **14 `determinism`
advisories**, i.e. `f(x) == f(x)`. The linter handed over 386 pure functions and
the engine's answer for those it has no template for is the one law that cannot
fail. Refutable yield of the seeded run: **5 of 19**, and one of those five is a
false positive (below), so **4 of 19 ≈ 21%**.

## Two real bugs, both found by properties, both in green code

Consistent with Appendix C's tally: the existing test suite was green before,
during, and after. 2931 tests did not have an opinion about either of these.

### Bug 1 (HIGH) — a severity override silently empties the seed manifest

`LintConfiguration.applyOverrides` rebuilds an issue field-by-field to apply a
severity override, through an initialiser whose trailing `symbol:` parameter
defaults to `nil` — and does not pass it:

```swift
return LintIssue(severity: severity, message: issue.message,
                 locations: issue.locations, suggestion: issue.suggestion,
                 ruleName: issue.ruleName)   // symbol: defaults to nil
```

`PBTSeedsFormatter.format` drops any issue whose `symbol` is nil. So configuring
a severity for a seed-bearing rule in `.swiftprojectlint.yml` does not downgrade
that rule's seeds — it **deletes them**, and `.pbt/seeds.json` comes back short
with exit 0.

That is a confident zero at the entry point of the entire adoption loop, and it
is self-inflicted: the file's own doc comment says *"a finding the linter prints
but does not seed is a finding the pipeline does not have."*

#### The part that stings: the linter had already reported it

This is the shape of the linter's own **Lossy Struct Rebuild** rule, and the
first draft of this write-up assumed the rule had simply never been run here.
That was wrong, and checking it produced the sharpest finding of the run.

A full `--include-nested-packages` run reports **three** Lossy Struct Rebuild
findings. One of them is:

```
Packages/…/Configuration/LintConfiguration.swift:210 | LintIssue
  `LintIssue` is rebuilt field-by-field from `issue`. Its initialiser has
  defaulted parameters, so a field you forget takes its default SILENTLY —
  the value compiles, renders, and is quietly missing part of itself.
```

That is the bug site, with the correct diagnosis, in the tool's own default
output. The rule fires on the *shape* — dominant argument ratio from one base
value, plus a defaulted initialiser — with no condition on whether a field is
actually being dropped, so it was firing identically before the fix (4 of 5
arguments sourced from `issue`, versus 5 of 6 after).

So this is not the Appendix C §1.1.3 shape of *a passing test that ratified the
bug*. It is a new variant, and a worse one:

> **The tool found its own bug, printed an accurate description of it, and the
> finding went unread.**

The rule's doc comment makes it more pointed still. It was written from evidence
in SwiftInferProperties, where eight rebuild sites each dropped a newly added
`generatorRecipes` field — *"the half of a property law that decides whether the
law can **fail at all**. The suggestion still printed a confident score, having
quietly stopped being able to find the bug."*

The identical failure mode then recurred one repository over, on `symbol` — the
half of a seed that decides whether the seed **exists at all**. The manifest
still printed, exit 0, having quietly stopped carrying the finding.

A ninth toolchain finding follows directly, and it is not about any of the five
packages: **a linter with 197 rules and a real finding in its own output has a
signal-to-noise problem, not a detection problem.** The same run reports
thousands of findings; nothing marks this one as the one that breaks the
pipeline. Seed-bearing rules and rules that damage the seed path deserve to be
separable from the rest — which is fix 9 in the table below.

Found by writing law L7.3 ("a severity override changes the severity and nothing
else") — before the test was even run; confirmed by the shrunk counterexample
`transformed.symbol → nil` vs `original.symbol → "symbol1"`. Fixed by passing
`symbol:` through.

### Bug 2 (LOW severity, exemplary shape) — doc-vs-code drift in basename extraction

`FileAnalysisUtils.extractSwiftBasename` documented "removing the `.swift`
extension" — a suffix — and implemented
`replacingOccurrences(of: ".swift", with: "")`, which removes **every**
occurrence anywhere. `"My.swiftUI.helper.swift"` came back `"MyUI.helper"`.

Low severity only because the function has **zero production callers** (see
toolchain finding 6). Its value is what it demonstrates:

> The single **shape-entailed** law available on this function — `T -> T`
> idempotence, which is exactly what `discover` proposed — **held under the bug**
> (`"a.swift.swift"` → `"a"` → `"a"`) and **fails under the fix**
> (`"a.swift.swift"` → `"a.swift"` → `"a"`).

So the catalog's proposal here did not merely miss the bug; it ratified it, and
would have flagged the correction as the regression. The law that found the bug
came from the docstring. This is the sharpest single argument in the run for
reading reference definitions out of prose rather than off type signatures.

### Also surfaced

- **An undocumented behaviour, now pinned:** rule names in suppression
  directives are matched case-insensitively (`parseRules` lowercases before
  lookup). Found because `"FORCE-TRY"` was seeded into a junk-token pool and the
  property failed on it — the test was wrong, the code was right. Pinned rather
  than papered over.
- **Four correct-today, guarded-against-tomorrow results** — the category
  Appendix C insists on counting: `suppressionKey` injectivity holds across all
  197 rules (a collision would be a *runtime trap*, not a wrong answer, because
  `keyToRule` uses `Dictionary(uniqueKeysWithValues:)`); the `DirectoryNode`
  exclusion round-trip holds; `resolveRules`' set algebra holds including the
  duplicated-expression law; `CleanInstanceMethodCatalog` is genuinely
  file-order independent.

## Key defects — where the frozen key was wrong

Recorded, not deleted, per the freeze commitment.

1. **L9.3 (idempotence) is not a law of `extractSwiftBasename`.** I keyed it as
   one. It is false for the correct implementation. The test now documents the
   non-idempotence deliberately.
2. **K10 was over-claimed.** `RuleIdentifier.category` is an exhaustive `switch`
   with no `default:` arm, so the compiler already forces every new rule to be
   mentioned. The law retains value (it forbids the `.other` arm) but is weaker
   than keyed.
3. **K4's predicted defect did not exist.** I recorded in advance that the
   empty-string root pattern would likely break the round-trip. It does not —
   `""` means "exclude everything" consistently on both sides.
4. **Two pure kernels were walked past.** `LayerPolicy.contains(relativePath:)`
   and `ProjectLinter.isGeneratedFile(at:)` are pure predicates the tools
   surfaced and the key omitted. This is precisely the Appendix C shape — the
   hand-written key missing a real candidate — and they are recorded here as
   **unscored**. They do not improve the score.

## Toolchain findings, ranked by leverage

**1. `--docstring-advice` is off by default, and it is worth 7 of 10
candidates.**
This is the finding. The advisory reaches K1, K2, K3, K4, K5, K6, K9, K10 — the
template catalog reaches K8 and K9. Every candidate the templates missed for
lack of a matching law family, the docstring surface found, because the subject
is well-documented and the templates' failure was never about the *code*.

Appendix C labels this feature *"built and unverified — no measurable lift"* on
the strength of a 6-reader A/B whose control arm was contaminated. This is
different evidence, on a different metric: not reader lift, but **reach against a
frozen key**. On that metric it is the single highest-value surface in the tool.

Caveat, stated plainly: the advisory hands you a *sentence*, not a law — "encode
THAT". Reach is not laws delivered, and a human still writes the property. But
reach is exactly what "find me the opportunities" means.

**2. The handoff loses more than either end.**
Linter reaches 6, `discover` reaches 2, and the four lost in between are lost at
the seam. K6/K7/K8 are seeded `extractable-kernel`, whose `isAnalysable` is
`false`, so `discover --seeds` cannot focus on them — they are reported to the
reader as places to refactor, never as subjects. This is the **kind-granularity
gap** (Finding B, SwiftLintRuleStudio) reproduced on a fresh subject: a function
can owe a law at its own boundary and still be seeded only as a location.

**3. The generator boundary is the hard ceiling, and it is structural here.**
60% of suggestions have no derivable generator. K1 — the best candidate in the
key, correctly seeded by the linter — takes `[SourceFileSyntax]`, and SwiftSyntax
nodes are not constructible from a `Gen`. The workaround a human reaches for
immediately is to generate *source strings* and parse them, which is what the
hand-written suite now does. **The tool has no notion of "generate the input in a
different representation and map into the type."** For a compiler-adjacent
codebase that one recipe would unlock most of the missing 60%.

**4. No type-level law family over `CaseIterable` carriers.**
K2 and K10 are both `RuleIdentifier -> X` mappings over a 197-case enum, and
their laws are about the *mapping across all cases* (injectivity; no case lands
in a sink), not about a function's inputs. Nothing in the catalog names that
shape. K2's law guards a **runtime trap**, which makes this the highest-severity
gap by consequence rather than by count. The generator side is free — the engine
already derives from `CaseIterable`. Cheapest high-value template to add.

Related: the right check for a 197-element domain is **exhaustive, not sampled**.
A `propertyCheck` over a finite case list would have to be lucky to draw the one
colliding pair. A `CaseIterable` template should emit a loop, not 100 trials.

**5. A spurious round-trip pairing still gets through.**
`discover` proposed `extractSwiftBasename ↔ realPath` as a round-trip pair, on
`String -> String ↔ String -> String` type symmetry alone. They are unrelated
functions. This is the `CustomRuleConflict` false-pairing shape the label-stem
admission gate was meant to close; it does not cover this case.

**6. Nothing ranks by reachability.**
The top-scored Config suggestion is on `extractSwiftBasename`, which has **zero
production callers** — only tests. A kernel nothing calls should sort below one
on the hot path. Call-site count is cheap for the linter to compute and would
sharpen the manifest at no modelling cost.

**7. The docstring advisory reads only the function's own docstring.**
K1's decisive sentence — *"declaration order — and file order — does not decide
the answer"* — lives on the **type**'s doc comment and on the **private**
`resolve` method. `build(from:)`, the public entry point the advisory reports,
carries only "Resolves the catalog over every parsed source in the project."
The advisory should hoist prose from the enclosing type and from private helpers
the function delegates to.

**8. `--seeds` advisory output is not scoped to `--sources`.**
Running with `--sources …/SwiftProjectLintModels` prints all 202 extractable
kernels, including ones in `SwiftProjectLintEngine`. Identical output for four
different scopes. Cosmetic, but it makes the advisory unusable for narrowing.

## Prioritised toolchain fixes

| # | Change | Package | Leverage |
|---|---|---|---|
| 1 | Promote `--docstring-advice` to the default run (or a `discover` section, not a flag) | SwiftInferProperties | +7 of 10 candidates |
| 2 | `CaseIterable` law family: mapping injectivity + no-sink exhaustiveness, emitted as an exhaustive loop | SwiftInferProperties | guards a runtime trap; free generator |
| 3 | Split `extractable-kernel` into "has no name yet" vs "has a name but an impure caller", so the latter is analysable | SwiftProjectLint + SIP | the 4-candidate handoff loss |
| 4 | Generator recipe: build inputs in a proxy representation and map in (`String` → `Parser.parse` → `SourceFileSyntax`) | SwiftPropertyLaws / SIP | most of the 60% not-derived |
| 5 | Hoist docstring prose from enclosing type + private callees | SwiftInferProperties | K1-shaped misses |
| 6 | Rank seeds by production call-site count | SwiftProjectLint | signal quality |
| 7 | Require a shared label stem (not just type symmetry) for `round-trip` pairing | SwiftInferProperties | kills the false pair |
| 8 | Scope the `--seeds` advisory to `--sources` | SwiftInferProperties | cosmetic |
| 9 | Surface findings that damage the seed path separately from ordinary lint output | SwiftProjectLint | the bug above was reported and unread |

Fix 3 has a soundness caveat worth stating before anyone builds it: the reason
`extractableKernel` is `isAnalysable == false` is that the symbol names the
*enclosing* function, which is a location rather than a subject. Splitting the
kind is only safe where the linter can name the callable boundary itself.

## Property tests added

Seven suites, 45 tests, all green. Written against the key, not against the
tools' output.

| Suite | Key | Laws |
|---|---|---|
| `Models/RuleIdentifierKeyLawsTests` | K2, K10 | injectivity, lowercase-stability, well-formedness, no uncategorised rules |
| `Suppression/InlineSuppressionParserRoundTripTests` | K3 | directive round-trip (197×4, exhaustive), line-number exactness, junk-token tolerance, case-insensitivity, inertness |
| `Visitors/CleanMethodCatalogOrderIndependenceTests` | K1 | file-order independence, reverse-order chain resolution, refusal propagation, actor exclusion, overload all-or-nothing |
| `Configuration/OverrideApplicationLawsTests` | K7 | field preservation (**found bug 1**), identity, pass-through by identity, subsequence, idempotence |
| `Configuration/RuleResolutionLawsTests` | K6 | the duplicated-expression law, disabled/sentinel exclusion, opt-in gating, CLI precedence, category filtering |
| `FileAnalysis/DirectoryNodeExclusionRoundTripTests` | K4 | round-trip, pruning soundness, sorted/deduped output, leaf states, empty-pattern semantics |
| `FileAnalysis/BasenameExtractionLawsTests` | K9 | suffix-only removal (**found bug 2**), basename projection, deliberate non-idempotence |

Two suites needed input built in a proxy representation (Swift source strings
parsed into `SourceFileSyntax`; `DirectoryNode` trees assembled by hand) — the
recipe fix 4 would automate.

## Since the road test — what shipped, and what it moved

Recorded as an addendum rather than folded into the numbers above. The scored
result is a measurement taken on a date; rewriting it to reflect later fixes
would be the denominator-moving this exercise exists to avoid.

| Fix | Where | Status |
|---|---|---|
| 1 — `--docstring-advice` on by default | SwiftInferProperties `ec7604c` | shipped |
| 2 — `CaseIterable` mapping law family | SwiftInferProperties `10318a4` | shipped |
| 4 — proxy-construction generator recipes | SwiftInferProperties `820b55a` | shipped |
| 3 — the seed-kind split | — | **not built; the diagnosis was wrong** |
| 3′ — Equatable index missed synthesised conformances | SwiftProjectLint | shipped in its place |

**Fix 1** flips a default. It surfaces nothing that was not already reachable by
passing a flag, so it is a defaults change and not new capability.

**Fix 2** is new capability: `caseiterable-key-injectivity` and
`caseiterable-case-coverage`. On this subject they fire exactly twice across
~37k lines — `suppressionKey` earns the injectivity law, `category` earns the
coverage law — with no false positives and no cross-firing.

The design point worth carrying: injectivity is **not** shape-entailed. This
subject's own `category` maps 197 rules onto 11 categories deliberately, so a
template that proposed distinctness for every enum mapping would fail on correct
code. The name and the codomain decide which of the two laws is owed.

Only the injectivity half is admitted to `roleEntailedTemplates`, and that
asymmetry is the point. A member called `…Key` / `…Identifier` / `…Slug` claims
to *identify* the case, so a collision is a bug or a lie about the name — the
same standard `filter-subset` was admitted under. Routing cases to a sink can be
perfectly correct (this subject's own `.unknown` and `.fileParsingError` do), so
coverage stays below the cut. Admitting it would make the tool cry wolf, which
`Refutability` argues is worse than saying nothing. The template's noun list was
narrowed to clear that bar: `name` is excluded, because two cases sharing a
*label* is ordinary code.

Re-measured, both fixes in:

| Configuration | On the day | Now |
|---|---|---|
| `discover` default (templates only) | 1 (K8) | **2** (K2, K8) |
| `discover --include-possible` | 2 (K8, K9) | **4** (K2, K8, K9, K10) |
| `discover` default, all surfaces | — | **9** (everything but K7) |

The last row is the one an adopter actually experiences: with fix 1 the
docstring advisory is on by default, so a bare `swift-infer discover` now
reaches 9 of the 10 keyed candidates. K7 remains correctly unreached — it is
impure.

The union across surfaces is unchanged at 9. Fix 2 did not widen reach; it moved
two candidates from "only the docstring surface finds these" into the catalog
proper, and promoted one of them above the default tier cut. That is a
robustness gain, and it is worth less than the headline makes it sound.

**Fix 4** addresses the largest finding by count — toolchain finding 3, the
generator boundary. 60% of suggestions printed "not derived (no strategy matched
this type)", and ~92% of those carriers were SwiftSyntax nodes, because this
subject is a static analyser whose kernels take AST nodes.

`swift-infer` now recognises a parser-constructed carrier and attaches a runnable
recipe — generate source, `Parser.parse` it, walk the tree — rather than
dead-ending. **Dead carriers on this subject: 28 → 3.** The residue is honest:
`FunctionSignature` and `[LintIssue]` are declared in packages outside the
scanned scope, and `some SyntaxProtocol` is declined on purpose (no single
concrete node to parse out).

It does not move the scored row, and should not be read as if it did. Reach is
about which candidates are *proposed*; this is about whether a proposed law can
be *run*. The keyed candidate it touches is K1, which was already reached by the
linter's manifest and by the docstring surface — what changed is that a reader
who gets there is no longer told the law is unrunnable.

The claim was verified by using it rather than by inspection:
`Tests/CoreTests/Visitors/SyntaxPredicateTotalityTests.swift` is the emitted
recipe pasted and filled in, and it holds `SyntaxHelpers`' predicates to totality
and a refinement law. A recipe that does not compile is advice, not a generator.

### Fix 3 — the diagnosis was wrong, and the fix that replaced it does not move the score

Recorded at length because it is the fourth time in this road test that a named
blocker turned out not to be the blocker, and the repetition is the finding.

**What was proposed.** Toolchain finding 2 said K6/K7/K8 are seeded
`extractable-kernel`, whose `isAnalysable` is `false`, so `discover --seeds`
cannot focus on them — split the kind and the three become analysable.

**What was true.** All three come from the `pureClosureCandidate` rule, and their
line numbers point at closures *inside* those functions
(`LintConfiguration.swift:147` is the `rules.filter { … }` call). The symbol
really is a location rather than a subject, so `isAnalysable == false` is
**correct** and splitting the kind would have been wrong. The caveat attached to
the original proposal was right, for the wrong reason.

**The real blocker was one layer down.** `PropertyTestCandidacy` gates seeding on
the return type being known-`Equatable`, and `EquatableConformanceCollector` only
recorded types that *explicitly declare* `Equatable` / `Hashable` / `Comparable`.
It missed conformances the **compiler synthesises**. A probe settled it without
guesswork:

```
resolveRules — purity verdict: .pure
  without RuleIdentifier in the index → nil (not a candidate)
  with    RuleIdentifier in the index → candidate(.ofSelfAndInputs)
```

`resolveRules` was pure the whole time. The only thing keeping it out of the
manifest was that `RuleIdentifier: String, CaseIterable, Codable` never says
`Equatable` — it has it by language guarantee.

**Fixed:** an enum with no associated values is `Equatable` and `Hashable`
whether it declares them or not, and a raw-value enum cannot carry associated
values, so the two cases are one. Enums *with* payloads stay gated on the
declaration. That is a language guarantee rather than a heuristic, which is what
makes widening the index sound.

**Measured on the subject: 588 → 600 seeds, all `pure-function`, none removed.**
`resolveRules` is now seeded analysably; `applyOverrides` and `filter` correctly
are not (the first calls `findSwiftFiles`, the second returns `[LintIssue]`,
which carries a random `UUID` and is genuinely not `Equatable`).

**And the scored row does not move.** Seeded discovery on the Config package went
19 → 21 suggestions, and *the entire increase is `determinism`* — 14 → 16 of the
`f(x) == f(x)` tautology. `resolveRules` reaches `discover` and is handed a law
that cannot fail, because no template matches
`([PatternCategory]?, [RuleIdentifier]?) -> [RuleIdentifier]?`.

So K6 moved from **invisible** to **visible but tautological**, which is progress
in the pipeline and not progress on the benchmark. Counting it as reached would
be exactly the refutability error Appendix C's scoring rule exists to prevent.

The next refuter is now named, and on this record that is worth stating as a
hypothesis rather than a plan: the shape wants a law like
`Set(result) ⊆ Set(RuleIdentifier.allCases)` — a selection out of a `CaseIterable`
domain, which would be a third member of the `caseiterable-*` family. Three
previous passes each named the remaining blocker and were wrong, so it should be
*measured* before it is built.

## Net

The loop found **two real bugs and four clean guards** on a codebase whose 2931
tests were green throughout, which is the ratio Appendix C predicts: applied to
real code, the practice returns *correct-today, guarded-against-tomorrow* about
as often as it returns a defect.

The scored answer is **2 of 10 on a default run, 9 of 10 across surfaces already
shipping**. That gap is the actionable result, and it is not a catalog gap — it
is a **defaults** problem. The single most valuable change in the table above is
turning on a feature the book currently describes as unverified.

And the honest counterweight, in the run's own words: the one law the template
catalog proposed for the function that actually had a bug was a law the bug
satisfied.
