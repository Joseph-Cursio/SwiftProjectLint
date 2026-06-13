[← Back to Rules](RULES.md)

## Flag Optional Pair State

**Identifier:** `Flag Optional Pair State`
**Category:** State Management
**Severity:** Info
**Opt-in:** Yes

### Rationale
A State struct that declares a transition Bool flag — `isLoading`,
`isFetching`, `isRefreshing`, `isActive` — alongside an Optional "result"
property is encoding a small state machine across two independent fields. The
flag describes a *change in progress*; the optional describes the *current
value*. Those are orthogonal axes, so the struct can represent combinations
that are supposed to be illegal:

- **loading with a stale result** — `isLoading == true` while the previous
  optional value is still present (re-fetching without clearing it), and
- **loaded but flag off** — `isLoading == false` while the result is present
  (the normal resting state after a fetch — the flag and the result simply
  aren't opposites).

Because all four `(flag, result-present)` combinations are reachable, no
`==`/`!=` invariant between the two fields holds. The fix is to make the
illegal combinations **unrepresentable** by modeling the pair as a single sum
type:

```swift
enum Status {
    case idle
    case loading
    case loaded(Value)
}
```

A sum type holds one case at a time, so "loading" and "have a value" can no
longer drift apart.

### Motivation — real TCA example code
This rule was motivated by PointFree's Composable Architecture case studies,
which model exactly this shape:

- **`ScreenA`** (NavigationStack case study) — `var isLoading = false` +
  `var fact: String?`. The fact persists after loading completes, so at rest
  `isLoading == false` while `fact != nil`.
- **`NavigateAndLoad`** — `var isNavigationActive = false` +
  `var optionalCounter: Counter.State?`.

Both declare the flag with an **inferred** type (`var isLoading = false`), so
the rule treats a boolean-literal initializer as a `Bool`. This code is **not
buggy**, so the rule is an **opt-in refactor suggestion** (`Info` severity),
not an error.

### Discussion
`FlagOptionalPairStateVisitor` visits each `struct` and fires when it finds
**both**:

1. a **stored** `Bool` property whose name matches the transition heuristic
   (`loading` / `fetching` / `refreshing` / `active`, the last excluding
   `interactive` / `inactive`), where `Bool` is recognized by an explicit
   annotation *or* a boolean-literal initializer, and
2. any property declared with an Optional type (`T?`).

Detection is purely structural — no reducer flow analysis. Computed flags
(`var isLoading: Bool { status == .loading }`) are ignored, since a derived
flag is already the healthy shape.

### Non-Violating Examples
```swift
// Already a sum type — illegal combinations are unrepresentable
struct State {
    var status: Status = .idle   // enum idle / loading / loaded(String)
}

// A flag with no optional result — nothing to collapse
struct State {
    var isLoading = false
    var count = 0
}

// An optional with no transition flag
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
```

---
