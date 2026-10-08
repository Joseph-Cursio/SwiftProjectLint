[← Back to Rules](RULES.md)

## Unused Protocol Requirement

**Identifier:** `Unused Protocol Requirement`
**Category:** Architecture
**Severity:** Info *(opt-in)*
**Principle:** Interface Segregation (SOLID)

### Rationale
Interface segregation says a client shouldn't depend on requirements it doesn't use.
[Fat Protocol](fat-protocol.md) checks a proxy for that — size — and needs an arbitrary
threshold to do it: at nine requirements a protocol passes, however few of them its clients
call. This rule checks the principle's own question. For every requirement of a project
protocol it asks whether any client calls it **through the protocol**, and reports the ones
nothing does, at any size.

A *client* is code holding a value typed with the protocol: a stored property, parameter or
local typed `P`, `any P`, `some P`, or `T` where `T: P`. A requirement that no client calls is
one every client is made to depend on without using, and one every conformer — every test double
included — has to implement for nothing.

### Discussion
`UnusedProtocolRequirementVisitor` runs cross-file. It builds a `ProtocolClientIndex` from every
file of the run in three passes, then reports from it.

1. **Clients.** Every binding typed with a project protocol: stored and computed properties,
   function, initializer, subscript and closure parameters, locals with a type annotation, and
   generic parameters constrained `<T: P>` or `where T: P`. `any`, `some`, `?`, `!`, `P & Q`,
   parentheses and typealiased compositions (`typealias Store = Saving & Reading`) are seen
   through. A binding typed with a protocol that refines `P` is a client of `P` too. So are a
   function returning `P`, a cast to `P`, and a local inferred from any of these
   (`let s = makeStore()`); a local inferred from anything else is unknown and ignored.
   Where a type reference to `P` sits is read with `ProtocolTypePosition`, the classifier
   [Unused Protocol Abstraction](unused-protocol-abstraction.md) also uses to tell a conformance
   from a use.
2. **Calls.** Within each binding's scope, the members reached through it: `store.save(order)`,
   `self.store.recentOrders()`, `store?.title`, `store.count = 1`. Requirements are matched by
   base name plus argument labels, so `load(id:)` and `load(name:)` are told apart; a trailing
   closure matches whatever its parameter is labelled. This is local name resolution, not type
   inference: `x.store`, with `x` untyped, is taken to be every protocol-typed property named
   `store`.
3. **Report.** A requirement of `P` that no client calls is reported once, at its declaration.

#### Decisions

- **A call on a concrete conformer does not count.** On Checkout's `essay/s3-layer-violation`
  branch, `CheckoutViewModel` builds its own `CoreDataOrderStore()` and calls `recentOrders()` on
  it. That code depends on the conformer, not on `OrderStore` — it is the layer violation the
  branch exists to show — so `recentOrders()` is still reported there, as it is on `main`, where
  nothing calls it at all. Likewise a conformer calling its own requirements on `self`
  (`receiptText(for:)` calling `order(withIdentifier:)`) is the concrete type talking to itself.
- **A protocol extension is code written against the protocol.** A requirement called from a
  member of `extension P` counts as used when that member is — through the protocol *or* on a
  concrete conformer, since removing the requirement would break the extension either way. Calls
  between extension members are followed transitively. An extension member nothing calls credits
  nothing.
- **An escaping value uses everything.** A protocol value passed to a parameter typed `P`,
  `any P`, `some P` or `T: P` is followed one hop: that parameter is a client of its own. Assigned
  to a protocol-typed property, returned from a function declared to return the protocol, used as
  an operand of `??` or `?:` (`injected ?? Default()`), or compared with `==`/`===`, it stays
  tracked. Passed anywhere else — to an unknown or framework
  function, into a collection, a string interpolation, a closure's result — it may reach any
  requirement, and the protocol is not judged. So is a protocol named in a position whose values
  cannot be followed at all: `[any P]`, `Box<any P>`, `P.self`, an enum payload, an associated
  type's constraint.
- **Tests are clients, but test code is not judged.** A test that calls a requirement through a
  protocol-typed double depends on the protocol as surely as production code does, so a
  requirement only a test calls is not reported. That matches the other cross-file rules that
  measure use: [Unused Protocol Abstraction](unused-protocol-abstraction.md) counts a use in a test
  file, and [Could Be Private Member](could-be-private-member.md) counts a reference from one. And
  like Could Be Private Member, which never reports a member *declared* in a test file, this rule
  never reports a protocol declared in test or fixture code (`Tests/`, `Fixtures/`, `Mocks/`,
  `Examples/`, …): that is scaffolding, often deliberately shaped sample code.

