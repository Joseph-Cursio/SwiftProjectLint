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
