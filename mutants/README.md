# Mutation / regression corpus (private)

A hand-authored mutant corpus for **sharpening the linter itself** (Chapter 30
§30.4.4). SwiftProjectLint is a SwiftPM monorepo — the rules live under `Packages/*`
— so mutants patch a detector's own source and are killed by the root package's
`CoreTests`. Not a scored benchmark — no frozen answer key.

Each mutant is a reversible patch (`patches/<id>.patch`). The runner applies one,
builds, runs its named killer test via `swift test --filter`, checks the outcome,
and reverts. SwiftPM targets test methods precisely, so a kill is attributed by
construction.

## Run

**Rebuild before measuring anything with the binary afterwards.** The runner reverts each mutant's
*source* and moves on, so the build products left behind belong to the **last mutant**, not to
`main`. A corpus measurement taken straight after a run is a measurement of that mutant.

This is not hypothetical: a sweep run immediately after `kernel-storage-test-inverted-to-denylist`
reported two repositories lower than the truth — exactly that mutant's two false exemptions — and
the number was one step from being published. It was caught only because the shortfall matched the
mutant's own documented effect. `rm -f .build/build.db && swift build --product CLI` first, or copy
the binary *before* running the corpus.


```sh
mutants/run-mutants.sh                       # all mutants
mutants/run-mutants.sh kernel-threshold-too-high
```

Requires a clean working tree.

## The corpus (`manifest.json`)

Two shapes. The first four target the `ExtractableTotalKernelVisitor` — the §15.2.5 "a total kernel is
trapped in this impure method; lift it" rule — on both sides of the
precision/recall line:

| id | shape | expected | killer |
|---|---|---|---|
| `kernel-governs-always-false` | detector-recall | killed | `chunkingKernelIsCandidate` |
| `kernel-scans-pure-functions` | detector-precision | killed | `pureFunctionIsNotReported` |
| `kernel-worth-extracting-always-true` | detector-precision | killed | `arithmeticWithoutAGoverningUseIsNotReported` |
| `kernel-ignores-ambient-state` | detector-precision | killed | `continuousClockElapsedIsNotAKernel` |

Forcing `governs` false makes the rule miss a real kernel (recall); inverting the
purity guard makes it scan pure functions that are already candidates elsewhere;
making `isWorthExtracting` always true makes it flag merely-stored arithmetic;
removing the ambient-state guard makes it report `ContinuousClock.now - lastActivityAt`
as a kernel that "depends only on its parameters and locals", which is false (all
precision). All four verified killed.

(An earlier pair of threshold/conjunction off-by-one mutants *survived* — the test
kernels sit clear of those boundaries, so no test pinned them; they were replaced
with the decisive mutations above rather than shipped as false guards.)

**A patch can go stale, and two of these did.** `isWorthExtracting` was later split
into `isArithmeticKernel || isPathKernel`, and both `kernel-governs-always-false` and
`kernel-worth-extracting-always-true` stopped applying. That is a *structural* drift,
not a line-number one: regenerating `kernel-worth-extracting-always-true` at the old
site would have forced only the arithmetic half true and quietly tested less than its
label claims. When a patch fails to apply, re-read what the mutant is supposed to say
and re-express it against the current shape — do not just re-anchor it.

Re-anchoring is right only after that check. `kernel-scans-pure-functions`,
`split-type-members-assumed-visible` and `platform-prefix-set-widened` later stopped
applying on context alone: a comment was rewritten beside the guard, and helpers were
widened from `private` for generated tests. The logic under each was unchanged, so each
makes the same edit on the same line. `kernel-storage-test-inverted-to-denylist`, which
went stale at the same time, needed re-expressing (see its section).

The runner is loud about this rather than silent: an apply failure is reported as
`APPLY FAILED`, recorded with outcome `apply-failed`, and exits non-zero. A stale
corpus shows up as a failing run, never as a passing one.

## Adding a mutant

1. Make the buggy edit; 2. `git diff -- <file> > mutants/patches/<id>.patch`;
3. `git checkout -- <file>`; 4. add an entry to `manifest.json`.

### The `ComputedPropertyViewVisitor` gates

