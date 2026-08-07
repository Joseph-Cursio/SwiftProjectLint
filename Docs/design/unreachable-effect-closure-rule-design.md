# `unreachable-effect-closure` — rule design

**Status:** proposal. Not implemented.
**Category:** Testability · **Severity:** `.info` · **Gating:** listed by default (see below — there
is no per-rule opt-in switch, and the sibling's "opt-in" is something else entirely)
**Sibling:** `pure-closure-candidate` (this is its impure twin)

## The gap

`pure-closure-candidate` opens with the right argument:

> *An inline closure cannot be tested — not "is hard to test", cannot. There is no name to call and
> no seam to reach it through.*

That argument is about **reachability**, and reachability has nothing to do with purity. But the
rule then narrows to pure closures, and refutes anything that writes to what it captured:

> *What no extraction rescues is a closure that **writes** to what it captured — that one is
> refuted, by the shared purity oracle.*

For a *property-test* seed that refutal is correct: you cannot generate inputs for a closure whose
job is a side effect. But the unreachability claim still holds — and for effectful closures it
matters more, because a side effect on shared state is exactly the kind of thing that regresses
silently. The refutal is scoped to the wrong conclusion: it should refuse *property-test candidacy*,
not refuse *extraction*.

This rule covers what falls through: a closure that **mutates captured state**, is **registered as a
callback** rather than called inline, and therefore has no seam through which any test can observe
its effect.

### Worked example

Measured in SwiftUMLStudio (`NativeDiagramView`, `NativeSequenceDiagramView`), before:

```swift
.onContinuousHover(coordinateSpace: .named(Self.canvasCoordinateSpace)) { phase in
    switch phase {
    case .active(let location):
        viewport.hoveredNodeId = NativeDiagramGeometry.hitNode(in: graph, at: location)?.id
    case .ended:
        viewport.hoveredNodeId = nil
    }
}
.onKeyPress(.escape) {
    viewport.selectedNodeId = nil
    return .handled
}
```

Both write to captured `viewport`, so `pure-closure-candidate` refutes both. Neither is reachable by
a unit test: `ImageRenderer` drives a real draw pass but never fires gestures or key presses, and
ViewInspector cannot traverse these views at all (their bodies are `GeometryReader`s — see the
`ViewInspectorCompatibility` preflight). Coverage sat at **0%** across both files.

After extraction (landed in SwiftUMLStudio `095de17`, "Cover NativeDiagramView and
NativeSequenceDiagramView"):

```swift
.onContinuousHover(coordinateSpace: .named(Self.canvasCoordinateSpace)) { updateHover($0) }
.onKeyPress(.escape) { clearSelection() }

func updateHover(_ phase: HoverPhase) { … }
func clearSelection() -> KeyPress.Result { … }
```

The behaviours that then became assertable are real contracts, not ceremony:

- tapping empty canvas **clears** the selection rather than leaving a stale one
- the pointer leaving the canvas **clears** the hover highlight
- an arrow key on an empty graph returns `.ignored` rather than being swallowed (so it does not beep)

None of those could be stated as a test before. All three are one careless edit from regressing.

## Trigger

Report a `ClosureExprSyntax` when **all** hold:

1. **Registered, not called.** It is a trailing/argument closure on a call whose base is a member
   access in a `View` body position — the SwiftUI callback surface. Start from an explicit allowlist
   rather than inferring: `onTapGesture`, `onLongPressGesture`, `onKeyPress`, `onContinuousHover`,
   `onHover`, `onChange`, `onSubmit`, `onDrag`, `onDrop`, and the gesture callbacks `onEnded` /
   `onChanged` / `updating`.

   **`onAppear` / `onDisappear` are deliberately absent** — see *Interaction with
   `impure-call-in-view-body`* below. **`Button`'s action closure is deliberately present**, as a
   second surface with a different shape: it is a `DeclReferenceExprSyntax` call, not a member
   access, so the allowlist above cannot reach it and it needs its own arm. It belongs here — the
   unreachability argument applies to a button action verbatim, and it is likely the single most
   common instance of the whole pattern.

   This widens the rule's scope past what the original proposal asked for, and it is a **settled
   decision, not the author's preference** — affirmed 2026-08-07, on the reasoning that a rule
   arguing from reachability cannot exclude the most-used callback surface without contradicting
   itself. Expect the finding count to be materially higher than a modifiers-only v1; open question 4
   is how that count gets measured.
2. **Effectful on captured state.** The body contains an assignment whose left-hand side roots in a
   captured identifier rather than a closure parameter or a local.

   **Do not implement this by inverting `PurityInferrer.isPure(_ closure:)`.** That returns one Bool
   folding four separate refuters — `async`/`throws`, impurity markers, totality, and capture
   mutation (`SwiftEffectInference/PurityInferrer.swift:194-205`). Inverting it over-reports:
   `.onHover { print(x) }` is impure and has no captured write. The predicate this rule actually
   wants is the last of the four alone, and it is now available as
   `PurityInferrer.mutatesCapturedState(_ closure:)` — see *Feasibility*.
3. **Not already extracted.** The body is more than a single call expression.

Condition 3 is what makes the rule converge. `.onKeyPress(.escape) { clearSelection() }` is the
*fixed* form and must not be reported — otherwise the rule fires forever and gets disabled. A body
that is exactly one `FunctionCallExprSyntax` (optionally `return`ed) is already a named seam.

## Refutations

- **Single-call bodies** — the fixed form (condition 3).
- **Empty bodies** — nothing to extract.
- **Read-only closures** — no captured write. That is `pure-closure-candidate`'s territory when
  pure, and nobody's when it merely reads.
- **Local-only writes** — writes to a `var` declared inside the closure never escape.
- **Test files** — same skip the accessibility visitors already apply.
- ~~**`Button { … }` action closures** — already owned by `button-closure-wrapping`.~~ **Withdrawn.**
  Deferring wholesale would have opened a hole rather than closing an overlap.
  `button-closure-wrapping` fires only on a body that is a *single no-argument call*
  (`ButtonClosureWrappingVisitor.swift:20-45`) — exactly the shape condition 3 already excludes. The
  two rules therefore cannot collide: where that one reports, this one is silent by construction.
  What the deferral would have cost is every multi-statement effectful action —
  `Button { count += 1; save() }` — waived here and reported by nothing. Button actions are in
  scope; see condition 1.
- **Writes only to a closure parameter** — e.g. `inout` accumulators in `reduce(into:)`, which are
  local by construction.

## Message

> An effectful closure registered as a callback — no test can reach its effect.

"Registered as a callback" rather than the narrower "registered on a view modifier": since Button
actions are in scope (condition 1), a modifier-specific wording would misdescribe a whole surface.

**Suggestion:** *Lift the body into a named method; the effect becomes assertable through the state
it writes.*

Deliberately different from `pure-closure-candidate`'s "its captures become parameters" — that
advice is wrong here. The captures are not becoming parameters; the mutation target stays captured.
What changes is that the *effect* acquires a name a test can invoke.

## Severity and gating

`.info`. This reports a refactor, not a defect. The code works; it is simply unobservable.

**"Opt-in, matching its pure sibling" is not available, because rules have no opt-in switch.**
`SyntaxPattern` carries a severity and a category and nothing else — there is no per-rule enable
flag to set. What makes `pure-closure-candidate` feel opt-in is a *rendering* decision one layer up:
`CandidateInventory.inventoryRules` is exactly `{.pureFunctionCandidate, .pureClosureCandidate}`
(`CandidateInventory.swift:48-51`), those two collapse into a count in `text` output, and naming
`testability` in `--categories` un-collapses them (`SwiftProjectLintCLI.swift:155`). Machine formats
never collapse at all.

So this rule ships **listed by default** unless it is added to `inventoryRules`, and that is a
decision to make on purpose rather than inherit:

- **Don't add it** (preferred). The inventory's stated meaning is *property-test seeds* — the same
  refutal this rule was written to route around. A finding that is explicitly not a seed does not
  belong in the seed inventory, and widening the set to hold it would cost the inventory its
  meaning. Accept default-listed at `.info`, which is what `.extractablePureKernel` already does
  (`CandidateInventory.swift:32` records that choice and why).
- **Add it** only if a road test shows the volume is inventory-scale. `pure-closure-candidate` alone
  contributed 208 findings in the run recorded at `Docs/rules/pure-closure-candidate.md:253`; if
  this rule lands anywhere near that, collapsing becomes a readability argument that outweighs the
  taxonomy one. Measure before deciding.

## Registrar placement

Single-purpose visitor, so it gets its own leaf registrar — a `struct` conforming to
`PatternRegistrarProtocol` supplying one `var pattern`, wired into the `register(registrars:)` list
in `Testability.swift` alongside `ImpureCallInViewBody()` (`Testability.swift:105-108`). Not an
inline entry in the `patterns` array; that form is for rules sharing a multi-purpose category
visitor.

## Interaction with `could-be-private-member`

Acting on this rule widens access: the extracted method is called from one place in production, so
`could-be-private-member` is the natural next visitor to look at it.

Empirically it does **not** misfire, and the original figure reproduces exactly: a run against
SwiftUMLStudio reports `could-be-private-member` **39** times project-wide and on **none** of the four
extracted handlers (`selectNode`, `updateHover`, `clearSelection`, `handleArrow`), because the
cross-file visitor counts the test-file references as usages.

**But that result depends entirely on analysis scope, which is the part worth writing down.** Point
the linter at the app directory alone — `SwiftUMLStudio/SwiftUMLStudio` rather than the repository
root — and the picture inverts:

| scope | `could-be-private-member` | on extracted handlers |
|---|---|---|
| repository root (tests in scope) | 39 | **0** |
| app directory only (tests excluded) | 46 | **2** — `selectNode`, `selectParticipant` |

So the protection is real but conditional, and the mechanism is now confirmed rather than assumed. It
is **usage counting**, not the property-test exemption: that exemption is gated on
`propertyTestShape(of:) != nil` (`CouldBePrivateMemberVisitor.swift:151,160`) — a *pure* shape, which
these handlers are not. The moment usage counting stops seeing test files, the handlers you extracted
on this rule's advice get told to go back to `private`.

The two that fall out first are the ones whose names are unique to a single view. `updateHover`,
`clearSelection` and `handleArrow` are each declared by *both* diagram views, so a name-based
cross-file check sees them in more than one file regardless of tests — which means their apparent
safety in the narrow-scope run is a **name collision, not a real exemption**. `selectNode` and
`selectParticipant` have no twin, and they are exactly the two that get reported.

The explicit regression test this section asks for is still worth writing, and should pin the scoped
behaviour rather than just the happy path — the happy path passes for a reason that does not
generalise.

## Interaction with `impure-call-in-view-body`

Sharper than a timing distinction, and it is what removes `onAppear` / `onDisappear` from condition 1.

The two rules do target different moments — that rule catches impurity evaluated *during* body
evaluation, whereas these closures are merely *registered* during body evaluation and run later. But
they are not independent, because that rule's suggested fix names this rule's trigger surface
directly: *"Move it out of `body` — an action / `onAppear` for effects"*
(`ImpureCallInViewBodyVisitor.swift:84`). Allowlist `onAppear` and a developer who does exactly what
`impure-call-in-view-body` told them to do lands immediately on a fresh finding from this rule. Two
rules that hand a reader back and forth is how a whole category gets switched off.

Excluding both lifecycle modifiers from v1 costs little independently — they are usually one-liners,
which condition 3 mostly refutes anyway — and it removes the loop. Revisit only with a real project's
numbers showing what the exclusion misses.

## Feasibility

Structural AST, per-file. No cross-file graph, no flow analysis. The only genuinely new machinery is
"assignment whose LHS roots in a capture" — and **that prerequisite is now done**, via the upstream
route rather than a local reimplementation, so one definition of the predicate serves both rules.

`PurityInferrer.mutatesCapturedState(_ closure:)` is public in SwiftEffectInference as of `fc82ec4`
(SEI PR #6), forwarded here on `SwiftProjectLintVisitors.PurityInferrer`, with all three manifests
re-pinned. `CaptureMutationChecker` stays private — only the verdict crossed the boundary. The
implementation reads it directly; there is nothing left to build for condition 2.

Two things the prerequisite turned up that the rule must know:

- **Inverting `isPure` was never going to work.** That Bool folds four refuters — `async`/`throws`,
  markers, totality, capture mutation — and three are unrelated to captures. `{ print(x) }` is impure
  and mutates nothing. Pinned by `theCaptureClauseIsIndependentOfTheOtherRefuters` in
  `PurityOracleLawsTests`.
- **The predicate had a bug the audit found, now fixed.** Nested closures' *parameters* were not
  counted as locals, though their `let`/`var` were, so a nested `reduce(into:) { acc, x in acc += x }`
  read as a captured write — exactly the case this rule's own refutation list says must not fire.
  It measured as a no-op on both available corpora (SwiftProjectLint 10 → 10,
  SwiftInferProperties 250 → 250 `pure-closure-candidate` findings), so it changed nothing for the
  pure sibling; it was only ever going to matter for this rule.

One caveat carried over from SEI and worth re-reading before writing the visitor: the bound-name set
is **flat — scopes are not tracked**. A genuine captured write to `total` goes unrecorded if some
unrelated nested closure also binds a `total`. That errs toward *not* reporting, which is the right
direction for a rule making a positive claim, but it is the known soundness hole.

Main false-positive risk is condition 1's allowlist drifting behind SwiftUI. Prefer under-reporting:
an unlisted modifier is a missed finding, whereas inferring "any trailing closure on a member access
in a view body" would sweep in `Toggle`, `ForEach` and every custom view builder. `Button` is in
scope, but by being named explicitly (condition 1), not by being inferred.

## Road test

Implemented and measured across four corpora. **46 findings, no false positive found on inspection.**

One methodological warning, learned the hard way here: **pull before you measure, and check what
scope you are measuring.** Both mistakes were made during this road test — a stale SwiftUMLStudio
checkout produced a confident claim that its extraction had never happened, and analysing the app
directory instead of the repository root inverted the `could-be-private-member` result below. Neither
error was visible from the output; both looked like clean measurements.

| corpus | kind | total | `Button` | modifiers |
|---|---|---|---|---|
| SwiftUMLStudio (post-extraction) | SwiftUI app, gesture-heavy | 11 | 7 | 4 `onChange` |
| SwiftLintRuleStudio | SwiftUI app | 28 | 24 | 2 `onHover`, 2 `onChange` |
| SwiftProjectLint `Sources/App` | SwiftUI app | 7 | 7 | — |
| SwiftInferProperties | CLI/library, 598 files | 0 | — | — |

Three things the run settled:

**Acting on the rule silences it — measured, not argued.** SwiftUMLStudio was analysed by accident at
both ends of its own extraction: a stale checkout sitting at `cebd879` (pre-extraction) and then the
current tree at `daa9f41`.

| SwiftUMLStudio | findings | in the two extracted files |
|---|---|---|
| before (`cebd879`) | 17 | 6 |
| after (`095de17` onward) | 11 | **0** |

Every one of the six findings in `NativeDiagramView` and `NativeSequenceDiagramView` disappeared, and
nothing else moved. That is the end-to-end property a lint rule is usually asserted to have and rarely
shown to have: take its advice, and it stops reporting.

**The rule found its own motivating case unprompted**, on the pre-extraction tree —
`NativeDiagramView.swift:55` and `:70` are exactly the two closures in the *Worked example* above.

**Convergence holds on production code, not just fixtures.** The post-extraction file carries the
named forms, and the rule is silent on every one:

```swift
.onTapGesture(count: 2) { viewport.reset() }        // silent — single call
.onKeyPress(.rightArrow) { handleArrow(.right) }    // silent — single call
.onKeyPress(.escape) { clearSelection() }           // silent — the fixed form
```

That is condition 3 doing the job it exists for, on code nobody wrote to demonstrate it.

**The zero is a clean negative, not a null result.** SwiftInferProperties has no SwiftUI at all — no
imports, no listed modifiers, and its one `Button` match is a string literal inside a code emitter.
It tests that the rule stays quiet where it has nothing to say, which is where the *inferred* version
of condition 1 would have produced garbage: that corpus is dense with `map`/`filter`/`reduce`
closures (250 `pure-closure-candidate` findings). It does not test precision.

Precision rests on the 52 findings inspected across the three GUI apps.

## Open questions

1. ~~Should `onAppear` / `onDisappear` closures count?~~ **Resolved: excluded from v1.** Not because
   they are trivial — because of the hand-off loop with `impure-call-in-view-body`, above.
2. ~~Does this overlap `impure-call-in-view-body`?~~ **Resolved: no overlap, but a chain.** See that
   section. The road test it asked for is still worth running once both ship, to check the chain is
   actually broken and not just moved.
3. Is there a matching finding for AppKit/UIKit target-action and `NotificationCenter` observer
   blocks? Same unreachability, different surface. Out of scope for v1. **Still open.**
4. ~~Does `Button`-action volume swamp the modifier surface?~~ **Resolved: it dominates, and the
   widening was right.** 38 of 46 findings are `Button`. A modifiers-only v1 would have found **two**
   things in a whole GUI application (SwiftLintRuleStudio). The modifier arm earns its place only on
   gesture-heavy code — and note that on SwiftUMLStudio, the one corpus where modifiers led before the
   extraction (10 to 7), taking the rule's advice removed every modifier finding except `onChange`.

   The volume this predicted might reopen — inventory-scale, near `pure-closure-candidate`'s 208 —
   did not materialise. 46 across four corpora is an order of magnitude short, so the
   `inventoryRules` recommendation under *Severity and gating* stands unchanged: this rule stays out,
   and lists by default.
5. **New.** Does the single-assignment shape hold up in use? `{ selectedId = nil }` reports while
   `{ clear() }` does not, which follows from condition 3 — one has a seam, the other does not — and
   it fired for real (`Button("Select All") { enabledRuleNames = allRuleNames }`). It is the most
   arguable finding shape the rule produces and the likeliest source of "this is noise". Watch it
   before widening anything else.
