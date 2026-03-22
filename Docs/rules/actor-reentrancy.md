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

### False Positive: Resource Guards vs. Scheduling Sentinels

Not every `guard let x = prop` before an `await` is a reentrancy risk. The rule distinguishes between two patterns:

**Resource guard** — the bound name is the operand of the subsequent `await`. Multiple concurrent callers can legitimately proceed in parallel, each using their own captured snapshot. These are **not flagged**.

```swift
// Not flagged: `connection` is the receiver of `await connection.send(…)`
actor Client {
    var connection: Connection?

    func notify() async throws {
        guard let connection = connection else { throw MCPError.notConnected }
        try await connection.send(data)   // 'connection' is the await operand
    }
}

// Not flagged: `handlers` is the sequence of a for-in whose body awaits
actor Client {
    var notificationHandlers: [String: [Handler]] = [:]

    func handleMessage(_ msg: Message) async {
        guard let handlers = notificationHandlers[msg.method] else { return }
        for handler in handlers { try await handler(msg) }   // 'handlers' drives the await
    }
}
```

**Scheduling sentinel** — the property gates *whether* the operation should run at all, but is not itself consumed by the `await`. Two concurrent callers can both pass the gate before either updates it. These are **flagged**.

```swift
// Flagged: `lastRun` (bound from `lastRunDate`) does not appear in `await runAnalysis()`
actor InsightsEngine {
    var lastRunDate: Date?

    func runIfDue() async throws {
        if let lastRun = lastRunDate {
            guard elapsed >= minimumInterval else { return [] }
        }
        return try await runAnalysis()   // lastRunDate not claimed — two callers can race
    }
}
```

**Detection mechanism:** after finding an optional-binding condition (`guard let x = prop`), the rule checks whether the bound name `x` appears as a direct token in any `await` expression in the function, or as the sequence of a `for-in` whose body contains `await`. If it does, the condition is suppressed as a resource guard. The same suppression applies to expression conditions (`guard x != nil`) when the property name itself appears directly in an `await` operand.

**Residual false positive — indirect resource use:** the suppression only works when the property or its bound name appears as a *direct token* in the `await` expression. If the property is consumed one call-stack level below — e.g. `guard connection != nil` followed by `await self.send(request)` where `send()` internally uses `connection` — the visitor cannot detect the relationship without semantic data-flow analysis. These cases remain flagged. A practical workaround is to add a `// swiftprojectlint:disable actor-reentrancy` comment on the line.

---
