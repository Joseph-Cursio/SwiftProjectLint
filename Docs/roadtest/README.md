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

Two passes, and the second one matters for how you read the first. Everything up
to *Net* is the original run and the fixes that followed it, kept as written.
[**Second pass (2026-07-26)**](#second-pass-2026-07-26--the-handoff-and-the-defaults-problem-this-write-up-named)
records what shipped afterwards — including the defaults problem the Net section
correctly named and then pointed at the wrong flag for. The scored row is
unchanged by it, and the section says so.

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
4. **Two total kernels were walked past.** `LayerPolicy.contains(relativePath:)`
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

**11 suites, 83 tests, all green** — the whole suite goes 2931 → 3014 tests and
352 → 363 suites. Written against the key, not against the tools' output.

> **These are not a toolchain score, and must not be read as one.** Every one was
> written by hand. What the toolchain contributed is *reach* — which candidates it
> surfaced — and that number is 1 of 10 on a default run, 9 of 10 across all
> surfaces. A test count measures the effort spent, not the tool's yield, and the
> two move independently: the largest suite here (`InlineSuppressionParserRoundTrip`,
> exhaustive over 197 rules × 4 spellings) is for a candidate the templates never
> surfaced at all.
>
> The five suites already in `Tests/CoreTests` before this exercise — 10 tests —
> are excluded throughout. They predate the road test, so nothing here found them;
> see the answer key's exclusion table.

The first seven were written against the frozen key. The last four came out of
the toolchain fixes below and are listed separately.

| Suite | Key | Laws |
|---|---|---|
| `Models/RuleIdentifierKeyLawsTests` | K2, K10 | injectivity, lowercase-stability, well-formedness, no uncategorised rules |
| `Suppression/InlineSuppressionParserRoundTripTests` | K3 | directive round-trip (197×4, exhaustive), line-number exactness, junk-token tolerance, case-insensitivity, inertness |
| `Visitors/CleanMethodCatalogOrderIndependenceTests` | K1 | file-order independence, reverse-order chain resolution, refusal propagation, actor exclusion, overload all-or-nothing |
| `Configuration/OverrideApplicationLawsTests` | K7 | field preservation (**found bug 1**), identity, pass-through by identity, subsequence, idempotence |
| `Configuration/RuleResolutionLawsTests` | K6 | the duplicated-expression law, disabled/sentinel exclusion, opt-in gating, CLI precedence, category filtering |
| `FileAnalysis/DirectoryNodeExclusionRoundTripTests` | K4 | round-trip, pruning soundness, sorted/deduped output, leaf states, empty-pattern semantics |
| `FileAnalysis/BasenameExtractionLawsTests` | K9 | suffix-only removal (**found bug 2**), basename projection, deliberate non-idempotence |

Two of those needed input built in a proxy representation (Swift source strings
parsed into `SourceFileSyntax`; `DirectoryNode` trees assembled by hand) — the
recipe fix 4 would automate.

Four more followed from the toolchain work rather than from the key:

| Suite | From | Laws |
|---|---|---|
| `Visitors/SyntaxPredicateTotalityTests` | fix 4 | totality over parsed nodes incl. malformed source; `isSwiftUIViewOnly` refines `isSwiftUIView`; reparse determinism. Also the check that the emitted recipe compiles |
| `Visitors/EquatableSynthesisCollectorTests` | fix 3′ | synthesised `Equatable` on payload-free enums; payload enums, structs and classes still gated on declaration |
| `Visitors/ComputedPropertyCandidacyTests` | computed-property seeding | get-only / non-static / pure / assertable gates; bare `self` on a value type; synthesised vs declared `rawValue` |
| `Export/DroppedSeedReportTests` | fix 9 | the manifest reports its own losses, and the report agrees with what the formatter actually discards |

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

### Fix 3′′ — the follow-on, and the hypothesis that was itself a tautology

The write-up above recorded a next step as a hypothesis to measure rather than
build: `Set(result) ⊆ Set(RuleIdentifier.allCases)`, a selection out of a
`CaseIterable` domain.

**That hypothesis was wrong, and it was wrong in the most embarrassing available
way — the proposed law is a tautology.** Every value of a payload-free
`CaseIterable` enum *is* one of its cases, so `Set(result) ⊆ Set(E.allCases)`
holds by the type system for every implementation that compiles. Building it
would have added a fifth `f(x) == f(x)` dressed as a finding. Writing the law
down before writing the code is the only reason it was caught.

**The real law was already on the page.** The docstring surface's output for
`resolveRules` names it: *"given optional CLI **overrides**"* — i.e. L6.4 of the
frozen key, *an explicit value wins*. And it is structurally legible, not merely
documented: `cliRuleIdentifiers` has the return type **exactly**
(`[RuleIdentifier]?` → `[RuleIdentifier]?`), which is an unusual signature whose
overwhelmingly common reason is an override.

**Shipped:** `override-precedence` — `param != nil` implies `result == param`.
Refutable where it matters: the precedence lives in an early return, and early
returns migrate. Move it below the rest of the computation and the explicit value
silently stops winning, with nothing failing to compile.

**Checked for overfitting, because a template built for one function on its own
benchmark is exactly what this exercise is supposed to distrust.** Fired across
two unrelated codebases:

| Codebase | Firings | Verdict |
|---|---|---|
| SwiftProjectLint (~37k lines) | 1 — `resolveRules` | the motivating case |
| SwiftInferProperties (~40k lines) | 1 — `resolveVocabularyPath(cliOverride:…)` | **independent true positive** |

The second was not tuned for and is the same idiom (CLI > config > default), with
the law holding — a correct-today, guarded-against-tomorrow candidate in a repo
the template never saw. Two firings, two true positives, no false positives. Low
frequency is what a *specific* idiom should look like; precision is the number
that matters.

**Kept below the confidence cut on purpose.** A function may legitimately take an
optional value of its own return type and *merge* rather than replace, which is
correct code this law rejects — so it is a name-conjecture, not role-entailed,
and `Refutability`'s argument applies: a tool that proposes a false law is worse
than one that proposes nothing.

**Scored effect, re-measured rather than counted:**

| Configuration | On the day | After fix 2 | Now |
|---|---|---|---|
| `discover` default (templates only) | 1 (K8) | 2 | **2** (K2, K8) |
| `discover --include-possible` | 2 (K8, K9) | 4 | **5** (K2, K6, K8, K9, K10) |
| `discover` default, all surfaces | — | 9 | **9** (everything but K7) |

K6 is now reached with a **refutable** law under `--include-possible`, and on a
default run via the docstring advisory. `determinism` on the Config package fell
16 → 15 as `resolveRules` moved off the tautology.

### The computed-property seeding gap — three refuters, found before building

Noticed while measuring fix 3′: `category` and `suppressionKey` reach `discover`
(the `caseiterable-*` templates find them) but never entered the seed manifest.
The stated cause was that the seeding rules visit only `FunctionDeclSyntax`.

That was true and **insufficient**, and this time the probe ran *before* the
build rather than after. Three gates sat in series:

1. `PureFunctionCandidateVisitor` visits only `FunctionDeclSyntax`.
2. `PropertyTestCandidacy` had no computed-property overload — every entry point
   takes a `FunctionDeclSyntax`.
3. **And even wired up, it would have reached neither target.**
   `SelfAccessAnalyzer.accessorReadsOnlyImmutable` refused both:
   - `category` is `switch self`, and the getter path *hard-coded* bare `self` as
     disqualifying — although `instanceShape` already treats it as an ordinary
     read for a value type, because `self` **is** the value a test constructs.
   - `suppressionKey` reads `rawValue`, which is `RawRepresentable`'s synthesised
     accessor rather than a declared stored property, so it fell through to the
     assume-the-dangerous-one branch.

Measured, not assumed: a probe reported `pure=true readsOnlyImmutable=false` for
both before any change. Fixing only (1) and (2) would have shipped a change that
reached nothing — the Finding A/C failure a fourth time, avoided by spending one
probe.

**Fixed:** a computed-property candidacy overload (get-only, non-`static`, pure,
assertable return, reads only immutable state) reporting `.ofSelfAndInputs` —
a test must build the enclosing value first, and the argument list is simply
empty. Bare `self` now resolves through the same value-type rule the method path
uses, and a *synthesised* `rawValue` is treated as immutable while a declared
mutable one still refuses. The clean-method catalog is threaded through rather
than accepted and ignored.

**Measured on the subject: 600 → 662 seeds (+62), nothing removed.** 58 distinct
computed properties became visible to the manifest, `suppressionKey` and
`category` among them.

What this buys, stated precisely — and narrower than the first draft of this
paragraph claimed. It is a **linter-side reach** gain, not a scored-row gain.
Both K2 and K10 were already reached by the `caseiterable-*` templates through
*unseeded* discovery. Under `--seeds` focus, measured on the Models package:

| | old manifest | new manifest |
|---|---|---|
| `caseiterable-key-injectivity` (K2) | surfaced | surfaced |
| `caseiterable-case-coverage` (K10) | **dropped** | surfaced |

K2 already survived focus without being seeded, because it is role-entailed and
the refutability rescue keeps such laws rather than let a filter take the run to
zero. K10 is not role-entailed, so nothing rescued it — seeding `category` is
what makes it survive. **One law recovered on the seeded path**, not two, and the
scored table is unchanged either way.

### Fix 5 — built, measured, reverted

Toolchain finding 7: the docstring advisory reads only the function's own doc
comment, so `CleanInstanceMethodCatalog.build(from:)` is paired with *"Resolves
the catalog over every parsed source in the project"* — a restatement of the
signature — while the law sits one declaration away on the **type**: *"Resolution
runs to a fixpoint, so a chain resolves regardless of declaration order, and a
cycle simply never promotes."* That is the sentence K1's property was written
from.

Built end to end: `TypeDecl` gained a doc comment (it captured none), the scanner
populated it at all five declaration sites, the pipeline threaded it, and the
advisory attached it — gated to functions that *produce* the type, so a type's
sentence could not be sprayed across every method it declares.

**The mechanism worked. The selection did not.** A type's doc comment is an
essay: rationale, headings, a worked example, and the contract somewhere inside.
`CleanInstanceMethodCatalog`'s runs past 1500 characters. Handing that back
defeats an advisory whose promise is *here is the sentence*, so the prose has to
be **selected** — and two heuristics failed:

- **First cue-bearing sentences**: returns two paragraphs of motivation. The
  contract is stated *after* the rationale, which is how people write.
- **Highest cue density**: returns three rationale sentences, and neither law.

Measured outcome: it fires on **2 functions across ~37k lines**, and on the one
case that motivated it, it surfaces the wrong prose. A pointer that reliably
points at the wrong sentence spends the reader's trust — the same argument
`Refutability` makes about crying wolf, applied to advice rather than laws.

**Reverted.** The gap is real and the diagnosis holds; the blocker is not access
to the type's prose but *finding the claim inside it*, which is a text-ranking
problem this heuristic vocabulary does not solve. Recording it as measured and
declined, in the same spirit as the whole-project `try` resolver.

**Second attempt, killed by a pre-check rather than a revert.** The obvious next
selector was "lift the sentence under a `## Soundness` / `## Contract` heading",
proposed on the strength of `CleanInstanceMethodCatalog`, which has exactly that
heading. Measured across three repos before writing any code:

| Repo | Type docs | With any `##` heading |
|---|---|---|
| SwiftProjectLint | 465 | 26 (5%) |
| SwiftInferProperties | 606 | 4 (0%) |
| SwiftPropertyLaws | 92 | 0 (0%) |

Contract-*named* headings — `Soundness`, `Contract`, `Guarantees`, `Invariants`,
`Laws` — total **two across all three repositories**. The real heading vocabulary
is bespoke prose: "Why this exists", "The gap", "Cross-file dispatch", "Collision
policy", "Naming choice". There is no convention; there was one file, generalised
from.

That is the same error as the cue-subset probe an hour earlier — a rule formed
from the case in hand rather than from the corpus — and the only difference is
that the check ran first and cost two greps instead of a build and a revert. Both
failures argue the same thing: *measure the vocabulary, not the example.*

**Fix 5 is closed, not deferred.** Both available selection strategies are
measured and dead. What would solve it is ranking sentences by whether they state
a claim *about a value*, which is a semantic judgement this cue vocabulary cannot
make — a real capability, out of proportion to a feature that fires on 2
functions in ~37k lines.

**A process failure worth recording too, because it is the one this project keeps
naming.** The density ranking was validated offline against a **hand-written
subset** of the cue phrases rather than `contractCues` itself, and against that
proxy it looked like it worked — it surfaced both law sentences. Run with the
real vocabulary it surfaced neither. That is Finding C exactly ("verified on a
`YAMLConfig`-**shaped** probe"), committed while invoking the discipline that
forbids it. The probe has to use the real thing, or it is not a probe.

### Fix 6 — declined, and the fix-list entry was wrong

*"Rank seeds by production call-site count. The top-scored Config suggestion is
on `extractSwiftBasename`, which has zero production callers."*

**The premise does not survive scrutiny, and the motivating example refutes it.**
That same `extractSwiftBasename` is where a property found a real doc-vs-code
drift — the `.swift`-stripped-everywhere bug. Under fix 6 it would have been
demoted. The one case that inspired the ranking is a case the ranking would have
hurt.

More generally, call-site count is a poor proxy for property-test value. A pure
*leaf* kernel with one caller is arguably the better subject — pure leaves are
what property tests are good at — while a heavily-called orchestrator is usually
where the impurity lives. Ranking by callers would push the best candidates down.

The real concern buried in the original note was **dead code** — zero production
references — which is a narrower claim with a different remedy: delete it, not
test it later. That is a lint rule, not a seed-ranking feature, and it would need
the same new machinery: `knownProjectFunctions` is a `Set<String>` of *declared*
names, so there is no call-site index and one would have to be built.

**A note on the measurement, because it failed three times.** Attempting to size
the low-value population with text tooling produced three bad numbers in a row:
an unvalidated regex; a test-file classifier matching `"/Tests/"` against paths
that begin `"Tests/"`, so every test file counted as production; and a residual
disagreement with `grep` that was never reproduced. No number here is trustworthy
and none is quoted. Same failure family as the cue-subset probe above — a text
proxy taken on trust — and the right response was to stop at three rather than
try a fourth variant.

Declined on the design, not on the measurement: even a perfect count would be
ranking by the wrong signal.

### Fix 7 — built, measured, reverted: naming is the wrong instrument

*"Require a shared label stem (not just type symmetry) for `round-trip` pairing."*

**The noise is real and worse than the entry says.** `initializerPairAdmissible`
gates only synthetic initializers — `return true // neither half is a synthetic
init — no gate` — so two ordinary functions pair on type symmetry alone. Measured
spurious pairings: 1 in SwiftProjectLint (`extractSwiftBasename ↔ realPath`) and
**17 in SwiftInferProperties**, every one of them `(String) -> String` against
`(String) -> String`, with `codableRoundTripGenerator` matched against five
unrelated helpers. Same-type endomorphisms pair combinatorially: the candidate
set is *every same-typed function*, so the shape constrains nothing.

A gate was built for exactly that case — requiring an inverse-name signal only
when both halves are endomorphisms on the same type, leaving cross-type pairs
untouched so the cycle-4 posture held where its reasoning holds. It worked on the
stated target: **1 → 0** and **17 → 4**, the survivors all cross-type.

**And it costs real signal, which the existing tests proved.** Two failures, and
neither was a fixture-naming quibble:

- `ProtocolCoverageVetoIntegrationTests` pins `minimumCapacity(Int) -> Int`
  against `scale(Int) -> Int` surfacing as a round-trip — its own comment reads
  *"Score 30 from type-symmetry alone, **no curated name bonus**"*, and it is
  labelled *"the cycle-4 false-positive case in end-to-end form"*. The project
  met this exact noise before and answered it with a **shape** gate (V1.8.1),
  deliberately not a naming one.
- The curated algebraic survey corpus lost a `round-trip` recorded as
  `measuredDefaultFails` — a law that was executed and **disproven**. The gate
  would stop a real refutation from ever being proposed.

So the hypothesis behind fix 7 — *genuine `T -> T` inverse pairs are exactly the
ones a name identifies* — is false, and the counterexamples were already sitting
in the test suite before it was written. Reverted.

**What the entry got wrong.** It named the instrument, not just the problem, and
the instrument had already been considered and rejected here twice. The noise
deserves an answer; the answer wants to be a shape or semantic gate in the
V1.8.1 mould, not naming. Recorded as measured and declined, with the residual
noted: even after the endomorphism blowup, the four surviving cross-type pairs in
`SwiftInferProperties` also look spurious, which is a separate precision problem
this fix never addressed.

### Fix 9 — shipped, with a different instrument than the entry named

*"Surface findings that damage the seed path separately from ordinary lint
output."*

The problem is the sharpest single finding in this road test: the linter reported
the `symbol`-dropping rebuild in its own default output, and the finding went
unread among thousands. But a **separate lint section** is the wrong remedy — it
still asks a reader to notice a finding and connect it to a symptom they have not
seen yet, which is the step that already failed once.

What actually fails is narrower and mechanical. `PBTSeedsFormatter` discards any
seed-bearing finding whose `symbol` is unresolved — correctly, since the manifest
names *places* and a place without a name is not one — and says nothing. The
output stays valid JSON, still exits 0, and is simply shorter than the run behind
it. A consumer cannot tell a project with fewer candidates from a project whose
candidates fell out on the way.

So the loss is reported **where it happens**: `droppedSeeds(in:)` counts what
`format` will discard, per rule, and the CLI writes a notice to stderr. That is
the same channel and the same argument as the existing skipped-scope notice —
*"a clean-looking result is misleading if whole first-party packages were never
analyzed"* — which this codebase had already reached for once, in the same shape,
for the same reason.

**Measured honestly: on this subject the notice fires zero times.** The
`applyOverrides` fix removed the only source, so nothing is dropped today. This
is a regression guard, not a live catch — the same category as the
`suppressionKey` injectivity law, and worth exactly what that is worth: the next
rule that forgets to populate `symbol` announces itself instead of quietly
shortening the manifest.

A test pins the report against the formatter's own behaviour, so the two readings
of "what counts as droppable" cannot drift. A notice that disagreed with the file
beside it would be worse than none.

### Fix 8 — shipped; the smallest entry, and the only one whose remedy was right

*"Scope the `--seeds` advisory to `--sources`."*

Reproduced first: the refactor-pending block was **byte-identical** across four
different `--sources` values, naming files in all seven packages every time,
while every other part of the focus reporting — the focus ratio, the
private-function notes, the role-entailed warning — scoped correctly. One block
had been missed.

Now filtered to the files the scan actually saw. Per-scope counts on this
subject:

| Scope | Kernels |
|---|---|
| Core | 1 |
| Models / Config / Registry / Engine | 1 / 11 / 4 / 7 |
| Visitors / IdempotencyRules / Rules | 16 / 2 / 156 |
| **sum** | **198** |

**Checked for losslessness rather than assumed.** 198 across the eight scanned
scopes, plus exactly 6 in `Sources/App` — the target this road test deliberately
excludes — against a manifest of 204. Nothing is dropped by the path matching;
the residue is genuinely out of scope. Had those numbers not reconciled, the
scoping would have traded a noisy answer for a quiet wrong one.

The matching aligns on a path separator, so a seed in
`Visitors/Support/Policy.swift` cannot be claimed by a scan of
`Rules/Support/Policy.swift`, and `MyLoader.swift` cannot absorb `Loader.swift`.
Bare-basename matching would collide across targets; equality would never fire,
since seed paths are relative and scanned paths absolute.

**And when nothing is in scope it says so**, rather than emitting an empty
section: a listing that vanishes reads as "no kernels here", which is a different
claim and usually a false one. Verified against a scan of `Sources/CLI`, which
correctly reports 204 pending seeds all belonging to other targets.

Worth noting against the rest of this list: fix 8 was the only entry whose stated
remedy survived contact unchanged. It was also the entry that named a *defect*
rather than a *design* — "this block ignores a flag the others honour" — which is
the difference the other nine kept demonstrating.

## Re-run after the fixes — what the toolchain now offers

Run again once fixes 1–4, 8, 9 and the computed-property seeding had shipped.
**Not a scored measurement**, and it cannot be compared with the 1-of-10 / 9-of-10
figures above: this is the second pass over a tree the tools have now been tuned
against, which is exactly what Appendix C says to fork a fresh fixture to avoid.
Read it as a coverage investigation.

Manifest: **664 seeds** (460 analysable), no drops reported. Unseeded `discover`
across the scope: **52 proposals**, of which **43 name symbols no property test
exercises**. By whether the law can actually be run today:

| | Count | |
|---|---|---|
| DERIVED | 17 | generator synthesised |
| RECIPE | 24 | SwiftSyntax carrier; construction recipe attached (fix 4) |
| NONE | 2 | `some SyntaxProtocol` (declined by design); a carrier outside the scanned scope |

So 41 of 43 are actionable, against 17 before fix 4 — the largest practical change
in this exercise.

### What "actionable" does *not* mean

The number invites a conflation worth heading off, because the first draft of this
section made it.

| | predicate | law-bearing template |
|---|---|---|
| DERIVED (17) | 14 | 3 × idempotence |
| RECIPE (24) | 21 | 3 × monotonicity |

**35 of the 41 are `predicate`, whose only entailed law is totality.** A generator
solves the *input* problem; it does not supply a *law*. Those are independent
halves and fix 4 moved only the first. The tool is explicit about the second, in
the caveat it prints on every predicate: *"THE INTERESTING LAW IS NOT FREE, and no
tool can invent it for you. State that reference definition in one English
sentence."*

The two candidates written up below are the evidence. `LayerPolicy.contains` was a
DERIVED predicate: the toolchain supplied a candidate, a generator and the
totality obligation. Prefix semantics, monotonicity in `paths`, and the
empty-string hazard came from reading the one-line implementation. For
`isGeneratedFile`, the five-line boundary came from its docstring. Neither law was
proposed by a template.

So the honest ledger for a reader planning work: **41 candidates**, of which
roughly **6 arrive with a law attached** (idempotence and monotonicity, both
name-conjectured and still owing a sanity check) and **35 arrive with a generator
and an obligation**. And candidates are not tests — the three suites below are 22
tests over 3 candidates.

### Two of them written up

Both were candidates the frozen answer key **walked past** and the tools
surfaced — recorded as unscored key defects earlier, and now covered.

- **`LayerPolicy.contains(relativePath:)`** — prefix membership, monotone in
  `paths` (an implementation that intersected rather than unioned would *shrink*
  a layer when a user adds a folder, silently un-enforcing the boundary), and the
  hazard that `paths: [""]` claims every file. That last one is the **same shape**
  as `DirectoryNode`'s empty-pattern case found earlier in this road test: prefix
  matching meeting the empty string, twice, in unrelated code.
- **`ProjectLinter.isGeneratedFile(at:)`** — the docstring's **five-line
  boundary**, a number living only in prose and a `prefix(5)`. A marker on line 5
  counts and on line 6 does not; the code honours that today. A false positive
  here means a hand-written file is never linted, which is a confident zero with
  no output at all.

And one from the syntax-predicate family, which is the law of the batch:

- **The two closure-escape policies must agree.** `OnceReachClosurePolicy` and
  `EscapingClosurePolicy` are separate implementations carrying their own
  `calleeNames`, and the first one's doc states the contract: *"the same set as
  the idempotency rule visitors, so reach inference and direct-call detection
  agree on what counts as a retry boundary."* Nothing enforced it. Add a framework
  to one list and not the other and the two disagree about where a retry boundary
  is, with no test failing and no diagnostic saying so. They agree today.

That last one is what the whole exercise is for: stated in prose, refutable, and
invisible to any single-predicate law.

### Toolchain finding 10 — a law the repository already disproves is proposed at full score

Found by reading the re-run's own output rather than by measuring anything, which
is worth noting: it had been sitting in the file for two runs.

`discover` on the Config package proposes **`idempotence` on
`extractSwiftBasename`** — `f(f(x)) == f(x)`, Possible tier, score 35. That
function was *fixed during this road test* to strip only the trailing extension,
which made it deliberately non-idempotent, and the fix shipped with a test saying
so in as many words:

```swift
@Test
func extractionIsDeliberatelyNotIdempotent() {
    let once = FileAnalysisUtils.extractSwiftBasename(from: "a.swift.swift")
    #expect(once == "a.swift")
    #expect(FileAnalysisUtils.extractSwiftBasename(from: once) == "a")
}
```

So the tool proposes a law that a test in the same repository **executes and
disproves**, at full confidence, with no indication that the question has been
asked and settled.

**Not a test-discovery problem — measured.** The obvious explanation is the
layout: TestLifter walks up to `<package-root>/Tests/`, this scan targets a
nested package that has no `Tests/` directory, and the real suite lives at the
repository root. Re-running with `--test-dir Tests` pointed straight at it
changes nothing — still two `idempotence` suggestions, the refuted one among
them. TestLifter's job is to *lift* laws out of example tests to strengthen
suggestions; there is no channel by which a test **refutes** one.

**The counter-evidence channel exists and is manual only.** Every suggestion
prints `Suppress: // swiftinfer: skip <identity>`, and `.swiftinfer/decisions.json`
records triage. Both require a human to act. That is a defensible design —
a tool silently retiring its own proposals would be its own failure mode — but
there is a real difference between *no decision has been recorded* and *a test in
this project asserts the opposite*, and only the first is currently modelled.
This repository has no `.swiftinfer` directory at all, so nothing has been
recorded, which is the state most projects will be in.

**Why it belongs with the rest of these findings.** It is the third instance of
one pattern, and the pattern is the most durable thing this road test produced:

| The information | Where it sat | Why it never arrived |
|---|---|---|
| the `symbol`-dropping bug | the linter's own default output | 804 findings, no way to mark the one that breaks the pipeline (fix 9) |
| `CleanInstanceMethodCatalog`'s fixpoint law | the **type**'s doc comment | the advisory reads only the function's own docstring (fix 5, declined) |
| `extractSwiftBasename` is not idempotent | a **passing test** in the same repo | no refutation channel from tests to proposals |

Each time the knowledge was already in the project and the tool could not reach
it. That is a different failure from "the catalog has no law for this shape" —
and, on this evidence, a more common one.

## Second pass (2026-07-26) — the handoff, and the defaults problem this write-up named

Four changes shipped after the section above. Ordered by what they moved, not by
effort.

### The volume problem — the Net section named it and pointed at the wrong flag

"It is a **defaults** problem" was right. The fix it proposed —
`--docstring-advice` — was the smaller of the two defaults problems in this
output, and the larger one was measured in this very document without being
recognised as fixable.

A default run prints **884 findings, of which 672 are the two property-test
candidate rules**. That is 76% of everything the linter says. Both rules are
working correctly: there really are 464 pure functions and 208 pure closures.

The cost is already written up above, under *"the part that stings"*. The
**Lossy Struct Rebuild** finding — the correct diagnosis of bug 1, at the right
line, in default output, which nobody read — sat at **line 1438 of a
1768-line report**. It is now at **line 197 of 432**.

| | Before | After |
|---|---|---|
| Default text report | 1768 lines | **432** |
| Position of the bug-1 finding | line 1438 | **line 197** |
| Findings detected | 884 | 884 |
| Seeds exported | 669 | 669 |

**The constraint that shaped it:** the CLI computes its findings *once* and hands
the same array to the report formatter and to `--format pbt-seeds`. So the
obvious reading of "make the candidate rules opt-in" — disable them — would have
emptied the seed manifest and stopped the linter feeding `swift-infer` entirely.
This had to be presentation-only. The candidates are still detected, still
counted in the summary, still exported, still exit-code relevant; they are
counted and named in a footer instead of printed one per line, and
`--categories testability` restores the listing.

**It does not move the scored row, and saying otherwise would be the same error
this write-up keeps catching.** That row measures what `discover` proposes. This
changes what a human sees in the *linter's* report. The two are different
surfaces, and 1/10 is still 1/10.

### The kernel rule was scoring zero, and nobody had checked

`Extractable Total Kernel` — the rule with the most prescriptive advice in the
family, the one that says *lift this into a value type* — returned **0 findings
on 60k lines**. Not "this code is clean": its gates want an arithmetic operator
reaching a bound, and this codebase's impure methods enumerate directories and
derive paths. `dropFirst(prefix.count)` is a slice with no arithmetic in it
anywhere.

The sting is the same shape as bug 1. **Both bugs this road test found were
path/preservation shapes** — a `.swift` suffix stripped from the wrong end, a
field dropped on rebuild — and the rule built to find trapped logic was looking
straight at that family with nothing to say.

A second shape (a path derivation that *governs* a decision) took it from 0 → 2
here and 1 → 9 on SwiftInferProperties, losing nothing. Eight of those nine are
one `findPackageRoot` walk-up inlined in eight files, welded to a hardcoded
`FileManager.default`.

Two things about it are worth recording because they were found by measuring
rather than reasoning. The `>= 2` derivations threshold is **not** what provides
the precision — relaxing it to 1 changes nothing on either corpus, and the doc
comment now says so instead of a false-positive rate I had asserted without
measuring. And the first cut reused a helper that treats any comparison
containing `+` as evidence; `+` on strings is concatenation, so it vouched for
derivations it had nothing to do with.

### The manifest now says what the code *is*

`PureClosureCandidateVisitor` has always known which shape it found — it picks
its law sentence off exactly that distinction, calling one a comparator and
another a predicate. The manifest carried `{file, line, symbol, rule, kind}` and
threw the classification away, so all 204 of those findings reached `swift-infer`
as an undifferentiated `extractable-kernel` at a line number.

This is the same species of defect as the one `PBTSeedsFormatter` already
records — *"a finding the linter prints but does not seed is a finding the
pipeline does not have"* — except it was not the finding being dropped, it was
the finding's **content**.

The consumer had been asking for it in its own warning text, which is the part
that should have been noticed sooner:

> the seed manifest does not name the subject, but this law is owed by the
> code's **ROLE** … The manifest SHOULD have named it: this is a LINTER gap.

**207 of 669 seeds** now carry a role — 182 predicate, 15 transform, 4
comparator, 4 reducer, 2 normalizer. The refactor-pending listing ranks entailed
roles first and names the payoff:

```
…:31: inside `filter` — extract it into a named value type… It is a predicate —
it owes totality… Extracting it PAYS: `discover` will then propose the
`predicate` law, which a correct implementation cannot fail.
```

**Roles are not template names, and were deliberately not merged with them.**
`Refutability.roleEntailedTemplates` holds *law* names (`filter-subset`,
`caseiterable-key-injectivity`); a role is what the *code* is. They overlap on
three cases and are different vocabularies. Merging them would prevent a
spelling mismatch by asserting a correspondence that does not hold.

What can actually rot is the **entailment claim** — that comparator, predicate
and partition are laws correct code cannot fail. The two repositories are
versioned independently and pin their one shared dependency
(`SwiftEffectInference`) at *different revisions*, so there is no compiler
between them. A comment saying "these must not drift" is not a mechanism, so the
claim is pinned by tests at both ends: `SeedRoleEmissionTests` here, and
`SeedRoleContractTests` in SwiftInferProperties checking each role against
`Refutability.roleEntailedTemplates` itself.

**What it could not do yet, and why.** The obvious use of a role is a *join*:
match it against what `discover` proposed at that location, and say whether a
missing law is a linter gap or a template gap — the question the two tools
answered by blaming each other. That was blocked, and checking the manifest is
what revealed it: every seed carrying a role was an `extractable-kernel`, because
roles came from the two kernel rules and `pureFunctionCandidate` classified
nothing. A kernel's symbol names the enclosing impure method, so there was
nothing to join on.

*Unblocked below* — and the join's first run contradicted the prediction in this
paragraph. See
[The classification, and the prediction it inverted](#the-classification-and-the-prediction-it-inverted).

### The classification, and the prediction it inverted

The section above ends by naming the next increment: teach `pureFunctionCandidate` to classify its
findings, so analysable seeds carry a role and `swift-infer` can say whether a missing law is a
**linter** gap or a **template** gap, instead of the two tools blaming each other.

`DeclaredRoleClassifier` does the classifying — signature-only, since a declaration has no call site
the way a closure does. It reaches **215 of 468** analysable seeds: 201 predicate, 14 normalizer,
and **zero comparators**, because nothing in this codebase is a `compare`-shaped two-argument
`Bool`.

Then the join was run, and it went wrong twice — both worth recording, because the second one is the
actual finding.

**First, the join logic was mine and it was wrong.** Comparing a role name against a template name
flagged `extractSwiftBasename` and `realPath` as gaps. They are not: the linter called them
`normalizer`, and `discover` proposed `idempotence` and `round-trip`, which *are* the normalizer
laws. Only entailed roles have a one-to-one template name; conjectured roles map to several. Those
two were agreements being read as failures by a check that assumed an identity that does not hold.

**Second, the real disagreements pointed the opposite way from the prediction.** The two genuine
mismatches — `isSuppressed` and `pathMatches`, both seeded as predicates with no law proposed — are
`private static func`. `swift-infer` declines them deliberately, under a `RestrictedFunction`
concept whose own doc comment says: *"`private` or `fileprivate`. Not even `@testable import`
reaches these."*

The consumer was right and the linter was wrong. The diagnostic predicted to surface a **template**
gap surfaced a **linter** one on its first run.

And it was not two functions. A full count:

| | Before | After |
|---|---|---|
| Seeds marked analysable | 468 | **154** |
| …that no test could call | **316** | 0 |
| Reported as `restricted-function` | — | **319** |

**Two thirds of the manifest's actionable half named a function no test could reach.** The linter
had been telling `swift-infer` to go analyse things, `swift-infer` had been quietly refusing, and
neither tool could see the disagreement until both stated their beliefs in the same vocabulary.
That is the whole argument for the `role`/`kind` handoff, arriving as evidence rather than as a
design claim.

The knowledge was, once again, **already in the project**. `PropertyTestCandidacy`'s own doc comment
says `@testable import` exposes `internal` and not `private`. `couldBePrivate` and
`couldBePrivateMember` exist *specifically* so a scope rule cannot advise a reader into an
untestable corner. The seeding path never consulted any of it — the fourth instance in this document
of a fact the project held and the pipeline could not reach.

Restricted seeds are reported, not dropped, for the reason `RestrictedFunction` already argues: a
private helper is often the *best* property target. The obstacle is an access level, which is a
human decision — the same posture as an extractable kernel, a different obstacle, so a separate
listing with its own instruction:

```
12 restricted function(s) — pure, total and named, but `private` or `fileprivate`, so no test
can call them…
  …InlineSuppressionFilter.swift:119: `isSuppressed` — make it `internal` to property-test it.
  It is a predicate — it owes totality: an answer for every input its type admits.
```

**Still not a change to the scored row.** 1/10 default, 9/10 across surfaces. What moved is that the
manifest now describes itself honestly: a consumer narrowing to its analysable set gets 154 real
subjects instead of 468, of which two thirds were unreachable.

### The v1 shape tolerance is gone

`kind` used to default to `.pureFunction` when absent, for manifests written
before the field existed. None can exist — the producer's version is a constant
2 and manifests are generated on demand rather than archived — and the default
was **silent** on the one field whose misreading the v1 → v2 bump was created to
prevent. A seed read as `.pureFunction` is one a consumer may narrow discovery
onto, and doing that to an uncallable kernel produces exactly the confident zero
the bump existed to stop. It is now a parse error naming the file. The version
*number* warning is untouched — that is forward compatibility, a different
mechanism.

### What none of this changed

The scored row. 1/10 on a default `discover`, 9/10 across shipping surfaces,
exactly as before. Every change above is to the **handoff and the presentation**
— which findings reach a reader, and how much the manifest tells the next tool.
The template catalog proposes the same laws it did on 2026-07-24.

## Net

The loop found **two real bugs and four clean guards** on a codebase whose 2931
tests were green throughout, which is the ratio Appendix C predicts: applied to
real code, the practice returns *correct-today, guarded-against-tomorrow* about
as often as it returns a defect.

The scored answer is **1 of 10 on a default run, 9 of 10 across surfaces already
shipping** (see the correction under The headline — the 2 was the
`--include-possible` figure). That gap is the actionable result, and it is not a catalog gap — it
is a **defaults** problem. The single most valuable change in the table above is
turning on a feature the book currently describes as unverified.

And the honest counterweight, in the run's own words: the one law the template
catalog proposed for the function that actually had a bug was a law the bug
satisfied.
