[<- Back to Rules](RULES.md)

## onReceive Without Debounce

**Identifier:** `onReceive Without Debounce`
**Category:** Performance
**Severity:** Info *(opt-in)*

### Rationale
`.onReceive()` with a high-frequency publisher (like `Timer.publish` at sub-second intervals or `NotificationCenter.publisher`) can trigger view updates at a rate that degrades performance. Adding `.debounce()`, `.throttle()`, or `.collect()` helps control update frequency.

### Discussion
`OnReceiveWithoutDebounceVisitor` inspects `.onReceive()` modifier calls, checks whether the publisher argument is a known high-frequency source, and verifies that the publisher chain includes a rate-limiting operator. Currently detected high-frequency sources:
- `Timer.publish(every:)` with an interval less than 1.0 second
- `NotificationCenter.default.publisher(for:)` (any notification)

This rule is opt-in because intentional high-frequency updates (e.g., game loops, real-time animations) would produce false positives.

### Non-Violating Examples
```swift
// Debounced publisher
.onReceive(
    searchText.publisher
        .debounce(for: .milliseconds(300), scheduler: RunLoop.main)
) { text in
    performSearch(text)
}

// Timer at >= 1 second
.onReceive(Timer.publish(every: 1.0, on: .main, in: .common).autoconnect()) { _ in
    updateClock()
}
```

### Violating Examples
```swift
// Sub-second timer without rate limiting
.onReceive(Timer.publish(every: 0.016, on: .main, in: .common).autoconnect()) { _ in
    updatePosition()
}

// NotificationCenter without rate limiting
.onReceive(NotificationCenter.default.publisher(for: .NSWorkspaceDidActivateApplication)) { _ in
    refresh()
}
```

---
