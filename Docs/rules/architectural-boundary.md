[← Back to Rules](RULES.md)

## Architectural Boundary

**Identifier:** `Architectural Boundary`
**Category:** Architecture
**Severity:** Warning
**Status:** Implemented
**Principle:** Dependency Inversion (SOLID)

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

Each layer entry maps a set of path prefixes to its forbidden imports and types. Files that don't match any declared layer are silently ignored. When a file matches more than one layer, for example `Features/` in one and `Features/Payments/` in another, the layer with the longer matching path applies. If a layer path matches no analysed file, the CLI warns on stderr, because a misspelled path would otherwise leave the layer unchecked without a word.

#### Allowlisting imports

`forbidden_imports` catches only the frameworks someone thought to forbid; any other framework, including one added next month, is allowed by default. To reverse that, give a layer `allowed_imports`. Any import not on that list is then reported:

```yaml
architectural_layers:
  domain:
    paths: ["Domain/"]
    allowed_imports: ["Foundation"]
```

```swift
// Domain/OrderService.swift
import Foundation
import Alamofire   // ← violation: 'Alamofire' is not an allowed import in the 'domain' layer
```

- A submodule is allowed when its top-level module is, so `allowed_imports: ["UIKit"]` also permits `import UIKit.UIGestureRecognizerSubclass`.
- `import Swift` is always allowed, since every file imports the standard library implicitly.
- `allowed_imports: []` allows no framework at all. Omitting the key sets no allowlist.
- A module that is both forbidden and missing from the allowlist is reported once, as forbidden.

To control which *layers* a layer may use, as opposed to which frameworks, add `may_depend_on` and see [Layer Dependency](layer-dependency.md).

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
