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
- **DI-intent role suffixes:** Protocols ending with `Providing`, `Service`, `Repository`, `DataSource`, `Client`, or `Networking` are suppressed — these *role* words strongly imply the protocol exists for dependency injection. The bare `Protocol` suffix is **not** in this list: it is the universal Swift naming convention for protocols (`FooProtocol`), not a role signal, so exempting it would suppress essentially every protocol and stop the rule from ever firing. A `FooProtocol` — or a `FooServiceProtocol`, which ends in `Protocol`, not the role word `Service` — with a single conformer and no mock is therefore still flagged.
- **Public protocols in standalone libraries:** A `public` or `open` protocol is skipped **only when the whole project is a standalone library** — one whose `Package.swift` declares *no* executable target. There, a public protocol may be part of the published API, intended for conformance by code in another module the analysis can't see. Once the project ships an executable (a CLI or app), it is not a published library: its library targets *and* its first-party nested packages (`Packages/…`, included via `--include-nested-packages`) are implementation detail with no external consumers, so their public protocols are analyzed just like internal ones. `public` there is merely Swift's cross-module access keyword, not an API-stability promise. Executable source roots are detected from `Package.swift` (`.executableTarget`); a project without a `Package.swift` can't be classified and is treated conservatively as a library, so every public protocol is skipped.
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

// Single-conformer public protocol in a STANDALONE LIBRARY (the project declares
// no executable target) — exempt, since an external module may provide another
// conformer.
public protocol Plugin { func run() }      // library-only project, in Sources/MyLibrary/
struct DefaultPlugin: Plugin { func run() { } }
```

### Violating Examples
```swift
// Only one conformer, no mock — unnecessary abstraction
protocol DataLoader { func load() }
struct DefaultDataLoader: DataLoader { func load() { } }

// Zero conformers — dead protocol
protocol OrphanRule { func work() }

// Single-conformer public protocol in an app that ships an executable — flagged,
// because the app has no external module that could supply another conformer.
// This holds wherever the protocol lives in such a project: an executable target
// (Sources/CLI/), a library target (Sources/Core/), or a first-party nested
// package (Packages/Config/…).
public protocol Command { func run() }     // in Sources/CLI/
struct RunCommand: Command { func run() { } }
```

> Note: a protocol named with a dependency-injection suffix (`…Protocol`,
> `…Service`, `…Client`, etc.) is suppressed by the DI-intent exemption
> regardless of target, so the examples above avoid those suffixes.

---
