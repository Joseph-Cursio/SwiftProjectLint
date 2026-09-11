# `--format seams` — seam inventory design

**Status:** proposal. Not implemented.
**Shape:** an output format, **not a rule.** Nothing new is reported; nothing existing changes.
**Sibling:** `--format pbt-seeds`, which answers the same *kind* of question (here is what you can
reach) for pure functions.
**Motivation:** [`Docs/reachable-findings.md`](../reachable-findings.md)

## The gap

Every rule in this suite reports an absence. That is correct, and it leaves one question
unanswered: **where can I reach this type from a test?**

The question came up while writing tests for `SwiftFormatRuleStudio.ImpactModel`. The answer was
`cli` and `reader` — `init` parameters with defaults — and it was found by grepping for `let cli`
and `init(`. `missing-dependency-injection` was silent, correctly: the seam exists, so there is
nothing missing to report.

The suite already knows where that seam is. It has to, in order to decide *not* to report it.

## What a seam is, for this purpose

A named point at which a test can substitute behaviour without changing production code. Four
carriers, all already recognised somewhere in the codebase:

| Carrier | Example | Already read by |
|---|---|---|
| Initialiser parameter with a default | `init(cli: any SwiftFormatCLIProtocol = .makePreferred())` | `direct-instantiation` (as the shape it must *not* report) |
| Debug-only initialiser | `#if DEBUG init(viewModel:) { … }` | `missing-dependency-injection` (as an exemption) |
| Protocol-typed stored property | `private let cli: any SwiftFormatCLIProtocol` | `concrete-type-usage` (as the shape it wants) |
| Defaulted closure parameter | `now: @Sendable () -> Date = { Date() }` | `non-injected-nondeterminism` (as the shape it must not report) |

Every one is already computed. In each case a rule decides *not* to fire because the seam is
present — and then throws that knowledge away.

## Output

Machine-readable, keyed by the type it opens:

```json
{
  "type": "ImpactModel",
  "file": "…/Services/ImpactModel.swift",
  "seams": [
    { "kind": "initializerDefault", "name": "cli",
      "type": "any SwiftFormatCLIProtocol", "line": 52 },
    { "kind": "initializerDefault", "name": "reader",
      "type": "any SourceFileReading", "line": 53 }
  ]
}
```

and a text form for reading:

```
ImpactModel (Services/ImpactModel.swift)
  cli     any SwiftFormatCLIProtocol   init default, line 52
  reader  any SourceFileReading        init default, line 53
```

## Why an output and not a rule

A rule that fires on correct code is noise, and this fires on nothing *but* correct code — a seam
is the thing the rules are asking for. As an output it costs a reader who wants faults exactly
nothing, because they never ask for it.

`--format pbt-seeds` is the precedent: it answers *here are the pure functions* and hands them to
`swift-infer discover --seeds`. It is not a finding, not counted in the ranking, and not noise.
This is the same move for a different question.

## What it is not

- **Not a coverage tool.** It says a seam exists, not whether a test uses it.
- **Not a recommendation.** It makes no claim that a seam *should* be used, or that a type with
  none is wrong — `missing-dependency-injection` already owns that judgement.
- **Not type resolution.** `any SwiftFormatCLIProtocol` is reported as written. Whether the
  protocol is satisfiable by a test double is the reader's call.

## Open questions

1. **Scope.** Every type, or only those a rule has already reasoned about? The second is cheaper
   and self-limiting, but makes the output depend on which rules ran.
2. **Environment values.** `@Environment(TeamDataStore.self)` is a substitution point in SwiftUI
   and does not look like the four carriers above. Include it, and the output grows a
   framework-specific arm; exclude it, and the inventory is incomplete for exactly the views that
   most need testing.
3. **Does it earn its place?** The honest case for it is one session's friction, which is thin.
   Worth revisiting after keeping a note of how often *"where is the seam?"* actually comes up —
   if the answer is "rarely, and grep was fine", this should not be built.

## Prior art in this repo worth copying

`--format pbt-seeds` hands its output to another tool rather than to a human. If a seam inventory
has a consumer — a test-scaffold generator, say — that is a much stronger case than a reading
format, and would settle question 3.
