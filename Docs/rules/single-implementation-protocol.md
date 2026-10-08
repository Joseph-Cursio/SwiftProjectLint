[← Back to Rules](RULES.md)

## Single Implementation Protocol

**Identifier:** `Single Implementation Protocol`
**Category:** Architecture
**Severity:** Info
**Principle:** Dependency Inversion (SOLID), guarding against over-application

### Rationale
A protocol that is only adopted by one concrete type provides no polymorphism. Unless the protocol exists to enable test mocking, the extra layer of indirection adds cognitive load without architectural benefit. This is sometimes called "protocol soup" — unnecessary abstraction that obscures the actual implementation.

### Discussion
`SingleImplementationProtocolVisitor` uses cross-file analysis to count how many types conform to each protocol across the entire project. It flags protocols with zero conformers (dead code) or exactly one conformer (unnecessary abstraction).

A conformance counts wherever Swift lets it be written: in the type's own declaration, in a separate `extension Foo: P {}`, and through a `typealias`. A type conforming to `typealias OrderStore = OrderSaving & OrderHistory` conforms to both protocols, and is counted as a conformer of each. The expansion is transitive, so an alias that composes another alias is followed through. Reading the alias by its own name used to credit neither protocol, so every role it composed was reported as having *no* conformers. An alias name declared more than one way in the project (two different nested `typealias Element`s, or an alias sharing its name with a type) is not expanded, because the rule cannot tell which declaration a conformance means.

To reduce false positives, the rule applies several exemptions:
- **Mock conformers:** If any conformer's name contains "Mock", "Fake", "Stub", or "Spy", the protocol is not flagged — the abstraction exists for testability.
- **Test-file conformers:** Conformers in files matching `Tests/`, `Mocks/`, `Fakes/`, `Stubs/` are treated as test conformers. A protocol with 1 production conformer + 1 test conformer is suppressed.
- **DI-intent role suffixes:** Protocols ending with `Providing`, `Service`, `Repository`, `DataSource`, `Client`, or `Networking` are suppressed — these *role* words strongly imply the protocol exists for dependency injection. The bare `Protocol` suffix is **not** in this list: it is a widespread team naming convention for protocols (`FooProtocol`, enforced by the opt-in [Protocol Naming Suffix](protocol-naming-suffix.md)), not a role signal, so exempting it would suppress essentially every protocol and stop the rule from ever firing. A `FooProtocol` — or a `FooServiceProtocol`, which ends in `Protocol`, not the role word `Service` — with a single conformer and no mock is therefore still flagged.
- **Public protocols in standalone libraries:** A `public` or `open` protocol is skipped **only when the whole project is a standalone library** — one whose `Package.swift` declares *no* executable target. There, a public protocol may be part of the published API, intended for conformance by code in another module the analysis can't see. Once the project ships an executable (a CLI or app), it is not a published library: its library targets *and* its first-party nested packages (`Packages/…`, included via `--include-nested-packages`) are implementation detail with no external consumers, so their public protocols are analyzed just like internal ones. `public` there is merely Swift's cross-module access keyword, not an API-stability promise. Executable source roots are detected from `Package.swift` (`.executableTarget`); a project without a `Package.swift` can't be classified and is treated conservatively as a library, so every public protocol is skipped.
- **Test-file protocols:** Protocols declared inside test targets are skipped entirely.
- **Protocols consumed as an injected dependency:** a single-conformer protocol held as a stored property or received as an initializer parameter is a deliberate seam and is not flagged. A composition counts for each protocol in it, whether written inline (`let store: any OrderSaving & OrderHistory`) or through a `typealias` (`let store: any OrderStore`).

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

// Two conformers, both through a composition typealias. Each conforms to
// OrderSaving and OrderHistory, exactly as if it had listed them.
protocol OrderSaving { func save() }
protocol OrderHistory { func recent() }
typealias OrderStore = OrderSaving & OrderHistory
actor CoreDataOrderStore: OrderStore { /* … */ }
struct InMemoryOrderStore: OrderStore { /* … */ }

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
