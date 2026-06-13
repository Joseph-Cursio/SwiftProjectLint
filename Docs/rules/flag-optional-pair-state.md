[← Back to Rules](RULES.md)

## Flag Optional Pair State

**Identifier:** `Flag Optional Pair State`
**Category:** State Management
**Severity:** Info
**Opt-in:** Yes

### Rationale
A State struct that declares a Bool flag alongside an **optional or collection**
whose presence the flag shadows is encoding a small state machine across two
independent fields — an "impossible state combination." The flag describes a
*transition* or a *predicate*; the data describes the *current value*. Those are
orthogonal axes, so the struct can represent combinations that are supposed to
be illegal:

- **loading with a stale result** — `isLoading == true` while the previous
  value is still present (re-fetching without clearing it);
- **loaded but flag off** — `isLoading == false` while the result is present
  (the normal resting state after a fetch — the flag and the result simply
  aren't opposites); and
- **predicate out of sync** — `hasError == true` with `errorMessage == nil`, or
  vice versa.

Because all four `(flag, data-present)` combinations are reachable, no `==`/`!=`
invariant between the two fields holds. The fix is to make the illegal
combinations **unrepresentable** with a single source of truth — a sum type:

```swift
enum Status {
    case idle
    case loading
    case loaded(Value)
}
```

or, when the flag is purely derivable, a **computed** flag:

```swift
var hasError: Bool { errorMessage != nil }
```

### Motivation — real TCA example code + common shapes
Motivated by PointFree's Composable Architecture case studies —

- **`ScreenA`** (NavigationStack) — `var isLoading = false` + `var fact: String?`.
  The fact persists after loading completes, so at rest `isLoading == false`
  while `fact != nil`.
- **`NavigateAndLoad`** — `var isNavigationActive = false` +
  `var optionalCounter: Counter.State?`.

— and the broader session/error/results shapes (`hasError` + `errorMessage`,
`isLoading` + `results: [User]`). Both TCA cases declare the flag with an
**inferred** type (`var isLoading = false`), so the rule treats a
boolean-literal initializer as a `Bool`. This code is **not buggy**, so the rule
is an **opt-in refactor suggestion** (`Info` severity), not an error.

### Discussion
`FlagOptionalPairStateVisitor` visits each `struct` and fires when it finds a
stored `Bool` flag together with a **pairable** property — one declared as an
Optional (`T?`) or a collection (`[T]` / `Array` / `IdentifiedArray(Of)`). `Bool`
is recognized by an explicit annotation *or* a boolean-literal initializer. Two
tiers, tuned for precision:

1. **Transition flags** — name matches `loading` / `fetching` / `refreshing` /
   `active` (the last excluding `interactive` / `inactive`). These pair with
   *any* pairable property; the verb names are specific enough.
2. **`has<X>` / `is<X>` flags** — must *name-correlate* with a pairable property,
   i.e. the stem after `has`/`is` (camelCase boundary, ≥ 4 chars) appears in a
   pairable property's name (`hasError` ↔ `errorMessage`). The correlation
   requirement keeps `isEnabled` + an unrelated optional from firing.

Detection is purely structural — no reducer flow analysis. Computed flags
(`var isLoading: Bool { status == .loading }`) are ignored, since a derived flag
is already the healthy shape.

**Known gap:** a flag with no shared name token — e.g. `isLoggedIn` +
`currentUser` — is *not* flagged. Detecting it precisely needs type-level
semantics, and a blanket "`is*` Bool + any optional" rule would be too noisy.

### Non-Violating Examples
```swift
// Already a sum type — illegal combinations are unrepresentable
struct State {
    var status: Status = .idle   // enum idle / loading / loaded(String)
}

// A flag with no pairable property — nothing to collapse
struct State {
    var isLoading = false
    var count = 0
}

// A pairable property with no flag
struct State {
    var fact: String?
    var count = 0
}

// Derived (computed) flag — already healthy
struct State {
    var status: Status = .idle
    var isLoading: Bool { status == .loading }
    var fact: String? { status.loadedValue }
}

// has<X> flag with no name-correlated property — tier 2 requires correlation
struct State {
    var hasError = false
    var userName: String?
}

// Known gap — no shared name token, not flagged
struct State {
    var isLoggedIn = false
    var currentUser: User?
}
```

### Violating Examples
```swift
// The ScreenA shape — inferred Bool flag + persisted optional result
struct State {
    var count = 0
    var fact: String?
    var isLoading = false
}

// The NavigateAndLoad shape
struct State {
    var isNavigationActive = false
    var optionalCounter: Counter.State?
}

// Explicit Bool type, same smell
struct State {
    var isFetching: Bool = false
    var result: Response?
}

// Tier 1 paired with a collection (isLoading may stay true after results arrive)
struct State {
    var isLoading = false
    var results: [User] = []
}

// Tier 2 — name-correlated has<X>/is<X>
struct State {
    var hasError = false
    var errorMessage: String?
}
struct State {
    var isSelected = false
    var selectedItem: Item?
}
```

---
