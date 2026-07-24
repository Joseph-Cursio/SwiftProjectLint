# Rule Design: Duplicate Enum Mapping

**Status:** **Implemented** — [`rules/duplicate-enum-mapping.md`](rules/duplicate-enum-mapping.md).
Fills a verified coverage hole between two shipped rules. Validated against the motivating case:
run over SwiftInferProperties at the commit still containing `humanReadableTier`, the rule
reports exactly one finding — that duplicate, pointed at `Tier.label` — where `Scattered Enum
Mapping` reported zero, and no false positives elsewhere in that codebase.
**Category:** Architecture (cross-file)
**Severity:** Info *(opt-in)*, matching its neighbours.
**Proposed identifier:** `Duplicate Enum Mapping`
**Builds on:** [`scattered-enum-mapping-rule-design.md`](scattered-enum-mapping-rule-design.md),
[`rules/scattered-enum-mapping.md`](rules/scattered-enum-mapping.md),
[`rules/parallel-enum-shape.md`](rules/parallel-enum-shape.md),
[`rules/parallel-list-drift.md`](rules/parallel-list-drift.md).

---

## Origin

While consolidating hand-kept tier lists in SwiftInferProperties, the duplication rules
flagged a pair — `SuggestionRenderer.parts` against `InsightsCommand.tiers`. Reading the
surrounding code found the real shape of the problem: **four** sites maintaining the same
tier vocabulary, of which the rules could see two.

| Site | Form | Flagged? |
|---|---|---|
| `InsightsCommand.tiers` | `Set<String>` of labels | ✅ |
| `SuggestionRenderer.parts` | `[Tier]` inclusion list | ✅ |
| `ReportCommand.includeTiers` | 3-entry `Set<String>` of labels | ❌ under the entry-count floor |
| `IndexCommand.humanReadableTier` | **`switch` returning literals** | ❌ not a list |

The last one is the dangerous one. `humanReadableTier` was a byte-identical
reimplementation of `Tier.label` — same six cases, same six string literals — and it is the
function that writes the tier string *into the persisted semantic index*. The two
label-string filters (`insights`, `report`) then match against that stored string. So three
independently-maintained artefacts had to agree on the exact spelling of six words, and
nothing checked it. A one-word divergence would not have failed a build or thrown: the
filters would simply have matched nothing and both surfaces would have silently reported
empty.

That is precisely the failure class this rule family exists to catch, and it was invisible —
**not because of a tuning threshold, but structurally**: the mapping was written as a
`switch`, and both `Parallel Enum Shape` and `Parallel List Drift` only collect enum
declarations and array literals.

### The obvious objection, tested

`Scattered Enum Mapping` already targets duplicated `switch` mappings — so the natural
question is whether it simply wasn't enabled during that scan. It was not, so the check was
run explicitly: a worktree at the commit still containing `humanReadableTier`, linted with
`enabled_only: ["Scattered Enum Mapping"]`.

**Result: 0 findings.** The rule does not catch this, and the reason is in its own spec:

> A group fires when it has **≥ 3 scattered sites across ≥ 2 files**.

`humanReadableTier` + `Tier.label` is **2** sites. The pairwise case falls below the floor.

---

## The coverage hole

Stated as a matrix, the gap is a single empty cell:

| | **2 sites (a pair)** | **3+ sites (scattered)** |
|---|---|---|
| **enum decl / array literal** | `Parallel Enum Shape`, `Parallel List Drift` | (covered by the same, pairwise-repeated) |
| **`switch` returning literals** | ⬅ **nothing** | `Scattered Enum Mapping` |

The catalogue does pairwise detection for *lists* and 3+-site detection for *switches*. The
pairwise-switch cell is unoccupied, and it is not an exotic corner: **a pair is the most
common multiplicity of this bug.** Duplication starts at two. The three-site version is what
a pair becomes after it has been ignored for a while.

It also matters that `switch`-over-enum-returning-literals is not an unusual way to write
these mappings in Swift — it is *the* idiomatic way. A rule family aimed at "the same
vocabulary maintained in two places" that cannot see the idiomatic spelling of that
vocabulary has a hole in the middle of its stated purpose.

---

## Proposed rule

**Fire when two `switch` statements over the same enum produce the same mapping.**

The key move — the thing that makes a 2-site threshold safe where `Scattered Enum Mapping`
needed 3 — is **matching on values, not on shape**.

`Scattered Enum Mapping` groups sites by `(case-label set, return kind)`. That is
deliberately loose: it is looking for *a missing abstraction* across many sites, and it
cannot resolve types, so it must not over-commit. Two switches over `Severity` both
returning some `Color` are the same *shape* — but they might legitimately be different
mappings (a foreground colour and a background colour). At two sites that is a real
false-positive risk, which is exactly why the floor is 3.

That risk disappears when the **returned literals are compared and found identical**. Two
switches over the same enum, with the same case set, returning the same literal for every
case, are not "the same shape" — they are *the same function, written twice*. There is no
benign reading. At that point one site is enough evidence, and two is conclusive.

So:

- **`Scattered Enum Mapping`** — loose match (shape), high threshold (≥3 sites). Finds
  *missing abstractions*.
- **`Duplicate Enum Mapping`** — exact match (values), low threshold (2 sites). Finds
  *copied functions*.

They are complements, not competitors: one trades precision for recall, the other the
reverse.

