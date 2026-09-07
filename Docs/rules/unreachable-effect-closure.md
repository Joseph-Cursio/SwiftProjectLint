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

Measured in SwiftUMLStudio (`NativeDiagramView`, `NativeSequenceDiagramView`), where both files sat at **0% coverage**: `ImageRenderer` drives a real draw pass but never fires gestures or key presses, and ViewInspector cannot traverse those views at all — their bodies are `GeometryReader`s. After extraction, three real contracts became assertable: tapping empty canvas clears the selection, the pointer leaving the canvas clears the hover highlight, and an arrow key on an empty graph returns `.ignored` rather than being swallowed. None could be stated as a test before; all three are one careless edit from regressing.

That extraction has since landed in that project, which gave the rule an end-to-end check: **17 findings before, 11 after, and all 6 in the two extracted files gone.** Take the advice and the rule stops reporting.

### Discussion

`UnreachableEffectClosureVisitor` reports a `ClosureExprSyntax` when all four hold.

**1. Registered, not called.** Two surfaces, matched by an explicit allowlist:

- **View modifiers** — `onTapGesture`, `onLongPressGesture`, `onKeyPress`, `onContinuousHover`, `onHover`, `onChange`, `onSubmit`, `onDrag`, `onDrop`, and the gesture callbacks `onEnded` / `onChanged` / `updating`.
- **`Button` actions** — a `DeclReferenceExprSyntax` call rather than a member access, so it needs its own arm. Which closure is the action depends on the spelling: an explicit `action:` argument wins when present, because in `Button(action: { … }) { Text("Go") }` the *trailing* closure is the label, a `@ViewBuilder` and not a callback at all.

The allowlist is deliberate. Inferring "any trailing closure on a member access in a view body" would sweep in `Toggle`, `ForEach` and every custom view builder. **Prefer under-reporting**: an unlisted modifier is a missed finding, while a wrong inference is a finding the reader has to argue with. The cost is that the list drifts behind SwiftUI.

**2. Effectful on captured state.** The body assigns to something rooted in a capture rather than a parameter or a local. This consumes `PurityInferrer.mutatesCapturedState(_:)` from SwiftEffectInference — the same verdict [Pure Closure Property-Test Candidate](pure-closure-candidate.md) uses to *refute*, asked for the opposite purpose, so the two rules cannot disagree about what a captured write is.

Note that inverting `isPure` would **not** work: it folds four refuters into one Bool, and three of them have nothing to do with captures. `{ print(x) }` is impure and mutates no capture.

**3. Not already extracted.** The body is more than a single call expression.

This is what makes the rule converge. `.onKeyPress(.escape) { clearSelection() }` is the *fixed* form; reporting it would mean the advice can never be satisfied, and a rule that cannot be satisfied gets switched off. A body that is exactly one `FunctionCallExprSyntax` — optionally `return`ed — is already a named seam, and an empty body has nothing to extract.

A single **assignment** is not a call and does report. That asymmetry with `{ clear() }` is deliberate rather than an oversight: `{ selectedId = nil }` has no name either, and naming it is exactly the fix — *provided the state it writes is somewhere a test can reach*, which is condition 4.

**4. The effect has somewhere to be observed from.** A closure whose every write is a direct assignment to the enclosing view's own `@State` or `@FocusState` is **not** reported, because for that storage the rule's promise is false.

This is the one condition on the rule that was measured rather than reasoned about, and it had to be: 50 of the rule's 87 corpus findings wrote nothing but view-local `@State`, so more than half of what it asked for turned on whether naming such a write creates a seam. `Tests/AppTests/StateSeamHarnessTests.swift` builds both forms — the reported body and the extraction the suggestion describes — and tries every route a test has to the state afterwards:

| Route | Result |
| --- | --- |
| Call the extracted method on the view | property unchanged |
| Read it back through the rendered body | unchanged |
| Fire the button through ViewInspector | unchanged, for **both** the inline and the extracted button |

`@State`'s storage is allocated when SwiftUI installs the view. Before that the setter has nowhere to write and the getter answers from the initial value. The one route that observes the property is `ViewHosting.host`, and it goes through SwiftUI's storage rather than through the name — so it works identically either way. **The seam a test uses is the button, and the button exists in both forms.** The method exists in one and adds nothing.

The third row is what makes the other two mean anything. Without it the harness shows only that nothing works, which is not a finding.

**The gate is narrow because the same harness shows where the promise holds.** Three write targets stay reported, each measured:

