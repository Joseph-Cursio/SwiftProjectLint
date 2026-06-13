[← Back to Rules](RULES.md)

## Effect Cycle

**Identifier:** `Effect Cycle`
**Category:** Code Quality
**Severity:** Warning
**Opt-in:** No

### Rationale
A reducer arm that synchronously re-dispatches an action — `return .send(.x)` —
forms an edge in an action-dispatch graph. When those edges form a **cycle**,
the reducer loops forever:

```swift
case .start:
    return .send(.refresh)

case .refresh:
    return .send(.start)   // .start → .refresh → .start → …
```

There is no async boundary to break the loop: each `.send` is applied
synchronously, so the store re-enters the reducer immediately and never settles.

### Discussion
`EffectCycleVisitor` looks at each `switch action { … }` (the TCA reducer
convention — the switch subject is the bare identifier `action`). For every case
it records the actions dispatched via the **`.send(.X)` Effect form**, builds the
`caseName → sentAction` graph, and reports the first cycle it finds (a path like
`start → refresh → start`).

**Synchronous only — `.run` sends are excluded.** A `send(.x)` call inside a
`.run { send in … }` closure uses the closure's `send` parameter (a plain call,
not `.send`) and crosses an async boundary — timers, debounced work, and
request/response flows all live there and almost always terminate. Counting them
would drown the rule in false positives, so only the `.send` member-access form
counts.

**Caveat — conditional sends.** A guarded re-dispatch
(`if shouldContinue { return .send(.x) }`) still appears as an edge in the static
graph but may terminate dynamically. A flagged cycle therefore means *"verify
this terminates,"* not a proof of an infinite loop. This is why the message is
phrased as a cycle to break, and detection stays conservative (synchronous sends
only).

### Non-Violating Examples
```swift
// Linear flow — no cycle
case .start:
    return .send(.load)
case .load:
    return .none

// Re-dispatch across an async boundary — terminates, not flagged
case .tick:
    return .run { send in
        try await clock.sleep(for: .seconds(1))
        await send(.tick)        // plain `send`, inside `.run` → excluded
    }

// Request / response — async, not a synchronous cycle
case .reload:
    return .run { send in
        let value = try await api.fetch()
        await send(.response(value))
    }
case let .response(value):
    state.value = value
    return .none
```

### Violating Examples
```swift
// Two-cycle — the canonical infinite loop
case .start:
    return .send(.refresh)
case .refresh:
    return .send(.start)

// Self-cycle — synchronous self re-dispatch
case .tick:
    return .send(.tick)

// Longer cycle
case .a: return .send(.b)
case .b: return .send(.c)
case .c: return .send(.a)
```

---
