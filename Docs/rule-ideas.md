# Rule Ideas — TCA State-Consistency Backlog

Triage of candidate rules sourced from a ChatGPT-generated list of TCA
state-consistency issues (`TCA_State_Consistency_Issues.md`, 12 examples). Each
is scored by **home** (this linter vs the SwiftInferProperties property-inferer),
**novelty** (vs rules SwiftProjectLint already ships), and **feasibility**
(structural AST vs flow/whole-project/semantic — with false-positive risk).

Most of these are *bug detection* (lint), not *property inference*. The doc's own
closer is the key caveat: several "require semantic understanding rather than
simple syntax matching."

## Status

| # | Idea | Home | Verdict | Status |
|---|---|---|---|---|
| 1 | Impossible state combos (`isLoggedIn`+`currentUser?`, `hasError`+`errorMessage?`) | SPL | Extend `flag-optional-pair-state` | ✅ **DONE** — tier-2 name-correlated `has<X>`/`is<X>` flags |
| 10 | Loading inconsistency (`isLoading`+`results: [User]`) | SPL | Extend `flag-optional-pair-state` | ✅ **DONE** — flag now pairs with collections, not only `T?` |
| 11 | Effect cycles (`.start→.send(.refresh)`, `.refresh→.send(.start)`) | SPL | New rule | ⭐ **TODO** — intra-reducer `action→.send(action)` graph, flag short cycles. Not covered by `potential-retain-cycle`. Self-contained, structural |
| 12 | Redundant derived state (`fullName` stored vs computed) | SPL or SInferP | New rule | TODO — "prefer computed property" lint; generalizes SInferP's `conservation` family (`itemCount == items.count`). Lint framing is lower-risk |
| 2 | Dead actions (defined/handled, never `send`) | SPL (cross-file) | New rule | Maybe — needs whole-project action def/send graph. FP risk: bindings, parent features, tests, public API |
| 6 | State fields never written | SPL (cross-file) | New rule | Maybe — complements `unused-state-variable` |
| 7 | Actions sent but ignored (`default: .none`) | SPL (cross-file) | New rule | Maybe — send↔case graph |
| 9 | View reads state that never changes | SPL (cross-file) | New rule | Maybe — related to #6 |
| 4 | Ignored effect results | — | Overlap | Skip — covered by `discarded-try-result` / `fire-and-forget-task` / `async-let-unused` / `map-used-for-side-effects` |
| 5 | State fields never read | — | Overlap | Skip — covered by `unused-state-variable` (verify TCA-store coverage) |
| 3 | Unreachable reducer cases | — | Too hard | Skip — needs effect-flow reachability → high FP |
| 8 | Child state exists, no view scopes it | — | Too hard | Skip — needs view/feature graph, complex |

## Recommended next (ranked)

1. **Effect-send cycles (#11)** — smallest novel win: structural, self-contained
   (single reducer), a real bug class, nothing covers it. Build an
   `action → .send(action)` edge set within each `Reduce` and report short
   cycles. Watch FP from conditional/guarded sends.
2. **Redundant stored derived property (#12)** — "this stored field is only ever
   assigned a derivation of other stored fields → make it computed." Heuristic;
   lower precision than #11.
3. **Cross-file batch (#2 / #6 / #7 / #9)** — feasible and on-brand for this
   linter (cross-file is its reason to exist), but each needs a usage graph plus
   FP tuning (bindings, parent features, tests). Treat as one project, not four
   quick rules.

## Done — `flag-optional-pair-state` extension (#1 + #10)

Both broadenings shipped into the existing `flag-optional-pair-state` rule
(no new RuleIdentifier; same `.info` opt-in State-Management rule):

- **Pair with collections** (`[T]` / `Array` / `IdentifiedArray(Of)`), not only
  `T?` — catches `isLoading` + `results: [User]`.
- **Tier-2 `has<X>`/`is<X>` flags** that *name-correlate* with a pairable
  property (stem after `has`/`is`, camelCase boundary, ≥ 4 chars, appearing in a
  pairable property's name) — catches `hasError` + `errorMessage`, `isSelected` +
  `selectedItem`. Tier 1 (transition verbs `loading`/`fetching`/`refreshing`/
  `active`) still pairs with any pairable property.
- **Known gap (deliberate):** `isLoggedIn` + `currentUser` is *not* flagged — no
  shared name token, and a blanket "`is*` Bool + any optional" rule would be too
  noisy.
