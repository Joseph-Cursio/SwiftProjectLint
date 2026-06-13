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
| 11 | Effect cycles (`.start→.send(.refresh)`, `.refresh→.send(.start)`) | SPL | New rule | ✅ **DONE** — `effect-cycle` rule: cycle detection over the synchronous `.send(.X)` graph in a `switch action`; `.run`-closure sends excluded. `.warning`, enabled by default |
| 12 | Redundant derived state (`fullName` stored vs computed) | SPL | New rule | ✅ **DONE** — `redundant-derived-property`: stored property assigned a string interpolation of sibling fields → suggest computed. `.info`, opt-in. v1 is string-only (numeric aggregates left to SInferP's conservation family) |
| 2 | Dead actions (defined/handled, never `send`) | SPL (cross-file) | New rule | Maybe — needs whole-project action def/send graph. FP risk: bindings, parent features, tests, public API |
| 6 | State fields never written | SPL (cross-file) | New rule | Maybe — complements `unused-state-variable` |
| 7 | Actions sent but ignored (`default: .none`) | SPL (cross-file) | New rule | Maybe — send↔case graph |
| 9 | View reads state that never changes | SPL (cross-file) | New rule | Maybe — related to #6 |
| 4 | Ignored effect results | — | Overlap | Skip — covered by `discarded-try-result` / `fire-and-forget-task` / `async-let-unused` / `map-used-for-side-effects` |
| 5 | State fields never read | — | Overlap | Skip — covered by `unused-state-variable` (verify TCA-store coverage) |
| 3 | Unreachable reducer cases | — | Too hard | Skip — needs effect-flow reachability → high FP |
| 8 | Child state exists, no view scopes it | — | Too hard | Skip — needs view/feature graph, complex |

## Recommended next (ranked)

1. **Cross-file batch (#2 / #6 / #7 / #9)** — feasible and on-brand for this
   linter (cross-file is its reason to exist), but each needs a usage graph plus
   FP tuning (bindings, parent features, tests). Treat as one project, not four
   quick rules.

Possible follow-ups to the shipped rules:
- `redundant-derived-property` v2 — extend beyond string interpolation to string
  `+` concatenation, and (carefully) `self`/bare-reference derivations.

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
