[← Back to Rules](RULES.md)

## Non-Idempotent Action Name

**Identifier:** `Non-Idempotent Action Name`
**Category:** Idempotency
**Severity:** Warning

### Rationale
An action named `setEnabled`, `dismiss`, `close`, `hide`, `select`, or `cancel` makes a promise by its name: it drives state to a *fixed point*. Applying it twice should equal applying it once — `reduce(reduce(s, a), a) == reduce(s, a)`. A body that **accumulates** (`badge += 1`) or **toggles** (`isOn.toggle()`) breaks that promise: the name says "idempotent," the behavior isn't.

```swift
enum Action { case setBadge }            // name says "set to a value"
// …
case .setBadge:
    state.badge += 1                     // flagged: actually increments
```

This is the exact class of mislabel that execution-based idempotence checks (e.g. SwiftInferProperties' measured verification) exist to catch — a `setBadge` that increments, a `hide` that toggles. The lint gives the same signal statically and instantly, before any test run.

### Discussion
`NonIdempotentActionNameVisitor` is a file-local SyntaxVisitor over `SwitchCaseSyntax`. A case is flagged when **both** hold:

1. **The case name sounds idempotent.** The leading enum-case name (the `.x` in `case .x` / `case let .x(v)`) is an exact witness — `dismiss`, `close`, `hide`, `select`, `cancel` — or has a witness prefix — `set…`, `show…`, `select…`.
2. **The synchronous body mutates non-idempotently.** It contains a compound assignment (`+=`, `-=`, `*=`, `/=`, `%=`) or a `.toggle()` call.

Scope is deliberately narrow:

- **Enum-case switches only.** The label must reference a leading `.name` pattern (the `switch action { case .x: … }` shape), so plain value switches aren't matched.
- **Synchronous body only.** The scan does **not** descend into closures, so a `+=` inside a returned effect (`.run { … }`) — which isn't the synchronous state reduction — is not flagged.
- **Shape-based, file-local.** No type resolution; the rule fires on the name + operator shape alone.

### Violating Examples

```swift
// `set…` prefix that accumulates
case .setBadge:
    state.badge += 1                     // flagged: +=

// exact witness that toggles
case .hide:
    state.menu.toggle()                  // flagged: .toggle()

// payload-bound case that accumulates
case let .setVolume(value):
    state.volume -= value                // flagged: -=
```

### Non-Violating Examples

```swift
// `set…` that assigns a fixed value — genuinely idempotent
case .setEnabled:
    state.enabled = true

// exact witness that assigns
case .dismiss:
    state.sheet = false

// accumulation, but the name doesn't claim idempotence
case .increment:
    state.count += 1

// `+=` inside an effect closure is not the synchronous reduction
case .dismiss:
    state.sheet = false
    return .run { _ in counter += 1 }
```

### Remediation
- **Make the body idempotent** — assign a fixed value instead of accumulating or toggling (`state.enabled = true`, not `+=` / `.toggle()`).
- **Rename the action** to reflect cumulative behavior (`increment`, `bumpBadge`, `toggleMenu`), so the name no longer promises idempotence.

### Suppression
If the name is intentional and the non-idempotence is by design, suppress with:

```swift
// swiftprojectlint:disable non-idempotent-action-name
case .setBadge:
    state.badge += 1
```

### Interpretation of Zero Findings
Zero findings is the expected, healthy outcome — most `set…`/`dismiss`/`close` actions do assign. A finding is a high-confidence name-vs-behavior mismatch worth a closer look.

---
