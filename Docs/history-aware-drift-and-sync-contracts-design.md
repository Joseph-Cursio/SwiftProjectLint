# Design Note: History-Aware Drift Provenance & Sync Contracts

**Status:** Idea / design sketch — **not implemented** as a rule. The Part 1
provenance technique has since been **run by hand and validated** on two real
decisions (see *§Field result (2026-07-24)*); Parts 2–3 remain unbuilt. A forward
direction for the already-shipped duplication rules.
**Category:** Architecture (cross-file — and, newly, cross-*time*)
**Severity:** Info *(opt-in)*, same posture as the detection-only predecessors.
**Builds on:** [`rules/parallel-enum-shape.md`](rules/parallel-enum-shape.md),
[`rules/parallel-list-drift.md`](rules/parallel-list-drift.md),
[`rules/manual-registration-list.md`](rules/manual-registration-list.md),
[`scattered-enum-mapping-rule-design.md`](design/scattered-enum-mapping-rule-design.md).

---

## Origin

`Parallel Enum Shape` and `Parallel List Drift` detect that two declarations
*enumerate the same members* — two enums with the same cases, an enum and a
hand-kept array of the same names, two import lists, etc. In a dogfooding pass
across ~32 of the author's Swift projects, the rules did their job: they surfaced
the pairs. But **every single candidate had to be read by hand before it could be
acted on**, because the correct fix is not a function of the shape. The same
"these two lists match" signal resolved into five *different* right answers:

| Observed shape | Correct response | Why |
|---|---|---|
| Two identical enums, same meaning, no seam between them | **Unify** (typealias / one type) | Pure duplication; collapse it |
| Two identical enums across a deliberate layer boundary, joined by a converter | **Bridge + annotate** | Genuine parallel; keep two types, guard the seam |
| Two enums that merely share case *names* (one is test-fixture input) | **Suppress** | Coincidence, not duplication |
| An enum and a hand-maintained display/registry array of the same members | **Derive** the array from the enum | One should be computed from the other |
| Two lists that agreed yesterday and disagree today | **Fix the drift** | A real bug — one side was updated, the other forgotten |

The tell is in that last row. The static snapshot sees the *current* state of two
lists; it is structurally blind to **how they got there** — and that history is
exactly what separates "coincidence" from "copy-paste" and "intentional
divergence" from "someone forgot the other copy." Two facts the AST cannot
recover but `git` records precisely:

1. **Were these born together or did they converge independently?**
2. **If they've since diverged, was the divergence a bugfix, a feature, or an oversight?**

This note sketches how to fold those two facts in — first as *triage assistance*
(read history, classify better), then as *drift prevention* (record the classified
links, enforce them at edit time).

### The validating case

SwiftUMLStudio carried the render-kind list three times (layout-graph,
dependency-graph, and diagram-script passes). Two copies included `.macro`; the
dependency-graph copy did **not** — so macros were silently dropped from
dependency diagrams while appearing in every other diagram. `Parallel List Drift`
found the three-way near-match. But *which* copy was wrong, and *when* it went
wrong, is a history question: a `git log -S '.macro'` would point straight at the
commit that added `.macro` to two lists and not the third, name the author, and
its message would say whether that was a deliberate scope choice or a miss. The
snapshot can only say "these three differ." (Fixed by deriving all three from one
`ElementKind.processable` constant — see *§ Where the compiler already wins*.)

---

## The gap: a snapshot has no time axis

Static cross-file detection answers *"do these enumerate the same members right
now?"* It cannot answer:

- **Provenance** — same commit (paste) vs different commits (convergence)?
- **Divergence point** — if they differ, at which commit did they part, and was
  the sibling list touched in that same commit or left behind?
- **Intent** — does the commit message that introduced the divergence read like a
  bugfix, a feature, or an accident?

All three are cheap to recover from history and expensive-to-impossible to infer
from source. That asymmetry is the whole opportunity.

---

## Part 1 — Provenance as triage assistance (read history, classify better)

Attach a **provenance class** to every duplicate pair the existing rules surface,
computed from history:

