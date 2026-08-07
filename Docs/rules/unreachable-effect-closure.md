[← Back to Rules](RULES.md)

## Unreachable Effect Closure

**Identifier:** `Unreachable Effect Closure`
**Category:** Testability
**Severity:** Info

### Rationale

**An inline closure cannot be tested.** Not *is hard to test* — cannot. There is no name to call, no signature to satisfy, no seam to reach it through.

[Pure Closure Property-Test Candidate](pure-closure-candidate.md) opens with that argument and then narrows to *pure* closures, refuting anything that writes to what it captured. For a property-test seed that refutal is correct: you cannot generate inputs for a closure whose job is a side effect.

But the unreachability claim never depended on purity. The refutal is scoped to the wrong conclusion — it should refuse *property-test candidacy*, not refuse *extraction*. This rule is the other half: a closure that **writes to captured state**, is **registered as a callback** rather than called inline, and therefore has no seam through which any test can observe its effect.

For effectful closures the argument is stronger, not weaker. A silent regression in a side effect on shared state is precisely what a test exists to catch.

```swift
// Before — nothing can reach these
.onContinuousHover { phase in
    switch phase {
    case .active(let location):
        viewport.hoveredNodeId = hitNode(at: location)?.id
    case .ended:
        viewport.hoveredNodeId = nil
    }
}
.onKeyPress(.escape) {
    viewport.selectedNodeId = nil
    return .handled
}

// After — the effect has a name a test can invoke
.onContinuousHover { updateHover($0) }
.onKeyPress(.escape) { clearSelection() }

func updateHover(_ phase: HoverPhase) { … }
func clearSelection() -> KeyPress.Result { … }
```

Measured in SwiftUMLStudio (`NativeDiagramView`, `NativeSequenceDiagramView`), both files sat at **0% coverage**: `ImageRenderer` drives a real draw pass but never fires gestures or key presses, and ViewInspector cannot traverse those views at all — their bodies are `GeometryReader`s. After extraction, three real contracts became assertable: tapping empty canvas clears the selection, the pointer leaving the canvas clears the hover highlight, and an arrow key on an empty graph returns `.ignored` rather than being swallowed. None could be stated as a test before; all three are one careless edit from regressing.

### Discussion

`UnreachableEffectClosureVisitor` reports a `ClosureExprSyntax` when all three hold.

**1. Registered, not called.** Two surfaces, matched by an explicit allowlist:

- **View modifiers** — `onTapGesture`, `onLongPressGesture`, `onKeyPress`, `onContinuousHover`, `onHover`, `onChange`, `onSubmit`, `onDrag`, `onDrop`, and the gesture callbacks `onEnded` / `onChanged` / `updating`.
- **`Button` actions** — a `DeclReferenceExprSyntax` call rather than a member access, so it needs its own arm. Which closure is the action depends on the spelling: an explicit `action:` argument wins when present, because in `Button(action: { … }) { Text("Go") }` the *trailing* closure is the label, a `@ViewBuilder` and not a callback at all.

The allowlist is deliberate. Inferring "any trailing closure on a member access in a view body" would sweep in `Toggle`, `ForEach` and every custom view builder. **Prefer under-reporting**: an unlisted modifier is a missed finding, while a wrong inference is a finding the reader has to argue with. The cost is that the list drifts behind SwiftUI.

**2. Effectful on captured state.** The body assigns to something rooted in a capture rather than a parameter or a local. This consumes `PurityInferrer.mutatesCapturedState(_:)` from SwiftEffectInference — the same verdict [Pure Closure Property-Test Candidate](pure-closure-candidate.md) uses to *refute*, asked for the opposite purpose, so the two rules cannot disagree about what a captured write is.

Note that inverting `isPure` would **not** work: it folds four refuters into one Bool, and three of them have nothing to do with captures. `{ print(x) }` is impure and mutates no capture.

**3. Not already extracted.** The body is more than a single call expression.

This is what makes the rule converge. `.onKeyPress(.escape) { clearSelection() }` is the *fixed* form; reporting it would mean the advice can never be satisfied, and a rule that cannot be satisfied gets switched off. A body that is exactly one `FunctionCallExprSyntax` — optionally `return`ed — is already a named seam, and an empty body has nothing to extract.

A single **assignment** is not a call and does report. That asymmetry with `{ clear() }` is deliberate rather than an oversight: `{ selectedId = nil }` has no name either, and naming it is exactly the fix.

### Refutations

- **Single-call bodies** — the fixed form.
- **Empty bodies** — nothing to extract.
- **Read-only closures** — no captured write. That is the pure sibling's territory when pure, and nobody's when it merely reads.
- **Local-only writes** — writes to a `var` declared inside the closure never escape, and neither do writes to a closure parameter, including an `inout` accumulator in a nested `reduce(into:)`.
- **Test files** — the same skip the other testability visitors apply.
- **`Button` bodies that are a single no-argument call** — [Button Closure Wrapping](button-closure-wrapping.md) owns that exact shape, and condition 3 already excludes it here, so the two cannot double-report.
- **`onAppear` / `onDisappear`** — see below.

### Interaction with other rules

**[Impure Call in View Body](impure-call-in-view-body.md)** is why `onAppear` and `onDisappear` are absent from the allowlist. That rule's suggestion is *"move it out of `body` — an action / `onAppear` for effects"*, so listing `onAppear` here would hand a reader straight from that rule's fix into this rule's finding. Two rules passing someone back and forth is how a whole category gets disabled. The lifecycle modifiers are also usually one-liners, which condition 3 mostly refutes anyway, so the exclusion costs little.

**[Could Be Private Member](could-be-private-member.md)** pulls the other way: the extracted method is called from one place in production, so it becomes a candidate for `private`. Empirically it does not misfire — a run against SwiftUMLStudio after the extraction above reported `could-be-private-member` 39 times project-wide and on none of the four extracted handlers, because the cross-file visitor counts the new test-file references as usages. The protection comes from usage counting rather than from that rule's property-test exemption, which is gated on a *pure* shape these handlers do not have.

**[Button Closure Wrapping](button-closure-wrapping.md)** covers the complementary Button shape, as described in the refutations.

### Known limitations

The bound-name set backing condition 2 is **flat — scopes are not tracked**. A genuine captured write to `total` goes unrecorded if some unrelated nested closure also binds a `total`. That errs toward *not* reporting, which is the right direction for a rule making a positive claim, but it is a real hole.

### Severity

`Info`. This reports a refactor, not a defect — the code works, it is simply unobservable. Unlike its pure sibling it is **not** part of the collapsed candidate inventory, because that inventory means *property-test seeds* and this rule is definitionally not one; findings are listed in text output by default.
