[← Back to Rules](RULES.md)

## Architectural Boundary

**Identifier:** `Architectural Boundary`
**Category:** Architecture
**Severity:** Warning
**Status:** Not yet implemented — see [design notes](../architectural-boundary-rule-design.md)

> **Single-target projects only.** If your project is split into separate SPM targets or modules, skip this rule — the Swift compiler already enforces layer boundaries at build time, and no linter can improve on that. Tools like [Periphery](https://github.com/peripheryapp/periphery), [swift-dependencies](https://github.com/pointfreeco/swift-dependencies), and Tuist's project validation are better suited to modular architectures.

### Rationale

In a single-target app, nothing prevents a domain model from importing `CoreData` or a view model from calling `URLSession.shared` directly. There is no build system boundary — only folder conventions. This rule makes those conventions machine-checkable.

### Detection Modes

**Import-based** — flags `import` statements for frameworks that don't belong in a given layer:

```swift
// Domain/UserRepository.swift
import CoreData   // ← persistence framework in domain layer
```

**Type-based** — flags specific type references that slip through via broadly-imported frameworks (e.g. `Foundation`):

```swift
// Domain/OrderService.swift
let session = URLSession.shared   // ← networking type in domain layer
```

### Configuration

This rule requires an `architectural_layers` block in `.swiftprojectlint.yml`. It produces no output if the block is absent.

```yaml
architectural_layers:
  domain:
    paths: ["Domain/", "UseCases/", "BusinessLogic/"]
    forbidden_imports: ["CoreData", "SwiftData", "UIKit", "SwiftUI", "Alamofire"]
    forbidden_types:   ["URLSession", "UserDefaults", "NSManagedObject"]
  presentation:
    paths: ["ViewModels/", "Presentation/"]
    forbidden_imports: ["CoreData", "Alamofire"]
    forbidden_types:   ["URLSession", "NSManagedObject"]
```

Each layer entry maps a set of path prefixes to its forbidden imports and types. Files that don't match any declared layer are silently ignored.

### Non-Violating Examples

```swift
// Domain/UserRepository.swift — no persistence or UI imports
import Foundation

protocol UserRepository {
    func fetchUser(id: String) async throws -> User
}
```

```swift
// Infrastructure/CoreDataUserRepository.swift — persistence lives here
import CoreData

final class CoreDataUserRepository: UserRepository { ... }
```

### Violating Examples

```swift
// Domain/UserRepository.swift
import CoreData   // ← violation: persistence framework in domain layer

class UserRepository {
    let context: NSManagedObjectContext   // ← violation: persistence type in domain layer
}
```

```swift
// Domain/OrderService.swift
import Foundation

class OrderService {
    func placeOrder() {
        let session = URLSession.shared   // ← violation: networking type in domain layer
    }
}
```

---
