[← Back to Rules](RULES.md)

## Concrete Type Usage

**Identifier:** `Concrete Type Usage`
**Category:** Architecture
**Severity:** Warning

### Rationale
A function parameter or stored property typed as a concrete service class (e.g., `func configure(service: APIService)`) cannot be substituted with a test double or alternative implementation without modifying the function signature. Protocol abstractions allow callers to pass any conforming type.

### Discussion
`ConcreteTypeUsageVisitor` checks type annotations in function parameters and stored properties (without initializers) for names ending in the same service-like suffixes used by `DirectInstantiationVisitor`. It skips types ending in `Protocol`, `Type`, or `Interface` (which are already abstractions), types annotated with a SwiftUI property wrapper, and parameters typed with `some Protocol` (opaque types). Replacing `APIService` with `APIServiceProtocol` — or using `some NetworkProtocol` — resolves the issue.

### Non-Violating Examples
```swift
// Using a protocol-named type
class Owner {
    var service: NetworkServiceProtocol
    init(service: NetworkServiceProtocol) { self.service = service }
}

// Opaque type — no issue
class Owner {
    func foo(service: some NetworkProtocol) { }
}
```

### Violating Examples
```swift
// Concrete type in function parameter
class Setup {
    func configure(service: APIService) { }  // concrete type
}

// Concrete type in stored property
class MyViewModel {
    var repo: UserRepository  // concrete type, no initializer
    init(repo: UserRepository) { self.repo = repo }
}
```

---
