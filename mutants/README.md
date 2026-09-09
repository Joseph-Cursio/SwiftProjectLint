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