### 1a. Born together (same introducing commit)
Both members first appear in the same commit → strong copy-paste signal → the pair
most likely *should* stay in sync. Raises the prior toward **unify** or **sync
contract**. (In today's SwiftInferProperties pass, the v2
`InteractionPostAcceptanceOutcomeKind` almost certainly began as a paste of v1's
`PostAcceptanceOutcomeKind` — history would confirm it, and that's the pair we
unified to a `typealias`.)

### 1b. Born apart (different introducing commits, converged later)
The two were authored independently and only *became* look-alikes over time →
coincidence → raises the prior toward **suppress**. (The fixture `Confidence` in
`Tests/Fixtures/` vs the production `Suggestion.Confidence`: different origins,
different raw-value base types, same three case names by chance.)

### 1c. Born together, then diverged (the money case)
Both from one commit, but one side later gained/lost a member the other didn't.
`git log -S<member>` (the "pickaxe") finds the *exact* commit where the member
entered one list, and a `blame` of the sibling shows it was untouched there. Now
the commit **message** is the classifier:

- reads like a **bugfix / feature that added a case** → the sibling probably needed
  the same case → **drift bug** (the `.macro` shape).
- reads like a **deliberate format/version split** → intentional → **suppress with
  rationale** (SwiftInferProperties `Decision` vs `InteractionDecision`: the v2 enum
  was *born* pinning a different `"accepted-as-conformance"` raw value because the
  two JSON schemas must diverge on the wire — history would show the divergence
  present since birth, i.e. intentional, not a later slip).

### Git mechanics (and where they bite)
- **Introduction commit:** first commit touching each declaration's line range —
  `git log --diff-filter=A` on the file won't do (files get split); need a
  `log -S<declaration>` pickaxe or `log -L` on the range.
- **Per-member divergence:** `git log -S'<member token>' -- <paths>` locates the
  commit that added/removed a specific case or entry.
- **Blame with move/copy detection:** `git blame -M -C -C --follow` to survive the
  renames and file splits this codebase does constantly — e.g.
  `VerifyCommand+SurveyTypes.swift` exists *only* because another file hit the
  400-line cap and was split. Naïve blame would misattribute every line in it.

