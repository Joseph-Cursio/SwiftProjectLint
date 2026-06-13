[← Back to Rules](RULES.md)

## Mutually Exclusive Presentation State

**Identifier:** `Mutually Exclusive Presentation State`
**Category:** State Management
**Severity:** Info
**Opt-in:** Yes

### Rationale
When a State struct declares two or more presentation optionals — `@Presents` /
`@PresentationState` properties such as `alert`, `confirmationDialog`, `sheet`,
`destination` — as **independent** fields, the type permits a combination that
is supposed to be illegal: more than one modal presented at once
(`alert != nil && confirmationDialog != nil`). Nothing in the type prevents it;
the mutual exclusion is enforced elsewhere (usually by UI modality at runtime),
not by the data model.

The idiomatic Swift / TCA fix is to make the illegal state **unrepresentable**:
collapse the separate optionals into a single `@Presents var destination:
Destination.State?` whose `Destination` is an enum with one case per modal. A
sum type can only be in one case at a time, so "two modals shown" becomes a
compile-time impossibility and there is nothing left to test or assert.

### Motivation — real TCA example code
This rule was motivated by PointFree's own Composable Architecture case studies,
which routinely model mutually-exclusive modals as separate optionals:

- **`AlertsAndConfirmationDialogs`** — `@Presents var alert` +
  `@Presents var confirmationDialog`, with no reducer logic niling one when the
  other is set.
- **`VoiceMemos`** — `@Presents var alert` + `@Presents var recordingMemo`.

That code is **not buggy**: modality means a user can never tap the second
button while the first modal covers the screen, so the both-non-nil state is
unreachable in the running app. Because the code is correct, this rule is an
**opt-in refactor suggestion** (`Info` severity), not an error — it points at a
"make illegal states unrepresentable" improvement, not a defect.

### Discussion
`MutuallyExclusivePresentationStateVisitor` visits each `struct` declaration and
counts stored properties that are **both** (a) annotated with `@Presents` or
`@PresentationState` **and** (b) of Optional type (`T?`). When the count is ≥ 2,
the struct is flagged. Detection is purely structural — the `@Presents` /
`@PresentationState` annotation is itself the TCA signal, so no surrounding
`@Reducer` / `State` context is required, and no flow analysis or presentation
semantics are modeled.

### Non-Violating Examples
```swift
// Single destination enum — illegal state is unrepresentable, nothing to flag
@ObservableState
struct State {
    @Presents var destination: Destination.State?   // one slot
}

// A single presentation optional is fine
@ObservableState
struct State {
    @Presents var alert: AlertState<Action.Alert>?
}

// Non-optional @Presents-annotated property (not a presentation slot) — ignored
struct State {
    @Presents var destination: Destination.State    // not Optional
}
```

### Violating Examples
```swift
// Two independent presentation optionals — both-non-nil is representable
// (the AlertsAndConfirmationDialogs shape)
@ObservableState
struct State {
    @Presents var alert: AlertState<Action.Alert>?
    @Presents var confirmationDialog: ConfirmationDialogState<Action.ConfirmationDialog>?
}

// The VoiceMemos shape
@ObservableState
struct State {
    @Presents var alert: AlertState<Action.Alert>?
    @Presents var recordingMemo: RecordingMemo.State?
}

// @PresentationState (older spelling) counts too
struct State {
    @PresentationState var sheet: SheetFeature.State?
    @PresentationState var popover: PopoverFeature.State?
}
```

---
