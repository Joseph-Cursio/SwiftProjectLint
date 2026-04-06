[← Back to Rules](RULES.md)

## Protocol Naming Suffix

**Identifier:** `Protocol Naming Suffix`
**Category:** Code Quality
**Severity:** Info

### Rationale
Naming protocols with a `Protocol` suffix makes a type's role immediately visible at every usage site. When a parameter is typed as `NetworkService`, a reader cannot tell whether it is a class or a protocol. When it is typed as `NetworkServiceProtocol`, the abstraction is self-evident.

### Discussion
`NamingConventionVisitor` checks `protocol` declarations without a `Protocol` suffix. To reduce false positives, the following are exempt:

- **Capability-describing suffixes** — names ending in `-able`, `-ible`, `-ing`, `-ive` (e.g., `Equatable`, `Collecting`, `Correctable`) already convey "this is a contract"
- **Domain-role suffixes** — `Rule`, `Configuration`, `Provider`, `Validator`, `Reporter`, `Visitor`, `Handler`, `Delegate`, `DataSource`, `Factory`, `Builder`, `Context`, `Comparable`, `Convertible`
- **Public protocols** — library API protocols follow community conventions
- **Test/example files** — exempt from naming rules

Xiangyu Sun's article [*How Well Can You Detect a Swift Protocol Without the Compiler?*](https://medium.com/ios-ic-weekly/how-well-can-you-detect-a-swift-protocol-without-the-compiler-537fac929bd7) (featured in [Fatbobman's Swift Weekly #127](https://weekly.fatbobman.com/p/fatbobmans-swift-weekly-127)) demonstrates through empirical analysis that the `Protocol` suffix is one of the most reliable signals for static tools and LLMs to identify a protocol without compiler access. Without it, heuristics based on SwiftSyntax AST parsing, regex, or even SourceKit are all substantially less accurate.

### Non-Violating Examples
```swift
protocol NetworkServiceProtocol {
    func fetch() async throws -> Data
}

protocol RequestableProtocol {
    func perform() async throws
}
```

### Violating Examples
```swift
protocol Requestable { func perform() async throws }  // missing "Protocol" suffix

protocol DataStore { func save() }  // missing "Protocol" suffix
```

---
