# Design Spike: Could Hoist To Protocol Extension

**Status:** Variant A shipped as the [Hoistable Conformer Member](rules/hoistable-conformer-member.md)
rule. Variant B's broad form was measured and rejected; its narrow `|S| >= 2` subset shipped as
the [Hoistable Sequence Operation](rules/hoistable-sequence-operation.md) rule — see §7.

## 1. Problem statement

The protocol-architecture rules so far critique *existing* abstractions
([Single Implementation Protocol](rules/single-implementation-protocol.md),
[Mirror Protocol](rules/mirror-protocol.md),
[Unused Protocol Abstraction](rules/unused-protocol-abstraction.md)) or *missing structural*
ones ([Duplicate Struct Shape](rules/duplicate-struct-shape.md),
[Shared Domain-Enum Field](rules/shared-domain-enum-field.md)). The remaining gap is
**behavioral**: logic duplicated across types that already share a protocol, which could move
into `extension P` so it is written once.

This is the behavioral inverse of [Could Adopt Protocol](rules/could-adopt-protocol.md):

| Rule | Starts from | Asks |
|---|---|---|
| Could Adopt Protocol | a type matching a protocol's shape | should it *declare* conformance? |
| Duplicate Struct Shape | concrete types | is there a *missing protocol*? |
| Scattered Enum Mapping | `switch` over an enum | should the mapping move *onto the enum*? |
| **This spike** | duplicated logic over conformers of P | should it move *into `extension P`*? |

## 2. Motivating evidence (and an inconvenient truth)

