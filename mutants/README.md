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