#### What is not judged

- **`public`, `open` and `package` protocols** — their clients can be in modules the run cannot
  see. [Unused Protocol Abstraction](unused-protocol-abstraction.md) skips them for the same reason.
- **A protocol with no clients at all** — that is
  [Unused Protocol Abstraction](unused-protocol-abstraction.md)'s finding, so it is not reported
  twice.
- **A protocol declared in test or fixture code** — see *Tests are clients* above.
- **`@objc` protocols and refinements of `NSObjectProtocol`** — delegates and data sources the
  frameworks call.
- **A protocol refining a framework protocol whose requirements aren't known** — directly or
  through other project protocols. The framework calls that protocol's requirements, and a
  project protocol may restate one: `protocol RunCommand: AsyncParsableCommand` restating
  `validate()`, which ArgumentParser runs on every command. The framework protocols whose
  requirements *are* known can be refined freely — `Sendable`, `AnyObject`, `Actor`,
  `Equatable`, `Hashable`, `Comparable`, `Identifiable`, `Codable`, `Error`, `LocalizedError`,
  `CustomStringConvertible`, `CaseIterable`, `RawRepresentable`, `Sequence`, `AsyncSequence`,
  their iterators, `View`, `ViewModifier`, `Shape`, `App`, `Scene`, `Observable`,
  `ObservableObject`, `Transferable`, `EnvironmentKey`, `PreferenceKey` and the marker
  protocols — because what they require is static, an initializer, or on the name list below.
- **Protocols carrying a macro** — any attribute other than a global actor, `@preconcurrency`,
  `@available` or `@usableFromInline`. A macro can generate callers the run cannot see, such as
  a type eraser forwarding every requirement.
- **Static requirements, initializers and associated types** — reached through metatypes
  (`T.make()`, `type(of: x).init()`), which this resolution does not follow.
- **Requirements the frameworks call by convention**, whatever protocol restates them: `body`,
  `makeBody`, `makeCoordinator`, `sizeThatFits`, `path`, `animatableData`, `defaultValue`,
  `reduce`, `transferRepresentation`, the `UIViewRepresentable`/`NSViewRepresentable` and
  view-controller-representable methods, `id`, `hash`, `hashValue`, `encode`, `description`,
  `debugDescription`, the four `LocalizedError` members, `makeIterator`, `next`,
  `makeAsyncIterator`, `rawValue`, `allCases`, `wrappedValue`, `projectedValue`,
  `unownedExecutor`, `startIndex`, `endIndex`, `index` and `objectWillChange`. Matched by base
  name.

#### Known limitations

- **An inferred local from an unknown expression is invisible.** `let s = registry.lookup()`,
  where `lookup` is not a project function returning the protocol, is not a client, so a call
  through `s` is missed and the requirement it calls can be reported. A type annotation on the
  local makes it a client.
- **Name resolution can merge namesakes.** Two protocols of one name, or a property `store` on two
  types, are credited together. That only ever suppresses a finding.
- **The run must hold every client.** Like
  [Unused Protocol Abstraction](unused-protocol-abstraction.md), the rule assumes it sees the
  whole module; pointed at a subdirectory, clients elsewhere in the module are missed.

### Non-Violating Examples
```swift
protocol OrderSaving: Sendable {
    func save(_ order: Order) async throws
}

final class CheckoutViewModel {
    private let store: any OrderSaving
    init(store: any OrderSaving) { self.store = store }
    func placeOrder(_ order: Order) async throws {
        try await store.save(order)   // the protocol's only requirement, used
    }
}
```

```swift
// Passed on to an unknown function: it may reach anything, so nothing is reported.
func archive(_ store: any OrderStore) {
    Logger.shared.attach(store)
}
```

### Violating Examples
```swift
protocol OrderStore: Sendable {
    func save(_ order: Order) async throws
    func recentOrders() async throws -> [Order]   // ← reported: no client calls it
}

final class CheckoutViewModel {
    private let store: any OrderStore
    init(store: any OrderStore) { self.store = store }
    func placeOrder(_ order: Order) async throws {
        try await store.save(order)
    }
}
```

**Suggestion:** Remove the requirement from the protocol and keep it on the conforming types that
need it, or move it to a protocol for the clients that will call it.

### Measured

