[← Back to Rules](RULES.md)

## Mirror Protocol

**Identifier:** `Mirror Protocol`
**Category:** Architecture
**Severity:** Info

### Rationale
A "mirror protocol" is one that duplicates a concrete type's entire public interface — typically named `FooServiceProtocol` for a class `FooService`, with every method and property copied verbatim. This pattern, common in Java-style codebases, adds a layer of indirection without enabling meaningful abstraction. In Swift, protocols are most valuable when they describe a focused capability, not when they mirror a type 1:1.

### Discussion
`MirrorProtocolVisitor` uses cross-file analysis to detect this pattern. It collects protocols ending with "Protocol", then checks if a conforming type exists whose name matches (e.g., `FooService` for `FooServiceProtocol`). If the protocol's requirements overlap with at least 80% of the conforming type's members, the rule fires.

The 80% threshold allows for minor differences (a private helper method on the type, for example) while still catching the core anti-pattern: a protocol that is essentially a copy of the type's interface.

Protocols with names that do not end in "Protocol" are not checked — naming conventions like `Loadable` or `Configurable` typically indicate a focused capability rather than a type mirror.

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
