[← Back to Rules](RULES.md)

## Singleton Usage

**Identifier:** `Singleton Usage`
**Category:** Architecture
**Severity:** Warning

### Rationale
Accessing a service through a `.shared` singleton creates a global dependency that is invisible in function signatures and impossible to replace in tests. Code that calls `DataManager.shared.fetch()` is permanently coupled to the `DataManager` implementation and cannot be tested without running the real implementation.

### Discussion
`SingletonUsageVisitor` flags member accesses where the member name is `shared` and the base is a type-name reference (a `DeclReferenceExprSyntax` with an uppercase first character) ending in a service-like suffix (`Manager`, `Service`, `Store`, `Provider`, `Client`, `Repository`, `Handler`, `Controller`, `Factory`, `Adapter`, `ViewModel`, `Coordinator`, `Generator`). Standard system singletons such as `URLSession.shared`, `UserDefaults.standard`, or `NotificationCenter.default` are not flagged because their base names (`URLSession`, `UserDefaults`, `NotificationCenter`) do not match the service suffixes.

### Non-Violating Examples
```swift
// System singleton — not flagged
class Connector {
    func send() {
        URLSession.shared.dataTask(with: url!)
    }
}

// Injected service — no singleton
class Coordinator {
    private let dataManager: DataManagerProtocol
    init(dataManager: DataManagerProtocol) {
        self.dataManager = dataManager
    }
}
```

### Violating Examples
```swift
class Coordinator {
    func run() {
        DataManager.shared.fetch()  // singleton access — hard coupling
    }
}

class Setup {
    func configure() {
        DataManager.shared.setup()
        AnalyticsService.shared.initialize()  // multiple singletons
    }
}
```

---
