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
- **Public protocols in library targets:** A `public` or `open` protocol declared in a **library** target is skipped — it may be part of the library's public API, intended for conformance by code in another module the analysis can't see. The same protocol declared in an **executable/app** target is *not* skipped: an app has no external consumers, so a dead or single-conformer public protocol there is just as suspect as an internal one. Executable source roots are detected from `Package.swift` (`.executableTarget`); a project without a `Package.swift` is treated as having no executable targets, so every public protocol is skipped.
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

// Single-conformer public protocol in a LIBRARY target — exempt, since an
// external module may provide another conformer.
public protocol Plugin { func run() }      // in Sources/MyLibrary/
struct DefaultPlugin: Plugin { func run() { } }
```

### Violating Examples
```swift
// Only one conformer, no mock — unnecessary abstraction
protocol DataLoader { func load() }
struct DefaultDataLoader: DataLoader { func load() { } }

// Zero conformers — dead protocol
protocol OrphanRule { func work() }

// Single-conformer public protocol in an EXECUTABLE target — flagged, because
// an app has no external module that could supply another conformer.
public protocol Command { func run() }     // in Sources/CLI/
struct RunCommand: Command { func run() { } }
```

> Note: a protocol named with a dependency-injection suffix (`…Protocol`,
> `…Service`, `…Client`, etc.) is suppressed by the DI-intent exemption
> regardless of target, so the examples above avoid those suffixes.

---
