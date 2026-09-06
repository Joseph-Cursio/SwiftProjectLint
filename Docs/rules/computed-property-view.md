[<- Back to Rules](RULES.md)

## Computed Property View

**Identifier:** `Computed Property View`
**Category:** Architecture
**Severity:** Warning (Info if `@ViewBuilder` is present)

### Rationale
Computed properties that return `some View` are a common pattern for breaking up `body`, but they defeat SwiftUI's structural identity. SwiftUI can only diff views at the `body` boundary; sub-views expressed as computed properties get re-evaluated on every parent update with no diffing. Separate `struct` views give SwiftUI a stable identity boundary and can independently hold `@State`.

### Discussion
`ComputedPropertyViewVisitor` inspects `VariableDeclSyntax` nodes inside types that conform to `View`
(or have a `var body: some View` property), and considers any computed property other than `body`
whose type annotation is `some View`. Properties annotated with `@ViewBuilder` are reported at
`.info` severity since they at least get result-builder behaviour, though they still lack a stable
identity boundary.

**It does not report all of them.** The mechanism above is real but its benefit is *conditional*,
and the rule used to report it unconditionally — 341 findings across nine repositories, of which a
hand audit found many that could not benefit at all. Three gates now stand between a property and a
finding, and every one of them was measured against a 26-repository corpus rather than argued for.
The count is **134**.

#### Gate 1 — the property must take a narrower input than its parent

A child `View` only skips an update when its inputs are *narrower* than its parent's. Extract
`SummaryRow(issue:)` out of a view that re-renders whenever `issue` changes and the child re-renders
in lockstep: the same work, one more type.

So a property is reported only when its transitive dependency on the enclosing type's stored inputs
is a **strict subset** of them. A view with no inputs yields nothing — its value already compares
equal to itself, so SwiftUI can skip it unaided.

Dependencies are followed **transitively** through the type's other computed properties: a property
that reads nothing itself but calls one that reads `isExpanded` depends on `isExpanded`. Without
that, every wrapper property looks input-free and all of them fire.

This is a *necessary* condition for the diffing benefit, not a sufficient one — a two-line `Text`
gains little either way — but it is the condition the rule can check. A property depending on four
of five inputs still passes and its benefit is marginal; no threshold has a principled defence, so
none was invented.

#### Gate 2 — dialog and menu builders are left alone

`confirmationDialog(actions:)`, `alert(actions:)` and `Menu(content:)` read a *collection of
buttons* out of the closure they are handed. A `View` struct wrapping those buttons is a container
they are not specified to accept, so following this rule there could change **what the app does**
rather than only how it redraws. It is the one shape with that risk, and it is now silent.

The search covers a builder's arguments and trailing closures but never the called expression —
for a modifier that holds the receiver, which is the entire view it is applied to. It is
deliberately coarse in one direction: a name appearing in `alert`'s `message:` closure is spared
along with the ones in `actions:`. Sparing a property costs a finding; reporting one whose
extraction breaks a dialog costs a working app.

#### Gate 3 — a child that requires capture cannot be skipped

**This one is measured.** A harness counted `body` evaluations while changing state no child reads
(iOS 26.5, three changes):

| Child holds | Re-renders |
|---|---|
| No inputs, a value input, or a *non-capturing* closure | **0** |
| A `@Binding`, or a *capturing* closure | **3** — once per change |

Three is exactly as often as the inlined property it replaced, so extracting those is a new type for
no benefit. **The distinction is capture, not closures**: `action: { }` compiles to one static
function and compares equal, while `action: { showingSheet = true }` allocates a fresh context on
every parent body run, so the child value never compares equal. A `Binding` carries a getter and
setter and behaves the same way.

That correction came out of the measurement itself. The harness's first version used `action: { }`
and reported the opposite conclusion — a shape no real app contains would otherwise have decided
the design.

Three shapes force capture: reading a stored property's projected value (`$name`), assigning to one,
or calling one of the type's own methods. Followed transitively, since a property composing children
that each need a binding has to pass those bindings down.

#### What the rule still cannot see

It fires on the return type, so a property returning `String` or `Color` is invisible to it — and
those are often the ones holding a decision. Lifting three of them out of one view (a severity icon,
colour and accessibility label) stated two laws no per-case example could: no two severities may
share an icon or a colour, and none may share a VoiceOver label. Worth looking for by hand while
you are in the file.

### Non-Violating Examples
```swift
// body is never flagged
struct ContentView: View {
    var body: some View {
        VStack { HeaderView() }
    }
}

// Separate View struct — correct pattern
struct HeaderView: View {
    var body: some View {
        Text("Title").font(.largeTitle)
    }
}

// Non-View type — not flagged
struct Utility {
    var helper: some View {
        Text("Not in a View type")
    }
}
```

### Violating Examples
```swift
struct ContentView: View {
    // Warning: computed property returning some View
    var header: some View {
        Text("Title").font(.largeTitle)
    }

    // Info: @ViewBuilder mitigates slightly
    @ViewBuilder
    var footer: some View {
        Text("Footer")
    }

    var body: some View {
        VStack {
            header
            footer
        }
    }
}
```

---