Three more, added when the rule was worked from 63 findings to 0 across the corpus. All three are
about a gate rather than about detection: each leaves the rule reporting, and changes only *which*
properties it declines.

| id | shape | expected | killer |
|---|---|---|---|
| `toolbar-not-a-decomposing-container` | detector-precision | killed | `toolbarItemGroupContentsAreNotReported` |
| `split-type-members-assumed-visible` | detector-precision | killed | `siblingInAnotherFileIsNotReported` |
| `same-file-extension-treated-as-hidden` | detector-recall | killed | `sameFileExtensionIsMerged` |

The third is the one worth having. It is the over-gate that the *fix* for an under-gate can
introduce: `hiddenMembers` stops subtracting the extensions visible in the file being analysed, so
every type with a same-file extension goes silent. Nothing about the rule's output looks wrong —
it simply reports less — which is the character of every finding in this shape.

### Engine wiring

One mutant in a third shape, and the only one here that is not about a detector's
judgement at all.

| id | shape | expected | killer |
|---|---|---|---|
| `prescan-catalog-built-then-dropped` | engine-wiring | killed | `everyCatalogIsInjectedPerFile` |

It removes one assignment, so a catalog the pre-scan spent real time building never
reaches the visitor that reads it. **Nothing about the output looks wrong** — the linter
reports fewer property-test candidates, correctly formatted, with no error anywhere, which
is indistinguishable from a corpus that has fewer candidates in it. That is why its killer
is a structural test over the two functions' source rather than an assertion about any
finding: it is the one bug shape in this corpus that no assertion about a rule's output
could catch.

### The package purity

Six more in the same shape, from wiring SEI's construction facts through `ProjectLinter`. The facts
are built at most once per pass and bound as a task-local (`PackagePurity.current`) around the
pre-scan, the per-file task group and cross-file analysis; every `PurityInferrer()` reads it. Each mutant breaks
one link of that, and each is a bug whose output looks like a corpus with more candidates in it.

| id | shape | expected | killer |
|---|---|---|---|
| `purity-context-not-bound` | engine-wiring | killed | `constructionRefutesThroughProjectLinter` |
| `purity-binding-excludes-prescan` | engine-wiring | killed | `constructionRefutesThroughProjectLinter` |
| `purity-universe-includes-tests` | engine-wiring | killed | `testNamesakeDoesNotRefuteProduction` |
| `purity-universe-unsorted` | engine-wiring | killed | `witnessIndependentOfDiscoveryOrder` |
| `purity-universe-follows-reporting-scope` | engine-wiring | killed | `nestedPackageTypesAreEvidence` |
| `purity-per-file-reparses` | engine-wiring | killed | `perFileRulesJudgeTheSharedTree` |

The second is the catalog-dropped bug again in a new place: hoist the pre-scan above the binding
and the clean-method catalog and the one-hop join are built by unconfigured oracles while the
per-file rules judge with the facts, so one run disagrees with itself. Its killer asserts the join
and the catalog sites separately, and either alone kills it. The last is the one the facts make
possible: SEI types an assignment target by node identity, so a per-file pass that re-parses its
file answers a different question from the tree the facts were built from.

### The universe's edges

More in the same shape, from the adversarial review of that wiring and the shared spec's first
amendment, which both consumers implement identically. Each puts back a way the universe disagreed
with what the compiler builds.

| id | shape | expected | killer |
|---|---|---|---|
| `purity-universe-classifies-symlink-target` | engine-wiring | killed | `linkIntoInRootTestsRefutes` |
| `purity-universe-takes-every-nested-package` | engine-wiring | killed | `unrelatedNestedPackageDoesNotRefute` |
| `purity-universe-nested-on-drops-filtered` | engine-wiring | killed | `excludedPathIsEvidence` |

The first classifies a symlinked file at its target again: `Sources/Lib/Item.swift` linking to a
file under `Tests/` is dropped as a test file, though SwiftPM compiles it into `Lib`. The second
takes every nested package again, not only those the root compiles, and is the one whose output
looks *worse* rather than merely smaller: an unrelated `Demo/` package's namesake costs a pure kernel
its Direct Instantiation exemption, and the run gains a warning. The third survived the whole suite
when it was found: with nested packages reported, the universe reuses a walk the run already made,
and every universe test ran with them off. `excludedPathIsEvidence` and `generatedFileIsEvidence`
now run both ways, and either kills it.

