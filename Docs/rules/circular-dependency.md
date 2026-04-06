[<- Back to Rules](RULES.md)

## Circular Dependency

**Identifier:** `Circular Dependency`
**Category:** Architecture
**Severity:** Warning

### Rationale
When type A holds a reference to type B and type B holds a reference to type A, you have a circular dependency. This creates tight coupling, makes both types impossible to test in isolation, and often indicates a missing abstraction. It can also cause retain cycles if both references are strong.

### Discussion
`CircularDependencyVisitor` is a cross-file analysis rule. In phase 1, it collects type declarations and their stored property type references across all files. In phase 2 (`finalizeAnalysis`), it builds a directed graph and detects length-2 cycles (A→B→A).

The rule suppresses findings when:
- One side of the reference is `weak` (intentional parent-child pattern)
- One side references the other through a protocol (the dependency is inverted)

### Non-Violating Examples
```swift
// Dependency inversion via protocol
class UserManager {
    var sessionProvider: SessionProviding  // Protocol, not concrete type
}

class SessionManager: SessionProviding {
    var userManager: UserManager
}

// Weak reference (delegate pattern)
class Parent {
    var child: Child
}

class Child {
    weak var parent: Parent?
}
```

### Violating Examples
```swift
// Circular dependency — tight coupling
// File: UserManager.swift
class UserManager {
    var sessionManager: SessionManager
}

// File: SessionManager.swift
class SessionManager {
    var userManager: UserManager
}
```

---
