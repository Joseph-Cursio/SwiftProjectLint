[← Back to Rules](RULES.md)

## Redundant Derived Property

**Identifier:** `Redundant Derived Property`
**Category:** State Management
**Severity:** Info
**Opt-in:** Yes

### Rationale
A stored property assigned from a **string interpolation of its sibling state
fields** is *derived*, not independent state:

```swift
struct State {
    var firstName: String
    var lastName: String
    var fullName: String   // derived
}

// reducer
state.fullName = "\(state.firstName) \(state.lastName)"
```

Storing it means re-deriving it on **every** change to the inputs — and the day
a code path updates `firstName` without updating `fullName`, the two go out of
sync. Make it a computed property, which can never go stale:

```swift
var fullName: String { "\(firstName) \(lastName)" }
```

### Discussion
`RedundantDerivedPropertyVisitor` fires at an assignment
`<base>.<target> = "<interpolation>"` when the interpolation references at least
one *other* `<base>.<field>` (same base as the target). It handles both the
unfolded (`SequenceExpr`) and folded (`InfixOperatorExpr`) assignment forms.

**Deliberately narrow (v1), for precision:**

- **String interpolation only.** Numeric aggregates (`total = a + b`,
  `count = items.count`) are *not* flagged — they are sometimes materialized for
  performance, and the companion property-inference tool
  (SwiftInferProperties) treats `count == items.count` as a *conservation
  invariant worth testing*, not a smell. Flagging them here would contradict
  that.
- **Same base required.** The interpolation must reference `<base>.<field>` with
  the same `<base>` as the target (`state.fullName` ← `state.firstName`) — the
  dominant TCA-reducer idiom. A derivation from a bare/`self` reference is not
  flagged.
- **Appends excluded.** `state.log = "\(state.log)\n\(entry)"` references the
  target itself — it accumulates rather than derives, and is not flagged.

The rule fires at the derive-assignment site; it does not perform cross-statement
"is this property *only ever* assigned this way" analysis.

### Non-Violating Examples
```swift
// Constant string — not derived from siblings
state.title = "Settings"

// Derived from external/action input, not a sibling field — keep stored
state.greeting = "Hello, \(name)!"   // `name` is a local, not state.name

// Append (references itself) — accumulation, not derivation
state.log = "\(state.log)\n\(entry)"

// Numeric aggregate — may be materialized; out of scope by design
state.total = state.price + state.tax
```

### Violating Examples
```swift
// The fullName shape
state.fullName = "\(state.firstName) \(state.lastName)"

// Derived display string
state.displayName = "\(state.user.name) (\(state.user.role))"

// Path built from sibling fields
state.path = "\(state.directory)/\(state.filename)"
```

---