`purity-universe-unsorted` was re-expressed when the shared spec's second amendment named the order:
`PackagePurity.build` takes it from `ConstructionUniverse.buildOrder`, the function both consumers
expose and assert on `Docs/construction-universe-cases.json`, so the mutant now drops that call
rather than a sort of the build's own.

### The universe's order of operations

Three more from the joint follow-up review, each a rule the code's own comments stated and no test
pinned: the whole suite passed with any one of them put back.

| id | shape | expected | killer |
|---|---|---|---|
| `purity-universe-dedup-keeps-first-seen` | engine-wiring | killed | `duplicateKeepsTheSmallestPath` |
| `purity-universe-collapses-before-classifying` | engine-wiring | killed | `testTargetLinkToProductionIsOneEntry` |
| `purity-universe-places-links-at-their-target` | engine-wiring | killed | `linkIntoUncompiledPackageCountsWhereTheLinkIs` |

The first survived because both of the test's layouts put the smaller path first on disk as well:
APFS lists `Sources/A` before `Sources/B`, so first-seen and smallest agreed. The test now adds a
layout where they disagree (`Sources/Lib` lists before `Sources/B`) and a twin that hands
`constructionSources` both orders itself, so it does not lean on the file system at all. The second
needs a test folder that sorts *before* `Sources/` — `AppTests/`, not `Tests/` — for the collapsed
entry to be the test-folder link. The third needs a link from the root's sources into a nested
package the root does not compile.

And one for each rule of the shared spec's amendments 3 and 3b, the second review's fixes. Each
puts back a way the universe disagreed with what SwiftPM compiles. All but two read as a corpus
with more candidates in it; the order mutant moves a witness, and the stack mutant kills the run.

| id | shape | expected | killer |
|---|---|---|---|
| `purity-universe-order-per-component` | engine-wiring | killed | `sharedBuildOrder` |
| `purity-universe-any-package-swift-is-a-boundary` | engine-wiring | killed | `sourceFileNamedPackageIsNoBoundary` |
| `purity-universe-ignores-xcode-project` | engine-wiring | killed | `xcodeProjectBesideTheManifestTakesEveryPackage` |
| `purity-manifest-reader-takes-source-text` | engine-wiring | killed | `dependencyPathIsReadAsSwiftPMReadsIt` |
| `purity-universe-matches-by-spelling` | engine-wiring | killed | `dependencyThroughALinkedDirectory` |
| `purity-closure-stops-at-unwalked-package` | engine-wiring | killed | `closureThroughNonProductionPackage` |
| `purity-universe-drops-reported-packages` | engine-wiring | killed | `reportedNestedPackageIsJudgedWithItsOwnTypes` |
| `purity-manifests-read-on-cooperative-stack` | engine-wiring | killed | `deepDependencyManifestIsSurvived` |
| `walk-skips-hidden-flag` | engine-wiring | killed | `hiddenFlagIsNoReasonToSkip` |
| `purity-closure-reads-package-swift-only` | engine-wiring | killed | `versionSpecificManifestDependency` |
| `purity-closure-ignores-target-paths` | engine-wiring | killed | `targetPathIntoNestedPackage` |