Measured on 2026-10-07 over the latest `origin` default branch of every Swift repository in the
author's projects folder — 24 of the author's own (the SwiftProjectLint, SwiftInferProperties and
RuleStudio families, MacCloud, the pbt-book code, Checkout, and others) and 9 third-party clones
(SwiftLint, Hummingbird, ViewInspector, swift-argument-parser, swift-aws-lambda-runtime, Harmonize,
SwiftPlantUML, Sitrep, TestableView) — each run at its root with `--include-nested-packages` and
only this rule enabled. Every finding was read against the source.

**The reproduction target behaves as designed.** On Checkout's `solid/i-fat-store` the rule
reports the nine requirements `CheckoutViewModel` never calls, and not `save`. On `main` and on
`essay/s3-layer-violation` it reports `recentOrders()` — on the latter despite the concrete call,
per the decision above. On `solid/i-split-store` it reports nothing: `OrderSaving`'s one
requirement is used, and the other three roles have no clients.

**Across the corpus it fires twice, and both findings are right.**

| finding | why it is real |
|---|---|
| Checkout `OrderStore.recentOrders()` | the one client calls only `save` |
| SwiftMarkdownWiki `Snapshotting.prune(for:keeping:)` | only `SnapshotManager` calls it, on itself; tests call it on a concrete `SnapshotManager` |

Two is few, and the census of every protocol in the corpus says why:

| | author's (24) | third-party (9) |
|---|---|---|
| protocols | 254 | 179 |
| `public`, `open` or `package` | 197 | 122 |
| declared in test or fixture code | 4 | 12 |
| refines a framework protocol whose requirements aren't known | 4 | 3 |
| no clients | 7 | 10 |
| a value reaches an opaque position | 10 | 13 |
| a value escapes | 2 | 6 |
| **judged** | **30** | **13** |
| findings | 2 | 0 |

Most of the author's repositories are packages, and most of their protocols are API. Of the 43
protocols judged, 41 have every reportable requirement called through them; they are small — 28 have
one or two reportable requirements, and none has more than six. The guards cost recall where it would matter most: SwiftMutator's
21-requirement `AnyMutationTestState` is not judged because a test spy keeps an
`[AnyMutationTestState]`, and its 16-requirement `MuterProcess` because a factory closure returns
one. Each guard skipped here was checked to be skipping for the reason it states — the framework
ones are JWTKit's `JWTPayload`, SwiftSyntax's macro and syntax protocols, ArgumentParser's
`AsyncParsableCommand` and SwiftPM's `CommandPlugin`.

**The resolution was also checked where the rule does not ship.** Lifting only the API guard —
judging `public` protocols as if their clients were all in the run, as they usually are in a
repository that pairs an app with its own packages — adds 16 would-be findings across eight
repositories. All 16 were read, and in
every one the requirement really is never called through the protocol: `ConfigurationPersistenceProtocol`
in this repository (`ContentViewModel` saves through `SafeFileWriter` and `LintConfigurationWriter`
directly, so `write(_:to:)` and `load(from:)` are unreachable through the protocol); SwiftLint's
`Documentable`, whose four requirements are called only on concrete types; requirements that only
a conformer calls on itself, or a test on a concrete double. None of them is a missed call. That is
evidence about precision, not about the guard — the guard stays, because the clients of a published
protocol are not, in general, in the run.

**What measuring changed.** One false positive was found and fixed: SwiftMutator's
`RunCommand: AsyncParsableCommand` restates `validate()`, which ArgumentParser calls — hence the
framework-refinement guard. Two over-approximations were narrowed because they suppressed real
findings, not because they produced wrong ones: `injected ?? Default()` (the default-injection idiom)
counted as an escape, and so did `Self.message(…)`, a static call that constructs nothing.
SwiftMarkdownWiki's finding was hidden by the first of these until it was fixed.

### See also

- [Fat Protocol](fat-protocol.md) — the size-based reading of the same principle.
- [Unused Protocol Abstraction](unused-protocol-abstraction.md) — a protocol with conformers but no
  clients at all.
- [Single Implementation Protocol](single-implementation-protocol.md) — what splitting a protocol
  without clients for the parts produces.
- **Stage 2, not built:** the same client and call data can suggest *splitting* a protocol whose
  requirements fall into groups that no single client uses across — one client calling `save`,
  another calling `recentOrders` and `receiptText(for:)`. `ProtocolClientIndex` keeps each
  client's uses separately rather than merged for that reason.

---