### Detection sketch

Phase 1 can reuse `ScatteredEnumMappingVisitor`'s existing collection wholesale — it already
walks every `switch`, filters to leading-dot exhaustive-looking arms with single-expression
bodies, and records the case labels and return kinds. Two changes:

1. **Record the arm *values*, not just the kind.** For literal returns, keep the literal
   text keyed by case label: `{verified: "Verified", strong: "Strong", …}`. For
   implicit-member returns, the member name (already recorded).
2. **Group by `(enum case set, full case→value map)`** and fire at **≥ 2 sites**, requiring
   the sites be in different declarations (a switch and its own helper overload in one type
   is not two maintainers).

Arm-count floor can drop below `Scattered Enum Mapping`'s 3, since exact-value matching
carries the precision — though ≥3 arms is a reasonable starting point to avoid two-case
boolean-ish switches.

### What should fire

```swift
// Tier.swift  (Core)
public var label: String {
    switch self {
    case .verified: return "Verified"
    …
    }
}

// IndexCommand+Projection.swift  (CLI)   ← fires: identical case→literal map
static func humanReadableTier(_ tier: Tier) -> String {
    switch tier {
    case .verified: return "Verified"
    …
    }
}
```

### What should not

```swift
// Same enum, same return type, DIFFERENT values — a real second mapping.
var foreground: Color { switch self { case .error: .red;   … } }
var background: Color { switch self { case .error: .pink;  … } }
```

Shape-matching would pair these; value-matching correctly leaves them alone. This is the
concrete precision win that buys the lower threshold.

---

## Why not simply lower `Scattered Enum Mapping`'s threshold to 2

Because its matching is too loose to support it — that threshold is load-bearing for its
precision, and dropping it would fire on every foreground/background pair in the corpus.
The threshold and the match strictness have to move together. Whether this ships as a
separate rule or as a second, stricter *mode* inside the existing visitor is an
implementation choice; the doc argues for a separate identifier so the two can carry
different severities and be enabled independently, and so the message can be specific
("identical mapping — delete one and call the other" vs "scattered mapping — extract to the
enum").

---

## False-positive risks

- **Genuinely independent identical mappings.** Two modules that must not depend on each
  other may each need `Tier → String`, and merging them would create unwanted coupling.
  This is the `SurveyOutcome`/`VerifyEvidenceOutcome` situation from the same codebase — a
  deliberate boundary. Mitigation: the finding is `Info`/opt-in and suppressible, and this
  is exactly the case the `linked-to` sync contract in
  [`history-aware-drift-and-sync-contracts-design.md`](history-aware-drift-and-sync-contracts-design.md)
  is designed to serve — the right outcome there is "keep both, enforce agreement," not
  "merge."
- **Test doubles / fixtures.** A fixture reproducing a production mapping on purpose.
  Mitigation: the existing `excluded_paths` reporting filter, plus the caveat learned in
  that same note — an excluded file still supplies cross-file *evidence*, so a Sources-side
  finding whose only counterpart is a fixture will still report and needs an inline
  suppression.
- **Generated code.** Two generated switches from one template are duplicated by
  construction and not worth reporting.

---

## Secondary finding: entry-count floors hide small vocabularies

The fourth site, `ReportCommand.includeTiers`, is a 3-entry array. `Parallel Enum Shape`
sets `minArrayEntries = 5` and `Parallel List Drift` sets `minEntries = 4`, so a 3-entry
list is below `Parallel Enum Shape` outright.

Those floors are well-motivated — short lists collide by coincidence constantly, and
lowering them globally would flood the output. But it is worth recording that the cost is
real: this list was a **third copy of a vocabulary whose other copies were already flagged**,
and it was silently exempt for being short.

A targeted relaxation is worth considering: when a short list's entries are a **subset of an
already-reported group's** entries, report it as an additional member of that existing
finding rather than as a new pair. That costs no new false positives — the group is already
being surfaced — and it closes the "third copy hides behind the floor" case that produced
this exact miss. (Whether `Parallel List Drift` should already have paired the 3-entry list
against the 4-entry one, given `max(3, 4) ≥ 4` clears its floor, was not established here
and is worth a separate look — the subset-similarity handling is the likely reason it did
not.)

---

## Worked example (the case that motivated this)

| | |
|---|---|
| **Enum** | `Tier` — 6 cases |
| **Site A** | `Tier.label` (SwiftInferCore) |
| **Site B** | `IndexCommand.humanReadableTier` (SwiftInferCLI) |
| **Relationship** | identical case set, identical string literal per case |
| **Consequence if drifted** | site B writes the tier into the persisted index; two label-based filters match against it; a divergence silently empties both surfaces with no error |
| **Caught by** | `Scattered Enum Mapping`? No — 2 sites, floor is 3 (verified empirically) |
| | `Parallel Enum Shape` / `Parallel List Drift`? No — a `switch`, not a list |
| **Found by** | reading the code |
| **Fix applied** | deleted `humanReadableTier`; both callers use `Tier.label` |

The generalisable lesson, and the reason this note exists: **the tool found the pair, but
reading found the cluster.** Two of four sites were invisible — one structurally, one to a
threshold. Both blind spots are addressable, and the structural one is the higher-value fix,
because it is not a matter of degree: no amount of tuning makes a list-shaped detector see a
`switch`.
