[← Back to Rules](RULES.md)

## Fat Protocol

**Identifier:** `Fat Protocol`
**Category:** Architecture
**Severity:** Info

### Rationale
A protocol with 10 or more requirements violates the Interface Segregation Principle. Swift encourages small, composable protocols (like `Equatable`, `Identifiable`, `Hashable`). A fat protocol forces every conformer to implement a large surface area, even when only a subset is needed.

### Discussion
`FatProtocolVisitor` counts all requirement types inside a `ProtocolDeclSyntax`: functions, properties, initializers, subscripts, and associated types. When the total reaches 10, the rule fires.

The threshold of 10 is intentionally generous — most well-designed protocols in the Swift ecosystem have 1–5 requirements. Reaching 10 is a strong signal that the protocol should be decomposed into focused, composable traits.

### Non-Violating Examples
```swift
protocol Loadable {
    func load() async throws
    func cancel()
}

protocol Configurable {
    var configuration: Configuration { get set }
    func apply()
    func reset()
}
```

### Violating Examples
```swift
protocol KitchenSinkProtocol {
    var name: String { get }
    var identifier: Int { get }
    func load()
    func save()
    func delete()
    func update()
    func validate()
    func export()
    init(name: String)
    subscript(index: Int) -> String { get }
    // 10 requirements — consider splitting
}
```

---
