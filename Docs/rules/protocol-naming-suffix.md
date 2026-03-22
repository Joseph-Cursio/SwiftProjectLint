[← Back to Rules](RULES.md)

## Protocol Naming Suffix

**Identifier:** `Protocol Naming Suffix`
**Category:** Code Quality
**Severity:** Info

### Rationale
Naming protocols with a `Protocol` suffix makes a type's role immediately visible at every usage site. When a parameter is typed as `NetworkService`, a reader cannot tell whether it is a class or a protocol. When it is typed as `NetworkServiceProtocol`, the abstraction is self-evident.

### Discussion
`NamingConventionVisitor` checks every `protocol` declaration. If the protocol's name does not end with `Protocol`, an issue is reported with a suggestion to rename it. The Swift standard library names protocols descriptively (e.g., `Equatable`, `Hashable`), but within an application codebase — especially one using dependency injection — the explicit suffix aids comprehension and LLM-based tooling.

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