The finding that prompted this (a review of SwiftCompilerFlagStudio's `BuildSettingIdentity`)
had **two distinct shapes**:

**Shape A — duplicated member implementations on the conformers.** `matchesMetadata(_:)` had
already been hoisted into a protocol extension; pre-hoist, each of the five conformers would
have carried an identical copy.

**Shape B — duplicated call-site closures over collections of conformers:**
```swift
flags.sorted { ($0.category, $0.name) < ($1.category, $1.name) }      // ×5 sites
Dictionary(grouping: filtered) { $0.category }; groupedX.keys.sorted() // ×4 sites
```
These should become `extension Sequence where Element: BuildSettingIdentity { … }`.

The inconvenient truth: the *actual* SCFS finding was **Shape B**. Shape A is the tractable
one; Shape B is the higher-value one. Variant A does not catch the call-site duplication that
started this, and the spike does not pretend otherwise.

## 3. The core difficulty

Both shapes reduce to one verification: **does this logic reference only what `P` guarantees?**
— the precondition for the hoist to compile.

- **Shape A** is checkable syntactically: collect the instance members the body touches, and
  require each to be a requirement of `P`. Bias to false-negatives → safe.
- **Shape B** additionally needs the **element type of the receiver collection** to be known to
  conform to `P` — i.e. type inference. `flags.sorted { … }` where `let flags =
  parser.compilerFlags(...)` has no annotation; SwiftSyntax alone cannot resolve it. Without
  that, B degrades to "this closure touches a member-set that happens to match `P`'s
  requirements," which fires on any unrelated `[T]` whose `T` coincidentally has those members.

That asymmetry drove the decision to ship A and defer B.

## 4. Variant A — Hoistable Conformer Member (shipped)

**Detection.** Three or more types conforming to a common protocol `P` each implement a method
or computed property *identically*, the shared body references at least one and only `P`'s
requirements, the member is not itself a requirement of `P`, and no `extension P` already
provides it → suggest hoisting to `extension P`.

**Algorithm.** Two-phase cross-file visitor:

1. *Collect.* Protocol requirement names; members provided by protocol extensions; and per
   concrete type (aggregated across primary declaration and extensions) its conformances, all
   member names, and hoistable-member records — `(signatureKey, normalizedBody,
   referencedIdentifiers, location)`. Bodies are normalized (whitespace stripped, `self.`
   dropped). Stored / `static` / `class` / `lazy` members are excluded.
2. *Group + emit.* Group by `(signature, body)`; for a group of `>= 3` distinct types pick the
   most specific common protocol satisfying the four guards, and emit one issue per type.

**The compile guard** — the precision backbone — intersects the body's identifier tokens with
the union of owner member names to find which *instance members* the body touches, then
requires that set to be non-empty and a subset of `P`'s requirements. Over-collection of
identifiers only ever makes the guard stricter, never looser, so a reported hoist is always
safe to perform.

Implementation: `HoistableConformerMemberVisitor`. Opt-in, `Info`. Mirrors the
`SharedDomainEnumField` machinery.

## 5. False-positive guards (A)

- Skip SwiftUI (`View` / `ViewModifier`).
- Exact normalized-body match only — no fuzzy matching.
- Compile guard (refs ⊆ `P` requirements, non-empty).
- Coverage check — already provided by `extension P` ⇒ silent (this is what makes the rule go
  quiet once a member has been hoisted).
- Not-a-requirement guard — only factor out incidental behavior, never change `P`'s contract.
- Opt-in, `Info`.

## 6. Test plan (A) — implemented

1 positive (3 conformers, identical member, refs ⊆ `P` → 3 issues) + negative guards: body
references a non-`P` field (the key correctness test), two conformers (below threshold), already
provided by `extension P`, no common protocol, differing bodies, plus a computed-property
positive. End-to-end opt-in test in `ProjectLinterTests`. New rule also needs the 6-point
wiring + `Docs/rules/hoistable-conformer-member.md` (the exhaustive doc test enforces it).

## 7. Variant B — Hoistable Sequence Operation (measured; narrow subset shipped)

**Sketch.** Find closure literals passed to a fixed allowlist of `Sequence` higher-order
methods (`sorted`, `filter`, `min/max(by:)`, `first/contains(where:)`, `partition(by:)`,
`Dictionary(grouping:by:)`). Extract the member-set `S` accessed off the closure's first
parameter; for a site whose `S` is a subset of some project protocol `P`'s property
requirements, suggest hoisting to `extension Sequence where Element: P`.

**The measurement.** A throwaway probe (not wired into the registry) ran the detection over two
real codebases and the findings were classified by hand.

*SwiftCompilerFlagStudio* (114 files, 4 protocols) — the repo with the genuine finding:

| Filter | Findings | True positives | Precision |
|---|---|---|---|
| `\|S\| >= 1` | 30 | 10 | **33%** |
| `\|S\| >= 1`, repeated closure (>= 3 sites) | 19 | 9 | 47% |
| **`\|S\| >= 2`** | **5** | **5** | **100%** |

*SwiftProjectLint* (369 files, 11 protocols): **1** finding total, a false positive
(`caseItems.contains { $0.pattern … }`, where `pattern` coincidentally subsets a protocol). B
fires rarely across a codebase, but what it does fire at `|S| = 1` is noise.

**What the data says.**

1. **The element-type-unknown problem (§3) dominates.** Two-thirds of `|S| >= 1` findings are
   false positives: common property names (`name`, `rawKey`) are subsets of a protocol's
   requirements *by coincidence*, so `targets.first { $0.name == … }` matches
   `BuildSettingIdentity` even though `ParsedTarget` is not a conformer.
2. **Recurrence does *not* discriminate** — the decisive negative result. The false-positive
   `{name}` closures recur **5×, 5×, 2×**, exactly as often as the real `{category,name}` sorts.
   "Repeated identical closure" was the spike's leading precision lever; the measurement refutes
   it.
3. **Member-set distinctiveness is the only lever that worked.** `|S| >= 2` gave 5/5 precision —
   the five `sorted { ($0.category, $0.name) < … }` sites, every one over a real conformer
   (`[CompilerFlag]`, `[EffectiveSetting]`, …). But it is still a heuristic: it worked only
   because no non-conformer happened to access `{category, name}` *together*, which is not
   guaranteed in general. And it misses the single-key `Dictionary(grouping:) { $0.category }`
   sites — 5 of which are real (and 1, over `[Recommendation]`, is the predicted soft-FP).

**Verdict.** Do **not** ship B as a broad syntactic rule: 33% precision at `|S| >= 1`, and
recurrence can't rescue it. Two viable paths:

- **Narrow, high-precision subset (shippable):** restrict to `|S| >= 2` — distinctive
  multi-key `Sequence` closures matching a protocol's requirements. 100% precision on this
  sample, catches the multi-key sort duplication (the strongest half of the original finding),
  documented explicitly as a heuristic that may miss single-key cases and can rarely FP. Opt-in,
  `Info`.
- **Complete solution (large lift):** resolve each receiver's element type and check conformance
  to `P`. That needs SourceKit/index integration, which is out of scope for a SwiftSyntax-only
  linter.

The single-key grouping sites (`{category}`) are genuinely real but indistinguishable from the
`[Recommendation]` false positive without type information, so they stay out of any syntactic
version.

## 8. Decisions on record

- **Two distinct rules, not an umbrella.** A and B have different confidence levels; a team may
  want one without the other. A shipped as `Hoistable Conformer Member`. B, if built, gets its
  own identifier.
- **A does not close the original SCFS (Shape B) finding.** Recorded so the gap is not mistaken
  for covered.
- **B's broad form was rejected by measurement; the narrow subset shipped.** Broad B is ~33%
  precision and unshippable. The `|S| >= 2` subset (`Hoistable Sequence Operation`, opt-in,
  `Info`, with a recurrence requirement) shipped: run against SwiftCompilerFlagStudio it
  reported exactly the five `{category, name}` sort sites and nothing else — 5/5. It remains a
  heuristic; the complete solution needs type resolution the linter does not have.
