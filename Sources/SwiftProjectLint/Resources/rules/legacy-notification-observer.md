[← Back to Rules](RULES.md)

## Legacy Notification Observer

**Identifier:** `Legacy Notification Observer`
**Category:** Code Quality
**Severity:** Info

### Rationale
`addObserver(_:selector:name:object:)` uses the target-action pattern inherited from Objective-C. It requires `@objc` methods, is not type-safe, and creates implicit coupling between the observer and the notification. Modern Swift provides safer alternatives: `notifications(named:)` async sequences for structured concurrency, and `addObserver(forName:object:queue:using:)` with closures for callback-based observation.

### Discussion
`LegacyNotificationObserverVisitor` detects `addObserver` calls that include a `selector:` argument, which is the hallmark of the target-action variant. The closure-based `addObserver(forName:...)` variant is not flagged because it is already a reasonable modern pattern.

The preferred migration path depends on your concurrency model:

```swift
// Before — target-action pattern
NotificationCenter.default.addObserver(
    self,
    selector: #selector(handleNotification),
    name: .didUpdate,
    object: nil
)

// After (async/await) — structured concurrency
for await notification in NotificationCenter.default.notifications(named: .didUpdate) {
    handle(notification)
}

// After (closure) — callback-based
let token = NotificationCenter.default.addObserver(
    forName: .didUpdate,
    object: nil,
    queue: .main
) { notification in
    handle(notification)
}
```

### Non-Violating Examples
```swift
// Closure-based observer — already modern
NotificationCenter.default.addObserver(
    forName: .didUpdate,
    object: nil,
    queue: .main
) { notification in
    handle(notification)
}

// Async sequence — preferred approach
for await notification in NotificationCenter.default.notifications(named: .didUpdate) {
    handle(notification)
}

// Combine publisher
cancellable = publisher.sink { value in
    process(value)
}
```

### Violating Examples
```swift
// Target-action pattern with selector
NotificationCenter.default.addObserver(
    self,
    selector: #selector(handleNotification),
    name: .didUpdate,
    object: nil
)

// Same pattern on a custom notification center
center.addObserver(
    viewController,
    selector: #selector(onDataChanged),
    name: NSNotification.Name("DataChanged"),
    object: nil
)
```

---