- **`@Binding`** — the storage belongs to the parent, and a test supplies its own `Binding(get:set:)` and reads the write back. 15 corpus write targets.
- **`@AppStorage`** — the setter writes straight through to the defaults store, which a test reads with no view at all. 4 corpus write targets.
- **A member write** — `viewModel.searchQuery = ""`, `model.extraArguments = new`. The object outlives the view, so the method moves onto it and a test calls it directly. 17 corpus write targets.

So *one* non-`@State` write anywhere in the body keeps the whole finding. The gate's claim is about the only thing the body does, and under-gating is the safe direction.

`@FocusState` is included on measurement rather than on mechanism: no corpus finding writes one, and the harness covers it because that was cheaper than arguing about it. `@GestureState` is **not** included — same storage mechanism, no corpus instance, and no harness case, so it is left reporting rather than gated on a theory.

The `@State` set is keyed **per type, not per file**. Two views in one file routinely use the same property name for different storage, and a file-wide set would let one view's `@State private var text` gate another view's `@Binding var text`.

### Refutations

- **Single-call bodies** — the fixed form.
- **Empty bodies** — nothing to extract.
- **Read-only closures** — no captured write. That is the pure sibling's territory when pure, and nobody's when it merely reads.
- **Local-only writes** — writes to a `var` declared inside the closure never escape, and neither do writes to a closure parameter, including an `inout` accumulator in a nested `reduce(into:)`.
- **Writes to nothing but the view's own `@State` / `@FocusState`** — condition 4. Measured, not assumed.
- **Test files** — the same skip the other testability visitors apply.
- **`Button` bodies that are a single no-argument call** — [Button Closure Wrapping](button-closure-wrapping.md) owns that exact shape, and condition 3 already excludes it here, so the two cannot double-report.
- **`onAppear` / `onDisappear`** — see below.

### Interaction with other rules

**[Impure Call in View Body](impure-call-in-view-body.md)** is why `onAppear` and `onDisappear` are absent from the allowlist. That rule's suggestion is *"move it out of `body` — an action / `onAppear` for effects"*, so listing `onAppear` here would hand a reader straight from that rule's fix into this rule's finding. Two rules passing someone back and forth is how a whole category gets disabled. The lifecycle modifiers are also usually one-liners, which condition 3 mostly refutes anyway, so the exclusion costs little.

**[Could Be Private Member](could-be-private-member.md)** pulls the other way: the method you extract is called from one place in production, so it becomes a candidate for `private` — which would undo the seam you just made. Measured against SwiftUMLStudio after its extraction, it does **not** misfire: 39 findings project-wide and none on the four extracted handlers, because the cross-file visitor counts the test-file references as usages.

**That result depends on analysis scope.** Analyse the app directory alone, with test files out of scope, and the count rises to 46 and two of the handlers *are* reported. The protection comes from usage counting, not from that rule's property-test exemption — which is gated on a *pure* shape these handlers do not have. If you lint an app target without its tests, expect to be told to make the method you just extracted `private` again.

**[Button Closure Wrapping](button-closure-wrapping.md)** covers the complementary Button shape, as described in the refutations.

### Known limitations

The bound-name set backing condition 2 is **flat — scopes are not tracked**. A genuine captured write to `total` goes unrecorded if some unrelated nested closure also binds a `total`. That errs toward *not* reporting, which is the right direction for a rule making a positive claim, but it is a real hole.

**Condition 2 detects assignments only, so a body of nothing but mutating calls is never reported.** `PurityInferrer.mutatesCapturedState(_:)` walks `SequenceExprSyntax` for an assignment operator, so `.onTapGesture { items.append(x); items.sort() }` mutates captured state, has no name, and has never appeared in a count. Closing it would *raise* the number, which is why it is written down here rather than done quietly. Condition 4's own collector does recognise those calls, but only as a disqualifier — reachable when the body also contains an assignment, and never on its own.

**Condition 4 cannot tell a value the view owns from an object it references.** `@State private var draft = Draft()` writing `draft.title = x` is a member write on an object that outlives the view, and `@State private var items: [Int]` writing `items.append(x)` is a mutation of view-local storage. Both are `name.member(…)` and neither is gated. Under-gating, which is the direction this rule chooses everywhere else.

### Severity

`Info`. This reports a refactor, not a defect — the code works, it is simply unobservable. Condition 4 sharpens what *unobservable* means: the rule now claims only that the effect has somewhere it could be observed from once it has a name, which is the claim the category makes and the one the harness can check. Unlike its pure sibling it is **not** part of the collapsed candidate inventory, because that inventory means *property-test seeds* and this rule is definitionally not one; findings are listed in text output by default.
