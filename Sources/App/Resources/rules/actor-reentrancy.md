[← Back to Rules](RULES.md)

## Actor Reentrancy

**Identifier:** `Actor Reentrancy`
**Category:** Code Quality
**Severity:** Warning

### Rationale
Swift actors serialize access to their mutable state, but `await` introduces suspension points where other callers can interleave. If an async method reads a stored property to decide whether to proceed (e.g., a guard) and then `await`s without first updating that property, a second concurrent caller can pass the same guard before the first completes. This leads to duplicate expensive work, data races on external resources, or violated invariants.

### Discussion
`ActorReentrancyVisitor` detects async functions inside `actor` declarations where a stored `var` property is referenced in a `guard` or `if` condition and an `await` follows without an intervening assignment to that property. The fix is to update the property eagerly — before the `await` — to "claim the slot" and prevent concurrent callers from passing the same check.

```swift
// Before — reentrancy window between guard and await
actor InsightsEngine {
    var lastRunDate: Date?
    let minimumInterval: Duration = .seconds(60)

    func runIfDue() async throws -> [Bead] {
        if let lastRun = lastRunDate {
            let elapsed = Duration.seconds(Date.now.timeIntervalSince(lastRun))
            guard elapsed >= minimumInterval else { return [] }
        }
        return try await runAnalysis()
    }
}

// After — set lastRunDate eagerly to prevent reentrancy
actor InsightsEngine {
    var lastRunDate: Date?
    let minimumInterval: Duration = .seconds(60)

    func runIfDue() async throws -> [Bead] {
        if let lastRun = lastRunDate {
            let elapsed = Duration.seconds(Date.now.timeIntervalSince(lastRun))
            guard elapsed >= minimumInterval else { return [] }
        }
        lastRunDate = .now  // Claim the slot before awaiting
        return try await runAnalysis()
    }
}
```

### Non-Violating Examples
```swift
// Property set before await — no reentrancy window
actor DataLoader {
    var isLoading = false

    func fetchData() async throws -> Data {
        guard !isLoading else { return Data() }
        isLoading = true
        let result = try await performFetch()
        isLoading = false
        return result
    }
}

// Synchronous function — no suspension points
actor Counter {
    var count = 0

    func increment() {
        guard count < 100 else { return }
        count += 1
    }
}

// No guard/if on stored property before await
actor Fetcher {
    var data: Data?

    func fetch() async throws -> Data {
        let result = try await performFetch()
        data = result
        return result
    }
}
```

### Violating Examples
```swift
// Boolean guard without update before await
actor DataLoader {
    var isLoading = false

    func fetchData() async throws -> Data {
        guard !isLoading else { return Data() }
        let result = try await performFetch()
        return result
    }
}

// Optional-binding guard without update before await
actor Scheduler {
    var lastRunDate: Date?

    func runIfDue() async throws {
        if let lastRun = lastRunDate {
            guard Date().timeIntervalSince(lastRun) > 60 else { return }
        }
        return try await runAnalysis()
    }
}
```

---