The first survived until the shared cases file gained `Sources/A-B/X.swift` beside
`Sources/A/X.swift`: `-` sorts before `/` under `String <` and after it per component, and none of
the eight paths before it told the two apart. `purity-universe-matches-by-spelling` is the one for
amendments H and Q together, since one resolver serves both: identity there misses the critic's
`s11` (a link to the package's directory), an absolute path through `/tmp`, and `packages/core`
for `Packages/Core`. `purity-manifests-read-on-cooperative-stack` is killed by a crash, not an
assertion — the killer's process dies with `SIGBUS` — which the runner counts as killed, as it
should.

Seven more from the shared spec's amendments 4 and 4b — the final review of #276 and the review of
#277. Three are the ways rule F's first-line test refused a manifest SwiftPM loads; each kills
exactly its own case of the killer, whose three arguments open a dependency's manifest with a blank
line, an upper-case label and a license header above a 6.0 comment. The fourth is a target path
that holds nested packages.

| id | shape | expected | killer |
|---|---|---|---|
| `manifest-tools-version-on-the-very-first-line` | engine-wiring | killed | `manifestAsSwiftPMReadsItKeepsTheClosure` |
| `manifest-label-case-sensitive` | engine-wiring | killed | `manifestAsSwiftPMReadsItKeepsTheClosure` |
| `manifest-tools-version-only-at-the-top` | engine-wiring | killed | `manifestAsSwiftPMReadsItKeepsTheClosure` |
| `purity-closure-target-path-misses-packages-under-it` | engine-wiring | killed | `targetPathOverNestedPackage` |
| `purity-closure-root-target-path-reaches-nothing` | engine-wiring | killed | `rootTargetAtTheRootReachesEveryPackage` |
| `manifest-spacing-spaces-and-tabs-only` | engine-wiring | killed | `sharedManifestRecognitionCases` |
| `manifest-prefilter-case-sensitive` | engine-wiring | killed | `sharedManifestRecognitionCases` |

The fifth is the follow-up T′: locations are relative to the root, which is `""`, so a root target's
`path: "."` resolved to a location no `hasPrefix` matched and reached nothing until the comparison
gained `location.isEmpty`. The fourth was re-expressed against the comparison's new line break.

The last two are amendment 4b (S′), from the review of #277. The first puts back the regression
amendment 4 had introduced: spacing that is only spaces and tabs, where SwiftPM takes any horizontal
whitespace, so `//\u{00A0}swift-tools-version:5.9` loads in SwiftPM and was no manifest here. The
second guards the prefilter that now spares a long `Package.swift` a regex per line: compare its
label without lowercasing and a header above `// SWIFT-TOOLS-VERSION:6.0` is filtered out before
the case-insensitive regex can see it. The shared cases file's `isManifest` section kills both. The
three amendment-4 manifest mutants were re-expressed against the new `isManifest`, and their killer
still fails exactly their own case.

`purity-universe-takes-every-nested-package` was re-expressed when discovery started awaiting the
bound on a large-stack thread (`compiledUniverse`): it now skips that call.

### The purity gate

Twenty in the same shape, one per mechanism of the gate that builds the construction universe, the
facts and the two purity catalogs only when a visitor the run executes declares that it reads them
(`PackagePurityConsumer`), withholds the rest, and redoes a pass that read something it withheld.
Each puts back a way the gate could report a finding the ungated run would not, cost a narrow run
what it was meant to save, or fail to say that it happened.

| id | shape | expected | killer |
|---|---|---|---|
| `purity-gate-declaration-dropped` | engine-wiring | killed | `declarationInventory` |
| `purity-gate-unreachable-effect-closure-undeclared` | engine-wiring | killed | `purityReadersDeclareWhatTheyRead` |
| `purity-gate-nil-plan-demands-nothing` | engine-wiring | killed | `demandIsPerVisitor` |
| `purity-gate-demand-from-cli-ids-only` | engine-wiring | killed | `narrowRunsSkipTheUniverseWalk` |
| `purity-gate-universe-always-resolved` | engine-wiring | killed | `narrowRunWithholds` |
| `purity-gate-unresolved-universe-builds-empty-table` | engine-wiring | killed | `narrowRunWithholds` |
| `purity-gate-withheld-pass-binds-unconfigured` | engine-wiring | killed | `narrowRunWithholds` |
| `purity-gate-read-does-not-trip` | engine-wiring | killed | `withheldTableTripsAtOracleCreation` |
| `purity-gate-catalog-shadow-storage` | engine-wiring | killed | `surfacesKeepOnlyWithholdableStorage` |
| `purity-gate-equality-bypasses-read` | engine-wiring | killed | `withheldCatalogsTrip` |
| `purity-gate-tripwire-records-nothing` | engine-wiring | killed | `undeclaredReadFallsBack` |
| `purity-gate-tripwire-shared-across-passes` | engine-wiring | killed | `tripwiresArePerRun` |
| `purity-gate-clean-catalog-built-on-the-join-bit` | engine-wiring | killed | `everyRuleAloneReadsOnlyWhatItDeclares` |
| `purity-gate-clean-catalog-empty-not-withheld` | engine-wiring | killed | `everyDeclaredInputIsRead` |
| `purity-gate-join-empty-not-withheld` | engine-wiring | killed | `prescanWithholdsEveryOracleBuiltCatalog` |
| `purity-gate-no-rerun` | engine-wiring | killed | `undeclaredReadFallsBack` |
| `purity-gate-rerun-reuses-derived-demand` | engine-wiring | killed | `undeclaredReadFallsBack` |
| `purity-gate-cancelled-run-returns-first-pass` | engine-wiring | killed | `cancelledTrippedRunNeverReturnsTheFirstPass` |
| `purity-gate-caller-detector-gets-catalogs` | engine-wiring | killed | `theCallersDetectorKeepsNoPurityCatalog` |
| `purity-gate-rerun-not-reported` | engine-wiring | killed | `rerunIsReported` |

The first two are the declarations. Dropping one is the mistake the gate is built to survive: the
findings stay right and the run takes twice as long, so no assertion about a finding can catch it,
and the killers are an inventory and a source scan instead. The scan is the one that matters for a
rule added later: Unreachable Effect Closure asks its oracle only `mutatesCapturedState`, which SEI
answers without the table today, and its mutant is killed by the file naming `PurityInferrer`,
whatever any corpus reaches.

The next five are the demand and what it decides. `purity-gate-demand-from-cli-ids-only` takes the
demand from the flags rather than the resolved rules, so `enabled_only` and `disabled_rules` stop
narrowing what is built; it is why the rules are resolved before discovery. The two after
`universe-always-resolved` are the unsound ones: a run that resolved no universe answers with an
empty or unconfigured table instead of a withheld one, so an undeclared read is answered silently
and nothing reruns.

The read point, the storage and equality are the three ways round `Withholdable.read`. The shadow
storage one is the case the compiler cannot see — a second stored property beside the private
state — so its killer is the structural pin that each surface stores one `Withholdable` and nothing
else.

The tripwire and the catalogs: recording nothing; sharing one tripwire across passes, which the
`precondition` stops when a rerun that withholds nothing inherits the first pass's trips; building
the clean-method catalog on the join's bit; and an `.empty` catalog where a withheld one belongs. An empty catalog looks exactly like a project with no kernels and no impure callees,
which is why `prescanWithholdsEveryOracleBuiltCatalog` reads the pre-scan's source rather than a
finding.

The last five are the rerun: returning the tripped pass, rerunning with the demand that tripped
(stopped by the `precondition`), returning the first pass of a run cancelled meanwhile, handing the
caller's long-lived detector a catalog that outlives its run, and dropping the call to the notice in
`lint`, which the CLI prints. (The CLI's own half, building and using a linter that has a notice, is
under "The CLI's rerun warning" below.)

Removing the debug `assert` in `analyzeProject` is an equivalent mutant and is not listed: it only
reports a rerun that has already happened, so no test can tell it is gone.

The gate moved two earlier mutants' sites. `purity-binding-excludes-prescan` was re-anchored when the
rules started being resolved before discovery, and again with `purity-context-not-bound` when the
binding moved into `ProjectLinter.pass`. Each makes the same mutation as before, and each is still
killed by `constructionRefutesThroughProjectLinter`.

And it took one killer's reach away. `everyCatalogIsInjectedPerFile` took the catalogs owed per file
from what `configuredDetector` primes, and the gate stopped priming the caller's detector with the
two purity catalogs, so `prescan-catalog-built-then-dropped` survived the first run of the corpus
on the gate. The test now names those two catalogs, owed per file and never primed once, and kills
it again — though by then the gate's own tests did too: a catalog dropped per file is never read, so
`everyDeclaredInputIsRead` finds the declaration stale.

### The gate's source scans

Eleven more, from the two reviews of the gate. A missing declaration costs the gate a second pass,
never a finding, so the runtime tests catch it only on a shape some corpus reaches. The structural
scans in `PurityOracleEntryTests` are there for the rest: they read the source. Each mutant below is
code that one of those scans missed: the first six survive the scans as they were at 0c701ba7, the
last five the scans as they were at 9112617a. Each also has a probe in `PurityScanProbeTests`, which
hands the scan the same shape as a string, so a scan that loses its reach fails there even with no
mutant applied.

| id | shape | expected | killer |
|---|---|---|---|
| `purity-gate-catalog-kept-in-a-static` | engine-wiring | killed | `noStaticHoldsAnOracle` |
| `purity-gate-catalog-kept-in-a-static-as-self` | engine-wiring | killed | `noStaticHoldsAnOracle` |
| `purity-gate-entry-point-added-to-a-listed-file` | engine-wiring | killed | `oracleEntryPointsAreKnown` |
| `purity-gate-read-in-an-undeclared-visitors-extension` | engine-wiring | killed | `purityReadersDeclareWhatTheyRead` |
| `purity-gate-rule-helper-reads-for-another-visitor` | engine-wiring | killed | `purityReadersDeclareWhatTheyRead` |
| `purity-gate-subscript-bypasses-read` | engine-wiring | killed | `withholdableStateIsReadOnlyThroughRead` |
| `purity-gate-oracle-created-by-dot-init` | engine-wiring | killed | `oracleEntryPointsAreKnown` |
| `purity-gate-unlabelled-helper-reads-for-another-visitor` | engine-wiring | killed | `purityReadersDeclareWhatTheyRead` |
| `purity-gate-read-overload-bypasses-read` | engine-wiring | killed | `withholdableStateIsReadOnlyThroughRead` |
| `purity-gate-empty-constant-built-by-the-join` | engine-wiring | killed | `noStaticHoldsAnOracle` |
| `purity-gate-detector-kept-in-a-static` | engine-wiring | killed | `noStaticHoldsAnOracle` |

The first two keep a catalog in a static. The scan used to match only the oracle, the table, the
tripwire and `Withholdable` by name. `CleanInstanceMethodCatalog` and `ImpurePackageFunctions` each
wrap a `Withholdable` without naming it, so the first passed. The second names its type only as
`Self`. Its read after the pass's `seal()` is the one way to a wrong finding the gate has: a release
build answers the placeholder and nothing reruns.

The next three are reads the reader scan did not count. The entry points were listed by file, so a
new public function in a file already listed was no new site. The scan now finds them declaration by
declaration, through helpers, to a fixpoint. A file was checked against the classes it declares, so
an extension of an undeclared visitor in a declared visitor's file was checked against the wrong
declaration. (The same fix stops a harmless `Visitor+Part.swift` split from failing with wrong
advice. That is a false alarm rather than a missed read, so it has a probe and no mutant.) And a
static helper in a rule package that creates an oracle made only its own file a reader, not the
files that call it.

`purity-gate-subscript-bypasses-read` is the declaration kind the state scan did not visit: it
listed functions, initializers and computed properties, and a subscript reached the private state
without tripping. The scan now names whatever declaration each `state` token sits in.

The last five are what the second review found the scans still read past. `oracle-created-by-dot-init`
creates the oracle as `let oracle: PurityInferrer = .init()`, which a scan for `PurityInferrer (`
does not see; a declaration that names `PurityInferrer` beside a `.init` now creates one.
`unlabelled-helper-reads-for-another-visitor` is the gap the reader scan used to document: a helper
class that stores an oracle, built with `ClosureOracle()` in an undeclared visitor's file. Unlabelled
initializers were left out because, by identifier tokens alone, that call reads like a registrar's
`ClosureOracle.self`; they are now matched with their punctuation. `read-overload-bypasses-read` is
the subscript mutant's sibling: an overload named `read` passed a scan that named functions by base
name, and functions are now named by their full signature. The last two are the static scan: a
sanctioned name whose constant is built from a run (a sanctioned constant must now be built from
literals and the empty constants alone), and a held set without the detector — and without the
visitors, which it now holds too, found from the source.

The static scan still matches names. A static whose type is inferred from a call, or a type that
stores a held value and is not listed, passes it; that is its documented limit, and no mutant is
listed for it.

### The CLI's rerun warning

Two more, one per half of the CLI's notice.

| id | shape | expected | killer |
|---|---|---|---|
| `purity-gate-cli-drops-rerun-warning` | engine-wiring | killed | `cliReportsAPurityRerunAsAWarning` |
| `purity-gate-cli-run-bypasses-make-linter` | engine-wiring | killed | `cliBuildsItsLinterOnlyThroughMakeLinter` |

`purity-gate-rerun-not-reported` drops the call in `lint`; these keep the call and lose the
listener. The CLI's notice is the only sign a release build gives of a mispredicted declaration.

The first builds `makeLinter`'s linter with `ProjectLinter()`. Its killer runs that linter over a
visitor that creates an oracle undeclared and expects one `warning:` line, so it holds `makeLinter`,
not `run()`. The second leaves `makeLinter` alone and has `run()` build its own `ProjectLinter()`,
which every runtime test passes: the configured rules never trip, and a debug `analyzeProject`
asserts on a run that does, so `run()` cannot be exercised for it. Its killer reads `Sources/CLI`
instead: only `makeLinter` may name `ProjectLinter`, and the one `analyzeProject` call must be made
in `run()` on a constant bound to `makeLinter` with standard error. Neither is a purity scan, and
neither has a probe in `PurityScanProbeTests`: the CLI's check lives in the CLI's test target.

### The `ConcreteTypeUsage` seam exemptions

Two more, from the pass that took that rule 41 → 22. Both are **recall** mutants: they widen or
narrow an exemption so the rule reports *more*, which is the direction nobody checks. A gate that
stops exempting looks exactly like a corpus that grew.

| id | shape | expected | killer |
|---|---|---|---|
| `platform-prefix-set-widened` | detector-recall | killed | `twoLetterPrefixCollisionIsPinned` |
| `computed-property-counts-as-storage` | detector-recall | killed | `closureWrapperIsNotReported` |

The first is the generalisation that looks obviously right and is refuted by this corpus: every
Apple two-letter prefix, which silences `CLIToolCommandRunner` because it begins `CL` followed by an
uppercase letter. The second is subtler — counting a computed property as storage makes
`var now: Date { make() }` disqualify the very type the exemption was written for, so the catalog
comes back empty and every finding returns. A first, cruder version of the detector did exactly
that.

### The pure-kernel discriminator

One mutant, and it reproduces a mistake that actually shipped into a corpus run before the
measurement caught it.

| id | shape | expected | killer |
|---|---|---|---|
| `kernel-storage-test-inverted-to-denylist` | detector-recall | killed | `storedCollaboratorDisqualifiesEvenWhenUnnamedInBodies` |

`isPureKernel(_:)` asks whether every stored property is a **value** — a positive test. The mutant
turns it back into the denylist the first implementation used: only spellings the walker cannot
read disqualify. That exempts a type storing `UserDefaults` and one storing a SwiftData
`ModelContainer`, which is exactly what the first corpus run produced — two false exemptions out of
six.

Worth having because the failure is invisible from the rule's output *and* from the purity oracle.
`UserDefaults` is one of the oracle's own side-effect markers, and the method that uses it reads
`defaults.data(forKey:)` — the property's name, never its type. A dependency held as storage does
not name itself where it is used.

It was re-expressed when the kernel set became a fixpoint, because a kernel may hold another
kernel: the denylist now replaces `isValue(givenEnums:kernels:)` inside the loop. A denylist makes
the `kernels` argument moot, since every type the walker can read passes whether it is a kernel or
not. Like the original, it also refuses a collection of values, because `[String]` has no nominal
name. So `syntacticValuesQualify` fails beside the killer, which is unaffected.

### The self-access analyzer's key-path components

Two mutants, one on each side of the line the fix draws.

| id | shape | expected | killer |
|---|---|---|---|
| `key-path-component-read-as-self` | detector-recall | killed | `aKeyPathPropertyComponentNoLongerRefutes` |
| `key-path-skip-reaches-subscript-arguments` | detector-precision | killed | `aSubscriptComponentsArgumentIsStillARead` |

The first puts the bug back: `ReferenceCollector` collects the names of key-path components, so
`rules.filter(\.value.enabled)` reads as `self.value` and the method is refused, along with every
caller the clean-method catalog would have cleared. That is how SwiftLintRuleStudio's public
`analyze` went unseeded two calls away from the key path.

The second is the over-correction the fix has to avoid. Skipping *everything* under a
`KeyPathExprSyntax` also skips the argument of a subscript component, so `rows.map(\.[index])`
stops reading `index`, and a method reading mutable state through one is admitted as a function of
its inputs.

Both were re-expressed when the check moved into the shared `isKeyPathComponentName` predicate
(`DeclReferenceExprSyntax+NamePosition.swift`). The first now deletes the call in
`ReferenceCollector`. The second now widens the shared predicate, so it reaches every rule that
asks it; its killer is unchanged.

### Key-path components and other values' members

Eleven mutants from the sweep that found eight rules making the self-access analyzer's mistake:
reading a key-path component (`\.name`) or the member half of `job.name` as a use of the
parameter, local or stored property called `name`. Each of the first ten puts one rule's bug back.

| id | shape | expected | killer |
|---|---|---|---|
| `boolean-coupling-key-path-read-as-the-flag` | detector-precision | killed | `ignoresKeyPathComponentSharingParameterName` |
| `actor-reentrancy-key-path-read-as-the-gate` | detector-precision | killed | `keyPathComponentInConditionIsNotTheGate` |
| `actor-reentrancy-key-path-operand-hides-the-gate` | detector-recall | killed | `keyPathComponentInAwaitOperandDoesNotHideTheGate` |
| `computed-view-key-path-counted-as-dependency` | detector-recall | killed | `keyPathComponentIsNotADependency` |
| `composition-root-key-path-counted-as-use` | detector-recall | killed | `keyPathComponentSharingTheBindingsNameIsNotAUse` |
| `shadowing-key-path-counted-as-rebinding` | detector-recall | killed | `keyPathComponentDoesNotExemptTheShadow` |
| `catch-key-path-counted-as-caught-error` | detector-recall | killed | `flagsNameThatIsNotTheCaughtError` |
| `urlsession-key-path-counted-as-error-parameter` | detector-recall | killed | `detectsNameThatIsNotTheErrorParameter` |
| `impure-marker-matched-on-any-member` | detector-precision | killed | `ignoresKeyPathComponentNamedLikeAMarker` |
| `shorthand-parameter-read-as-projected-value` | detector-recall | killed | `testShorthandClosureParametersAreNotCombine` |
| `member-of-self-read-as-other-base` | detector-precision | killed | `thePropertyItselfInAnAwaitOperandStillSuppresses` |
| `actor-reentrancy-member-operand-hides-the-gate` | detector-recall | killed | `anotherValuesMemberInAwaitOperandDoesNotHideTheGate` |
| `parenthesized-self-read-as-other-base` | detector-recall | killed | `aParenthesizedSelfIsStillTheGate` |
| `catch-pattern-bindings-ignored` | detector-precision | killed | `usingABoundNameIsHandling` |
| `catch-implicit-member-counted-as-caught-error` | detector-recall | killed | `flagsNameThatIsNotTheCaughtError` |
| `shadowing-capture-list-not-a-use` | detector-precision | killed | `genuineRebindingIsExempt` |

Most of them are recall mutants, and that is the shape the bug mostly took: a name that only
matched was read as the thing being looked for. A catch then looks handled, a shadow looks like
a rebinding, and a property seems to read every input. The rule reports less, and nothing in its
output says so.

`shorthand-parameter-read-as-projected-value` is the one unrelated to key paths. Found in the
same sweep, it is the same kind of mistake: a `$` prefix taken for a projected value, when `$0`
is a closure parameter.

The last is the over-correction, on the member side. A stored property is reached bare or
through `self`, so `isMemberNameOfOtherBase` must not count `self` as another base. The mutant
makes it count. `self.connection` in an `await` then stops being the actor's property, and a
resource guard is reported as a reentrancy risk.