Provenance is a **prior, not a verdict.** It should re-rank and pre-annotate
findings ("born together, diverged in `abc123` — *fix?*" vs "born apart —
*suppress?*"), not auto-apply changes.

### Field result (2026-07-24): the *empty* pickaxe is the cheapest high-signal probe

The first real use of this technique — mid-way through the SwiftInferProperties
carrier-list consolidation — produced a result worth promoting into the method.
Two consolidations each surfaced a **member missing from one list but present in
its sibling**, and in both cases the fix hinged on a single question: *was this
removed deliberately, or never added?*

| Asymmetry | Probe | Result |
|---|---|---|
| `UInt32` absent from the partition index list, while `Int32` is present | `git log -S'"UInt32"' -- PartitionPairing.swift` | **empty** |
| `Swift.Float80` absent, while bare `Float80` is present | `git log -S'Swift.Float80' -- ReducerDiscoverer+ShapeHelpers.swift` | **empty** |

**An empty pickaxe is not a null result — it is the answer.** It proves the token
never existed in any revision of that path, which *rules out the one hypothesis
that makes widening dangerous*: that someone had it, hit a problem, and removed it
on purpose. What remains is an authoring-time omission, and adding the member
becomes a safe call rather than a guess. Both were adopted on that basis (`UInt32`
was added; `Swift.Float80` was deliberately left alone for an unrelated reason —
`Float80` does not exist on arm64, so the entry is vestigial on the target
platform).

Three practical consequences for the design:

1. **Run the empty-check first.** It is a single `log -S` per suspicious member,
   needs no blame, no rename detection, and no commit-message interpretation — the
   parts of §Git mechanics that are expensive and failure-prone. It should be the
   *first* probe, not a follow-up.
2. **Report it explicitly in the finding.** "Member `X` never appeared in this
   path's history" is directly actionable text for the person reading the lint
   output; "these two lists differ" is not.
3. **A near-match finding should name the missing member, not just the delta
   count.** The probe is only cheap because the rule already knows *which* token to
   pickaxe — which the `Parallel List Drift` message format already surfaces
   ("agrees on 8 entries but is missing 1: `UnsignedInteger`").

### The propagation case, from this repo's own history

The same session's provenance run turned up a textbook instance of §1c, and its
commit message is the punchline. The partition index list was created in
`460bc9c` (*"Add the partition template…"*). A **second copy** of it appeared the
next day in `7b4af37`, whose subject reads:

> Ship the generator the law needs — **and stop the copy sites eating it**

That commit's entire thesis is that three readers had hand-copied a generator
because the template made them re-derive it — and in fixing exactly that failure
mode, it hand-copied the index list into a second site one layer down. Neither
copy was wrong in isolation; the duplication is only visible across the two
commits.

This is the strongest argument for Part 2 in the whole note: the author was *at
that moment actively thinking about copy-paste harm* and still introduced a copy,
because nothing in the toolchain connected the new site to the old one. Reviewer
attention is not the missing ingredient — a mechanical link is. It also shows the
commit message earning its keep as a classifier: it identifies which copy is
canonical (the one the commit set out to serve) and confirms the propagation was
incidental rather than a deliberate fork.

---

## Part 2 — Sync contracts (record the classification, prevent future drift)

Detection is post-hoc; the highest-value moment is **when someone adds the case**,
with the author present and the context fresh. That requires knowing, at edit time,
that two declarations are a *linked pair* — and that knowledge is precisely the
by-product of the Part 1 classification. So the pipeline closes on itself:

```
detect candidate  →  classify (history-assisted)  →  record the keep-in-sync ones
      ↑                                                        │
      └──────────────  enforce at edit/commit time  ←──────────┘
```

### The annotation becomes load-bearing
Today's output of classification is a *mute* suppression comment:

```swift
// swiftprojectlint:disable:next parallel-enum-shape
```

"Ignore this." Upgrade it to a *positive* assertion:

```swift
// swiftprojectlint:linked-to VerifyEvidenceOutcome — same members, enforce
public enum SurveyOutcome: String, Codable, Sendable { … }
```

Now it means "these two must enumerate the same members." A **diff-aware check**
(pre-commit hook or CI) then enforces it: if a commit adds a case to one member of
a linked group and the other member isn't changed in the same diff, the check
fires — *at the moment the drift is introduced,* not months later in an audit. This
is the direct generalization of `Manual Registration List` (which already checks a
hand-list against a registry) to arbitrary declared links.

### Why a positive link beats a suppression
A suppression says "I looked once." A link says "this relationship must hold going
forward" — it survives the next person, who never saw the original review. It turns
tribal knowledge ("oh, those two always change together") into an enforced,
greppable contract.

---

## Part 3 — Where the compiler already wins (and contracts aren't needed)

A large fraction of duplication should be made *impossible*, not *watched*. Several
of today's fixes did exactly that, and none of them need history, hooks, or a
registry:

| Technique | Effect | Today's example |
|---|---|---|
| **Collapse to one type** (`typealias`) | Two names, one source of truth | `InteractionPostAcceptanceOutcomeKind = PostAcceptanceOutcomeKind` |
| **Derive one from the other** | The array is *computed* from the enum | `Tier.reportDisplayOrder` / `familyDisplayOrder` from `allCases` |
| **Exhaustive `switch` as the guard** | Compiler refuses to build until a new case is handled | the `reportDisplayRank` / `metricsDisplayRank` switches behind those derivations |
| **Total-switch bridge** | Adding a case breaks the converter until updated | `ToolArgument.parameterType` (SwiftAssist) |

Where you can collapse or derive, **the compiler does "check right then" for free** —
the exhaustive `switch` *is* the sync contract, enforced at build time with zero
tooling. So the history + linked-group machinery is emphatically **not** for these.
It is for the *irreducible* parallels — the ones that must remain two distinct
types and that the compiler therefore cannot see across:

- **Wire-format splits** — `Decision` / `InteractionDecision`: same verdicts,
  deliberately different raw values, two JSON schemas.
- **Module boundaries** — `SurveyOutcome` (CLI public output) / `VerifyEvidenceOutcome`
  (Core persistence): identical members, kept separate so Core carries no CLI
  dependency, bridged by a raw-value round-trip pinned by a *test* rather than the
  compiler.

Those two are exactly where a `linked-to` contract earns its keep: no single type
can unify them, no `switch` spans them, so the *only* mechanical guard available is
a diff-aware check over a declared link.

**Rule of thumb:** try to collapse or derive first (compile-time, free, permanent);
reach for a sync contract *only* when a hard boundary forbids collapse.

---

## Caveats & failure modes

- **History is a heuristic, not proof.** Squash-merge and rebase workflows flatten
  provenance — "same commit" can be a squash artifact, not a paste; "different
  commits" can be a rebased split. Signal quality tracks the repo's commit hygiene.
- **Renames and file splits fool naïve blame.** Copy/move detection
  (`-M -C --follow`) is mandatory here, and still imperfect. Treat low-confidence
  provenance as "unknown," not as evidence of independence.
- **Dangling contracts rot.** A `linked-to` whose target is deleted or renamed must
  make the check **fail loudly**, or the contract silently becomes a no-op and the
  annotation lies. Link integrity needs its own check.
- **Cost / latency.** Shelling out to `git log -S` / `blame` per candidate pair is
  fine for a one-shot audit or CI, but too slow for the live per-keystroke path.
  Keep provenance out of the hot editor loop.
- **Over-linking.** Not every look-alike deserves a contract; most deserve a
  collapse. A registry full of contracts that *should* have been typealiases is just
  deferred debt with ceremony. The classifier must bias toward Part 3.

---

## Suggested sequencing

1. **One-shot history audit.** For every pair the existing rules already find,
   compute provenance (§Part 1) and emit a triage report: born-together /
   born-apart / diverged-in-`<sha>`-(*bugfix?*). Cheap-ish, high-insight, run once.
   This *seeds* the classification.
2. **Act on the audit** with the Part 3 preference: collapse/derive wherever a hard
   boundary doesn't forbid it; record a `linked-to` contract only for the
   irreducible remainder.
3. **Enforce forward** with the cheap diff-aware check over declared links (§Part 2)
   plus the compile-time guards from step 2. Do **not** run provenance on every
   lint pass — its value decays to near-zero once the known pairs are classified.

The net: history is how you *understand and seed*; the compiler and a small set of
declared contracts are how you *enforce*. Provenance is a spotlight for the initial
sweep, not a permanent tax on every run.

---

## Worked examples (from the 2026-07 dogfooding pass)

How each mechanism would classify / handle the pairs found this session:

| Pair | Provenance (expected) | Mechanism | Outcome |
|---|---|---|---|
| `Suggestion.Confidence` ↔ fixture `Confidence` | Born apart (fixture is parsed input) | — | **Suppress** (coincidence) |
| `Decision` ↔ `InteractionDecision` | Diverged **at birth** (raw values pinned differently) | `linked-to`? *No* — schemas must diverge | **Suppress w/ rationale** |
| `PostAcceptanceOutcomeKind` ↔ `Interaction…Kind` | Born together (v2 paste of v1) | Collapse | **Unify → typealias** |
| `VerifyEvidenceOutcome` ↔ `SurveyOutcome` | Born together, kept apart by design | **`linked-to` contract** | Suppress today; contract is the intended future guard |
| `InteractionInvariantFamily` ↔ `familyDisplayOrder` | Array hand-kept beside enum | Derive + exhaustive `switch` | **Compile-time guard** |
| `Tier` ↔ `tierOrder` | Label strings hand-kept in CLI | Derive from `Tier` + exhaustive `switch` | **Compile-time guard** |
| SwiftUMLStudio 3× render-kind list (`.macro` missing) | Born together, one diverged in a later commit | Derive all from one constant | **Was a real drift bug** |

The pattern the table makes visible: **provenance sorts the pile, the compiler
handles most of it, and only the two hard-boundary pairs are left for a declared
contract** — which is the whole thesis in one row-count.
