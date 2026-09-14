[← Back to Rules](RULES.md)

## Undeclared Target Dependency

**Identifier:** `Undeclared Target Dependency`
**Category:** Architecture
**Severity:** Warning

### Rationale

SwiftPM does not compare a target's imports with its `dependencies:`. A module can be imported whenever it has already been built by the time the importing target compiles, and a sibling target that some *other* dependency pulls into the build has been.

So this compiles:

```swift
// Package.swift
.target(name: "Domain", dependencies: ["Persistence"]),
.target(name: "Persistence"),
.target(name: "Checkout", dependencies: ["Domain"]),
```

```swift
// Sources/Checkout/CheckoutViewModel.swift
import Persistence   // never declared by Checkout
```

It keeps compiling until `Domain` stops depending on `Persistence`, and then `Checkout` fails to build even though nobody changed it. With parallel builds it can also fail intermittently, whenever `Checkout` happens to be scheduled before `Persistence` is built. The import is also an architectural decision the manifest never records: reading `Package.swift`, `Checkout` appears to know nothing about storage.

### Discussion

`UndeclaredTargetDependencyVisitor` is a cross-file rule. It reads each `Package.swift` in the analysed files from its syntax tree, maps every source file to the target that compiles it, and compares that target's imports with its declared dependencies.

- **Targets are matched by module name**, so a target named `tool-core` is matched by `import tool_core`.
- **Files are mapped the way SwiftPM maps them**: the `path:` argument when there is one, otherwise `Sources/<name>` (or `Source`, `src`, `srcs`) and `Tests/<name>` for test targets. `sources:` and `exclude:` are honoured, and a file inside a nested package belongs to that package, not to an enclosing one.
- **Each missing dependency is reported once per target**, at the first import in path order, with a count of the other files that import it. The fix is a single line in `Package.swift`, however many files import the module.

### Local packages

Modules from `.package(path:)` dependencies are checked too, when their manifests are part of the run. That happens when the local package sits inside the analysed directory and `include_nested_packages: true` is set. The rule follows each path to its manifest and resolves every `.product(name:package:)` to the targets that product vends. It also follows path dependencies transitively, so a module that is reachable only through another local package is still judged.

For these findings, the suggestion names the dependency to add, for example `.product(name: "KitCore", package: "kit")`. It also says when the package itself is missing from `dependencies:`, or when no library product vends the module at all.

The rule does not report:

- **Modules from packages outside the run.** `import Foundation`, a remote package such as `import ArgumentParser`, or a path package outside the analysed directory are never findings, because their manifests cannot be read.
- **Re-exported modules.** If a declared dependency contains `@_exported import Models`, then `Models` is part of that dependency's interface and importing it is permitted. Re-exports are followed transitively, across package boundaries.
- **Modules of a product the rule cannot match.** If a target declares a product of a local package but that package's product list is computed, or names no such product, then everything the package vends, and everything it re-exports, is left unjudged. That declaration could be what makes the import legitimate.
- **Imports guarded by `#if canImport(Module)`**, which are written to compile without the module.
- **Plugin targets**, which cannot import the package's targets.

### Limitations

A manifest is a program, and only what it states literally can be read. When a target's name, `path:`, `sources:` or `exclude:` is computed, or when a bare `.target(name:)` call appears where it could be either a target or a dependency, the whole manifest is skipped. One unread target could own files that would otherwise be attributed to a neighbour, and every finding about them would be wrong. A target whose `dependencies:` list alone is computed, for example `shared + ["Networking"]`, is skipped on its own.

A package with a version-specific manifest such as `Package@swift-5.9.swift` is skipped, because some toolchains read that file instead of `Package.swift`.

Nested packages are analysed only when they are part of the run (`include_nested_packages: true`). Otherwise their files and their manifests are not in scope, and neither are the modules they vend. A path dependency with a computed path, an absolute path, or a path outside the analysed directory is not followed.

### Non-Violating Examples

```swift
// Package.swift
.target(name: "Domain"),
.target(name: "Persistence", dependencies: ["Domain"]),
.target(name: "Checkout", dependencies: ["Domain", "Persistence"]),
```

```swift
// Sources/Checkout/CheckoutViewModel.swift
import Domain
import Persistence   // declared
import Foundation    // not a target of this package
```

```swift
// Re-exported by a declared dependency
// Sources/Domain/Exports.swift
@_exported import Models

// Sources/Checkout/Checkout.swift — Checkout declares Domain
import Models
```

### Violating Examples

```swift
// Package.swift
.target(name: "Domain"),
.target(name: "Persistence", dependencies: ["Domain"]),
.target(name: "Checkout", dependencies: ["Domain"]),
.testTarget(name: "CheckoutTests", dependencies: ["Checkout"]),
```

```swift
// Sources/Checkout/CheckoutViewModel.swift
import Persistence   // Checkout does not declare Persistence

// Tests/CheckoutTests/CheckoutTests.swift
@testable import Checkout
@testable import Domain   // CheckoutTests does not declare Domain
```

---
