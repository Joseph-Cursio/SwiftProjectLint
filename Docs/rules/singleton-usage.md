[← Back to Rules](RULES.md)

## Singleton Usage

**Identifier:** `Singleton Usage`
**Category:** Architecture
**Severity:** Warning

### Rationale
Accessing a service through a `.shared` singleton creates a global dependency that is invisible in function signatures and impossible to replace in tests. Code that calls `DataManager.shared.fetch()` is permanently coupled to the `DataManager` implementation and cannot be tested without running the real implementation.

### Discussion
`SingletonUsageVisitor` flags member accesses where the member name is `shared` and the base is a type-name reference (a `DeclReferenceExprSyntax` with an uppercase first character) ending in a service-like suffix (`Manager`, `Service`, `Store`, `Provider`, `Client`, `Repository`, `Handler`, `Controller`, `Factory`, `Adapter`, `ViewModel`, `Coordinator`, `Generator`). Standard system singletons such as `URLSession.shared`, `UserDefaults.standard`, or `NotificationCenter.default` are not flagged because their base names (`URLSession`, `UserDefaults`, `NotificationCenter`) do not match the service suffixes.

**Test and fixture files are exempt.** A unit test that calls the real `ProjectParser.shared` is exercising production code, not introducing coupling to refactor — the access *is* the test. The visitor skips files detected as test/fixture by `isTestOrFixtureFile()` (SPM `Tests/` and Xcode `…Tests/` target folders, `…Tests.swift` files, and fixture directories), matching the test-file handling already applied by other architecture rules (`Single Implementation Protocol`, `Unabstracted File IO`). This keeps the signal on the production call sites — e.g. an `AppState`/`…Model` that reaches for `Service.shared` — where injecting the dependency actually pays off.

**`.shared` as a parameter default value is exempt.** `init(parser: ProjectParsing = ProjectParser.shared)` is exactly the dependency-injection seam this rule's own suggestion recommends: the dependency is visible in the signature and replaceable by callers and tests, so it is not the hidden global coupling the rule targets. The visitor walks up from the `.shared` access and exempts it when it sits directly in a `FunctionParameterSyntax` default value — but **not** when it is a call inside a default *closure* body (`init(work: () -> Void = { Service.shared.run() })`), which is still hidden coupling. The walk stops at a closure or code block, so only the plain default-value position is exempt.

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

// `.shared` as a parameter default — the DI seam, not flagged
final class AppState {
    private let parser: ProjectParsing
    init(parser: ProjectParsing = ProjectParser.shared) {
        self.parser = parser
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
