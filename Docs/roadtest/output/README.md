# Road-test output — the raw artifacts

The actual output of both tools on this repository, so the claims in
[`../README.md`](../README.md) can be checked against something other than a
summary.

Generated 2026-07-25, against SwiftProjectLint at the commit that added the
road-test suites, with `swift-infer` @ `39ca16e`.

## What is here, and what is not

**Committed** — small enough to read in a browser or a diff:

| File | Size | What it is |
|---|---|---|
| `discover-Core.txt` | 1 KB | `swift-infer discover` on `Sources/Core` |
| `discover-SwiftProjectLintRegistry.txt` | 6 KB | …on the Registry package |
| `discover-SwiftProjectLintModels.txt` | 11 KB | …on Models — includes both `caseiterable-*` proposals |
| `discover-SwiftProjectLintIdempotencyRules.txt` | 13 KB | …on IdempotencyRules |
| `discover-SwiftProjectLintEngine.txt` | 14 KB | …on Engine |
| `discover-SwiftProjectLintConfig.txt` | 26 KB | …on Config — includes `override-precedence` on `resolveRules` |

**Not committed** — generated on demand, listed here so their absence is visible
rather than silent:

| File | Size | Regenerate with |
|---|---|---|
| `discover-SwiftProjectLintVisitors.txt` | 96 KB | see below |
| `discover-SwiftProjectLintRules.txt` | 128 KB | see below |
| `seed-manifest.json` | 186 KB | the linter, `--format pbt-seeds` |
| `lint-report.txt` | 346 KB | the linter, `--format text` |
| `lint-report.json` | ~525 KB | the linter, `--format json` |

A `.gitignore` entry covers those five. They are deliberately reproducible rather
than archived: pinning a 346 KB text report in git buys little, and it goes stale
the moment a rule changes.

## Regenerating

Both tools, from the repository root:

```sh
# The linter — findings, and the seed manifest the pipeline consumes.
swift build --product CLI
.build/debug/CLI . --include-nested-packages --format text  > Docs/roadtest/output/lint-report.txt
.build/debug/CLI . --include-nested-packages --format json  > Docs/roadtest/output/lint-report.json
.build/debug/CLI . --include-nested-packages --format pbt-seeds > Docs/roadtest/output/seed-manifest.json

# The inference engine — one file per scanned target.
INFER=../SwiftInferProperties/.build/debug/swift-infer
$INFER discover --sources Sources/Core --include-possible > Docs/roadtest/output/discover-Core.txt
for pkg in Models Config Registry Engine Visitors IdempotencyRules Rules; do
  $INFER discover --sources "Packages/SwiftProjectLint$pkg/Sources/SwiftProjectLint$pkg" \
    --include-possible > "Docs/roadtest/output/discover-SwiftProjectLint$pkg.txt"
done
```

`--include-possible` is deliberate: the default run hides `Possible`-tier
suggestions unless they are role-entailed, and the write-up scores both tiers
separately. Drop the flag to see what an adopter sees out of the box.

## What to look at

**For the shape of a suggestion**, `discover-SwiftProjectLintConfig.txt` is the
best single file: it carries the `override-precedence` proposal on `resolveRules`,
a `filter-subset`, two `idempotence`, and the `predicate` caveat block in full —
including the "Generators the law needs" section that hands over a collision-biased
generator rather than describing one.

**For the proxy-construction recipes** (fix 4), any SwiftSyntax-carrier proposal
in the Visitors output shows the `Generator: not synthesisable — a construction
recipe is given below` line and the pasteable recipe under it.

**For the signal-to-noise finding**, `lint-report.txt`. The run is 804 findings,
of which 588 are the two PBT-candidate rules and **three** are Lossy Struct
Rebuild — one of which named the `symbol`-dropping bug that silently emptied the
seed manifest. It was printed, correctly, and went unread. That ratio is the
argument for fix 9 (the manifest reporting its own losses at the point of loss)
and for toolchain finding 9 (seed-path damage deserves to be separable from
ordinary output).

## Reading these honestly

These are the *second* run, after the toolchain fixes this road test produced.
They are not the scored measurement — that was taken against a frozen answer key
before any tool ran, and is reported in the parent write-up. Anything here
benefits from tools that were tuned while looking at this subject, which is the
contamination Appendix C's "fork a fresh fixture" rule exists to prevent.
