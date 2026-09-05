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

All three target the `ExtractableTotalKernelVisitor` — the §15.2.5 "a total kernel is
trapped in this impure method; lift it" rule — one on each side of the
precision/recall line:

| id | shape | expected | killer |
|---|---|---|---|
| `kernel-governs-always-false` | detector-recall | killed | `chunkingKernelIsCandidate` |
| `kernel-scans-pure-functions` | detector-precision | killed | `pureFunctionIsNotReported` |
| `kernel-worth-extracting-always-true` | detector-precision | killed | `arithmeticWithoutAGoverningUseIsNotReported` |

Forcing `governs` false makes the rule miss a real kernel (recall); inverting the
purity guard makes it scan pure functions that are already candidates elsewhere;
making `isWorthExtracting` always true makes it flag merely-stored arithmetic (both
precision). All three verified killed.

(An earlier pair of threshold/conjunction off-by-one mutants *survived* — the test
kernels sit clear of those boundaries, so no test pinned them; they were replaced
with the decisive mutations above rather than shipped as false guards.)

## Adding a mutant

1. Make the buggy edit; 2. `git diff -- <file> > mutants/patches/<id>.patch`;
3. `git checkout -- <file>`; 4. add an entry to `manifest.json`.
