[← Back to Rules](RULES.md)

## Single Implementation Protocol

**Identifier:** `Single Implementation Protocol`
**Category:** Architecture
**Severity:** Info

### Rationale
A protocol that is only adopted by one concrete type provides no polymorphism. Unless the protocol exists to enable test mocking, the extra layer of indirection adds cognitive load without architectural benefit. This is sometimes called "protocol soup" — unnecessary abstraction that obscures the actual implementation.

### Discussion
`SingleImplementationProtocolVisitor` uses cross-file analysis to count how many types conform to each protocol across the entire project. It flags protocols with zero conformers (dead code) or exactly one conformer (unnecessary abstraction).

To reduce false positives, the rule applies several exemptions:
- **Mock conformers:** If any conformer's name contains "Mock", "Fake", "Stub", or "Spy", the protocol is not flagged — the abstraction exists for testability.
- **Test-file conformers:** Conformers in files matching `Tests/`, `Mocks/`, `Fakes/`, `Stubs/` are treated as test conformers. A protocol with 1 production conformer + 1 test conformer is suppressed.
- **DI-intent suffixes:** Protocols ending with `Protocol`, `Providing`, `Service`, `Repository`, `DataSource`, `Client`, or `Networking` are suppressed — these names strongly imply the protocol exists for dependency injection.
- **Public protocols:** Protocols marked `public` or `open` are skipped because they may be part of a library's public API, intended for external conformance.
- **Test-file protocols:** Protocols declared inside test targets are skipped entirely.

### Non-Violating Examples
```swift
// Two conformers — genuine polymorphism
protocol Repository { func fetch() }
struct RemoteRepository: Repository { func fetch() { } }
struct LocalRepository: Repository { func fetch() { } }

// One conformer + mock — testability justifies the protocol
protocol NetworkClient { func request() }
struct URLSessionClient: NetworkClient { func request() { } }
struct MockNetworkClient: NetworkClient { func request() { } }
```

### Violating Examples
```swift
// Only one conformer, no mock — unnecessary abstraction
protocol DataLoader { func load() }
struct DefaultDataLoader: DataLoader { func load() { } }

// Zero conformers — dead protocol
protocol OrphanProtocol { func work() }
```

---
