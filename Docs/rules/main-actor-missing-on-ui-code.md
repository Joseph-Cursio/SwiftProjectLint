[← Back to Rules](RULES.md)

## Main Actor Missing On UI Code

**Identifier:** `Main Actor Missing On UI Code`
**Category:** State Management
**Severity:** Warning

### Rationale
In Swift 6 strict concurrency, `@Published` property mutations drive SwiftUI view updates — which are inherently main-thread operations. An `ObservableObject` class that omits `@MainActor` compiles cleanly under concurrency checking but allows its `@Published` properties to be mutated from any actor or thread. When a background task mutates a `@Published` property on an un-isolated `ObservableObject`, the resulting `objectWillChange` notification fires off the main thread, creating a data race with the SwiftUI render cycle.

Annotating an `ObservableObject` class `@MainActor` makes this constraint explicit and compiler-enforced: all property mutations, method calls, and view-update emissions are guaranteed to run on the main actor, eliminating the race without requiring manual `DispatchQueue.main.async` calls.

### Discussion
`MainActorMissingVisitor` implements `CrossFilePatternVisitorProtocol` and performs a two-pass analysis:

- **Pass 1 (walk):** Every `ClassDeclSyntax` across all project files is inspected. Class names explicitly annotated `@MainActor` are collected into a suppression set. `ObservableObject` classes with at least one `@Published` property that lack `@MainActor` are queued as candidates.
- **Pass 2 (`finalizeAnalysis`):** Each candidate is checked against the suppression set. If the candidate's direct superclass is a known `@MainActor` class (from any file in the project), the issue is suppressed — the subclass inherits main-actor isolation automatically.

Only `class` declarations are inspected; structs and enums cannot meaningfully conform to `ObservableObject` as a base type and are ignored. Types using the `@Observable` macro (Swift 5.9+) are not `ObservableObject` conformers and are never flagged.

### Known Limitation
Suppression covers **one level of inheritance** only. Multi-level chains (grandparent `@MainActor` → parent (no annotation) → child) are not traversed. Superclasses from external SPM packages or frameworks (not in the file cache) cannot be suppressed. Teams using `swiftSettings: [.defaultIsolation(MainActor.self)]` in `Package.swift` should disable this rule for that target, as target-level isolation is not visible in Swift source AST.

### Non-Violating Examples
```swift
// Correctly annotated — all @Published mutations are main-actor-isolated
@MainActor
class CounterViewModel: ObservableObject {
    @Published var count = 0

    func increment() {
        count += 1  // Safe: already on main actor
    }
}

// No @Published properties — no threading contract to enforce
class DataService: ObservableObject {
    var items: [String] = []
}

// Inherits @MainActor from base class — suppressed (cross-file safe)
@MainActor
class BaseViewModel: ObservableObject {}

class DerivedViewModel: BaseViewModel {
    @Published var count = 0  // @MainActor inherited
}

// @Observable macro — not ObservableObject, not flagged
@Observable
class CounterModel {
    var count = 0
}
```

### Violating Examples
```swift
// FLAGGED: ObservableObject with @Published but no @MainActor
class CounterViewModel: ObservableObject {
    @Published var count = 0
    // Mutation from a Task or background queue is a silent data race
}

// FLAGGED: Multiple @Published properties, all unprotected
class SettingsViewModel: ObservableObject {
    @Published var isDarkMode = false
    @Published var fontSize: Int = 14
    @Published var username = ""
}

// FLAGGED: Nested conformance, still needs annotation
class NetworkViewModel: ObservableObject {
    @Published var isLoading = false

    func fetchData() async {
        isLoading = true   // ⚠️ Can be called from any actor
        // ...
        isLoading = false
    }
}
```

---
