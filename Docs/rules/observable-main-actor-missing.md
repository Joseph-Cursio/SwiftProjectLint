[← Back to Rules](RULES.md)

## Observable Main Actor Missing

**Identifier:** `Observable Main Actor Missing`
**Category:** State Management
**Severity:** Warning

### Rationale

The `@Observable` macro (Swift 5.9 / iOS 17+) synthesises observation infrastructure for every stored property in the class. Those properties drive SwiftUI view updates, which are inherently main-thread operations. Without `@MainActor`, nothing prevents background `Task`s or off-thread code from mutating observed state, producing data races and undefined rendering behaviour under Swift 6 strict concurrency.

As Paul Hudson puts it: *"If an `@Observable` class is not `@MainActor`, fix it before continuing, then take a quiet moment to reflect."*

Annotating an `@Observable` class `@MainActor` makes the threading contract explicit and compiler-enforced: all property mutations and view-update notifications are guaranteed to run on the main actor, eliminating races without requiring manual `DispatchQueue.main.async` calls.

### Discussion

`ObservableMainActorMissingVisitor` implements `CrossFilePatternVisitorProtocol` and performs a two-pass analysis:

- **Pass 1 (walk):** Every `ClassDeclSyntax` across all project files is inspected. Class names explicitly annotated `@MainActor` are collected into a suppression set. `@Observable` classes that lack `@MainActor` are queued as candidates.
- **Pass 2 (`finalizeAnalysis`):** Each candidate is checked against the suppression set. If the candidate's direct superclass is a known `@MainActor` class (from any file in the project), the issue is suppressed — the subclass inherits main-actor isolation automatically.

Only `class` declarations are inspected; structs annotated `@Observable` cannot be subclassed and actor isolation is less relevant.

### Known Limitation

Suppression covers **one level of inheritance** only. Multi-level chains (grandparent `@MainActor` → parent (no annotation) → child) are not traversed. Superclasses from external SPM packages or frameworks (not in the file cache) cannot be suppressed. Teams using `swiftSettings: [.defaultIsolation(MainActor.self)]` in `Package.swift` should disable this rule for that target, as target-level isolation is not visible in Swift source AST.

### Relationship to `main-actor-missing-on-ui-code`

This rule complements [`main-actor-missing-on-ui-code`](main-actor-missing-on-ui-code.md), which covers the older `ObservableObject` + `@Published` pattern. The two rules are independent: migrating to `@Observable` replaces the need for `main-actor-missing-on-ui-code` but introduces this rule instead.

### Non-Violating Examples

```swift
// Correctly annotated — all property mutations are main-actor-isolated
@MainActor
@Observable
class CounterModel {
    var count = 0

    func increment() {
        count += 1  // Safe: already on main actor
    }
}

// Attribute order does not matter
@Observable
@MainActor
class ProfileModel {
    var name = ""
}

// Inherits @MainActor from base class — suppressed (cross-file safe)
@MainActor
@Observable
class BaseModel {}

@Observable
class DerivedModel: BaseModel {
    var count = 0  // @MainActor inherited
}

// Plain class — not @Observable, not flagged
class DataService {
    var items: [String] = []
}
```

### Violating Examples

```swift
// FLAGGED: @Observable but no @MainActor
@Observable
class CounterModel {
    var count = 0
    // Any Task can mutate count off the main thread — silent data race
}

// FLAGGED: multiple observed properties, all unprotected
@Observable
class SettingsModel {
    var isDarkMode = false
    var fontSize: Int = 14
    var username = ""
}

// FLAGGED: async method can trigger off-thread mutation
@Observable
class FeedModel {
    var posts: [Post] = []

    func refresh() async {
        posts = await fetchPosts()  // ⚠️ Called from any actor
    }
}
```

### Fix

Add `@MainActor` to the class declaration:

```swift
// Before
@Observable
class CounterModel {
    var count = 0
}

// After
@MainActor
@Observable
class CounterModel {
    var count = 0
}
```

---
