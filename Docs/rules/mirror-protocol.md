[← Back to Rules](RULES.md)

## Mirror Protocol

**Identifier:** `Mirror Protocol`
**Category:** Architecture
**Severity:** Info
**Principle:** Dependency Inversion (SOLID), guarding against over-application

### Rationale
A "mirror protocol" is one that duplicates a concrete type's entire public interface — typically named `FooServiceProtocol` for a class `FooService`, with every method and property copied verbatim. This pattern, common in Java-style codebases, adds a layer of indirection without enabling meaningful abstraction. In Swift, protocols are most valuable when they describe a focused capability, not when they mirror a type 1:1.

### Discussion
`MirrorProtocolVisitor` uses cross-file analysis to detect this pattern. It collects protocols ending with "Protocol", then checks if a conforming type exists whose name matches (e.g., `FooService` for `FooServiceProtocol`). If the protocol's requirements overlap with at least 80% of the conforming type's members, the rule fires.

The 80% threshold allows for minor differences (a private helper method on the type, for example) while still catching the core anti-pattern: a protocol that is essentially a copy of the type's interface.

Protocols with names that do not end in "Protocol" are not checked. A capability name like `Loadable` or `Configurable` typically indicates a focused capability rather than a type mirror. A role noun like `OrderStore` cannot mirror a type of the same name, because a protocol and a type in one module cannot share a name; its conformers are named for how they fill the role (`CoreDataOrderStore`, `InMemoryOrderStore`).

**Relationship to [Protocol Naming Suffix](protocol-naming-suffix.md).** That rule asks for a `Protocol` suffix on every protocol, and the suffix is how a mirror is usually spelled: `OrderStoreProtocol` frees the name `OrderStore` for the type that copies it. The two rules never report the same protocol (that one fires only on unsuffixed names, this one only on suffixed ones), but following that rule's advice is the first step toward the pairing this one questions. That is why Protocol Naming Suffix is opt-in: it is a team naming convention, while this rule is about design. A team that adopts the convention can still stay clear of this rule by naming implementations for what they are (`actor CoreDataOrderStore: OrderStoreProtocol`) rather than after the protocol's stem.

**Mock-conformer exemption.** If a mock/test double conforms to the protocol — a conformer whose name contains `Mock`, `Fake`, `Stub`, or `Spy`, or one declared in a `Tests`/`Mocks`/`Fakes`/`Stubs` file — the protocol is **not** flagged, even if it mirrors the type 1:1. Such a protocol is a justified dependency-injection seam: it exists so tests can substitute a fake, and removing it would remove that seam. This exemption is shared with [Single Implementation Protocol](single-implementation-protocol.md) via a common `ProtocolExemption` predicate, so the two rules can no longer disagree about the same protocol. Unlike that rule, Mirror Protocol does **not** exempt on the dependency-injection *name suffix* alone — every mirror protocol ends in `Protocol`, so a suffix exemption would silence the rule entirely; only a real mock conformer justifies a 1:1 mirror.

**Dependency-injection exemption.** A mirror protocol held as a stored property or received as an initializer parameter is a deliberate seam, and is not flagged. A dependency typed with a composition consumes each protocol in it, whether written inline (`any FooServiceProtocol & Sendable`) or through a `typealias`.

**Conformances through a `typealias`.** A conformance written through a composition alias (`struct OrderService: AuditedOrderService`, with `typealias AuditedOrderService = OrderServiceProtocol & Auditing`) counts as conforming to each protocol the alias composes, for the match and the mock exemption alike.

### Non-Violating Examples
```swift
// Focused capability protocol — not a mirror
protocol Loadable {
    func load() async throws
}
class DataService: Loadable {
    func load() async throws { }
    func save() { }
    func delete() { }
}

// Protocol defines a subset of capabilities — genuine abstraction
protocol StorageProtocol {
    func read(key: String) -> Data?
    func write(key: String, data: Data)
}
class DiskStorage: StorageProtocol {
    func read(key: String) -> Data? { nil }
    func write(key: String, data: Data) { }
    func clear() { }           // extra method not in protocol
    func migrate() { }         // extra method not in protocol
    func calculateSize() { }   // extra method not in protocol
}
```

### Violating Examples
```swift
// 1:1 mirror — every protocol requirement matches a type method
protocol UserServiceProtocol {
    func fetchUser()
    func saveUser()
    func deleteUser()
}
class UserService: UserServiceProtocol {
    func fetchUser() { }
    func saveUser() { }
    func deleteUser() { }
}
```

---
