[<- Back to Rules](RULES.md)

## View Model Direct DB Access

**Identifier:** `View Model Direct DB Access`
**Category:** Architecture
**Severity:** Info *(opt-in)*

### Rationale
View models that directly import and use persistence frameworks (`CoreData`, `SwiftData`, `GRDB`, `RealmSwift`, `SQLite`) violate the separation of concerns principle. Direct database access in view models makes them hard to test, hard to migrate, and couples business logic to storage implementation.

### Discussion
`ViewModelDirectDBAccessVisitor` checks if a file both imports a persistence framework and contains a view model class (identified by `ObservableObject` conformance, `@Observable` attribute, or name ending in `ViewModel`/`VM`). Files with repository/service-like names or class names are suppressed.

This rule is opt-in because many small apps intentionally use `@Query` directly in view models per Apple's SwiftData tutorials.

### Non-Violating Examples
```swift
// Uses repository abstraction
class TaskListViewModel: ObservableObject {
    private let repository: TaskRepositoryProtocol

    func addTask(title: String) async throws {
        try await repository.create(title: title)
    }
}

// Repository class — not a view model
import SwiftData

class TaskRepository {
    var modelContext: ModelContext
    func create(title: String) { /* ... */ }
}
```

### Violating Examples
```swift
// View model directly imports SwiftData
import SwiftData

@Observable
class TaskListViewModel {
    var modelContext: ModelContext

    func addTask(title: String) {
        let task = TaskItem(title: title)
        modelContext.insert(task)
    }
}
```

---
