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

After extraction:

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
   `onHover`, `onChange`, `onSubmit`, `onDrag`, `onDrop`, `onAppear`, `onDisappear`, and the gesture
   callbacks `onEnded` / `onChanged` / `updating`.

   **`Button`'s action closure is deliberately present**, as a
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
   wants is the last of the four alone. See *Feasibility* for what that costs.
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

Empirically it does **not** misfire — a run against SwiftUMLStudio after the extraction above
reported `could-be-private-member` 39 times project-wide and on none of the four extracted handlers,
because the cross-file visitor counts the new test-file references as usages. Worth an explicit
regression test in this rule's suite regardless, since the two rules pull in opposite directions and
the exemption currently documented in `CouldBePrivateMemberVisitor` is gated on
`propertyTestShape(of:) != nil` — a *pure* shape, which these handlers are not. The protection here
appears to come from usage counting rather than from that exemption; if usage counting ever stops
seeing test files, these four would start being told to go back to `private`.

## Feasibility

Structural AST, per-file. No cross-file graph, no flow analysis. The only genuinely new machinery is
"assignment whose LHS roots in a capture" — and that machinery **exists but is not reachable from
this repo**, which is the real cost of v1.

`PurityInferrer` does decide the predicate, in a `CaptureMutationChecker` walk
(`SwiftEffectInference/PurityInferrer.swift:256-260`). But that type is `private final class` at
`PurityInferrer.swift:392`, visible only to the file that folds it into `isPure(_:)`. It lives in
`SwiftEffectInference`, a separate repository pinned here by revision (`bc084fb` in
`Package.resolved`), and reached only through the forwarding `PurityInferrer` in the Visitors package
— which exposes the folded Bool and nothing finer. Two ways out:

- **Expose it upstream.** A PR to SwiftEffectInference publishing the capture-mutation verdict —
  either `CaptureMutationChecker` itself or a `mutatesCapturedState(_ closure:)` member on
  `PurityInferrer` — then re-pin here and add a forwarding member to
  `SwiftProjectLintVisitors.PurityInferrer`. Correct long-term: it keeps one definition of the
  predicate, which is the whole reason the oracle was relocated to SEI in the first place. Costs a
  cross-repo round trip and a pin bump before this rule can build.
- **Reimplement locally.** A ~40-line visitor in this package. Ships without touching SEI, at the
  price of a second definition of "writes to a capture" that can drift from the one that refutes
  `pure-closure-candidate` — and these two rules are supposed to partition the same space, so drift
  between them is exactly the failure that matters.

Prefer the upstream route, and treat the SEI PR as a prerequisite of this one rather than a
follow-up.

Main false-positive risk is condition 1's allowlist drifting behind SwiftUI. Prefer under-reporting:
an unlisted modifier is a missed finding, whereas inferring "any trailing closure on a member access
in a view body" would sweep in `Toggle`, `ForEach` and every custom view builder. `Button` is in
scope, but by being named explicitly (condition 1), not by being inferred.

## Open questions

1. Should a closure that writes captured state **and** is non-trivial but lives on `onAppear` /
   `onDisappear` count? Those are lifecycle, often one-line, and often genuinely trivial. Possibly
   worth a lower tier or exclusion.
2. Does this overlap `impure-call-in-view-body`? That rule targets impurity evaluated *during* body
   evaluation; these closures are registered during body evaluation but run later. Different timing,
   different defect — but the two should be checked against each other on a real project before both
   ship enabled.
3. Is there a matching finding for AppKit/UIKit target-action and `NotificationCenter` observer
   blocks? Same unreachability, different surface. Out of scope for v1.
4. **New.** Does `Button`-action volume swamp the modifier surface? Button actions are now in scope
   (condition 1) and are far more common than gesture callbacks. If a road test shows they dominate
   the finding count, that is the evidence that would reopen the `inventoryRules` decision under
   *Severity and gating*. Measure the two surfaces separately from the first run.
