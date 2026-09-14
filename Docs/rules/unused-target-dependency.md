[← Back to Rules](RULES.md)

## Unused Target Dependency

**Identifier:** `Unused Target Dependency`
**Category:** Architecture
**Severity:** Info

### Rationale

The mirror of [Undeclared Target Dependency](undeclared-target-dependency.md). A sibling target listed in `dependencies:` that no file imports does not break the build, but it still costs something. The target is rebuilt whenever the dependency changes, and the manifest keeps claiming a coupling the source no longer has. That is the record a reader consults to learn how the package is layered, so a stale entry there hides the architecture instead of documenting it.

These entries accumulate quietly. A refactor removes the last `import Persistence` from `Checkout`, the build stays green, and nothing prompts anyone to update `Package.swift`.

### Discussion

`UnusedTargetDependencyVisitor` is a cross-file rule that shares its manifest reading with Undeclared Target Dependency. For each target, it collects what the target's files import. A declared dependency on a sibling target counts as used when the target:

- imports it, including `@testable import` and imports under `#if`;
- imports a module that re-exports it through `@_exported import`, followed transitively; or
- names it in `#externalMacro(module: "…")`, which is how a library uses the macro target it depends on.

The finding is reported on the dependency's line in `Package.swift`.

### Local packages

A declared product of a `.package(path:)` dependency is judged the same way when that package's manifest is part of the run, meaning the package is inside the analysed directory and `include_nested_packages: true` is set. The product counts as used if the target imports any of the modules it vends, directly or through a re-export.

### Limitations

Calling a dependency unused is a claim about every file of the declaring target and about the dependency's module name, so the rule declines whenever either is in doubt:

- **The declaring target has no Swift files in the run**, for example because its directory is in `excluded_paths`. If you exclude only *part* of a target, a dependency used only in the excluded files will be reported.
- **The dependency has no Swift files in the run.** A C target's module name comes from its module map rather than its target name, so `import zlib` can be how `CZlib` is used.
- **The dependency is an executable, plugin, system library or binary target.** A test target often depends on an executable only so that it gets built, and the other three are not imported by their target name.
- **The dependency is a product the rule cannot see into**: a product of a remote package, of a path package outside the run, or of a local package whose product list is computed or has no product of that name.
- **A local product includes a target with no Swift files in the run**, for the same module-map reason as a C sibling target.
- **The manifest or the target's dependency list cannot be read literally.** See [Undeclared Target Dependency](undeclared-target-dependency.md#limitations).

### Non-Violating Examples

```swift
// Package.swift
.target(name: "Domain"),
.target(name: "Checkout", dependencies: ["Domain"]),
.executableTarget(name: "tool"),
.testTarget(name: "ToolTests", dependencies: ["tool"]),   // executables are not judged
```

```swift
// Sources/Checkout/Checkout.swift
import Domain

// Tests/ToolTests/ToolTests.swift — runs the built binary, never imports it
import Foundation
```

```swift
// A macro target used through #externalMacro
// Package.swift
.macro(name: "MacrosImpl", dependencies: [/* swift-syntax products */]),
.target(name: "Macros", dependencies: ["MacrosImpl"]),

// Sources/Macros/Macros.swift
@freestanding(expression)
public macro stringify<T>(_ value: T) -> (T, String) =
    #externalMacro(module: "MacrosImpl", type: "StringifyMacro")
```

### Violating Examples

```swift
// Package.swift
.target(name: "Domain"),
.target(name: "Persistence"),
.target(
    name: "Checkout",
    dependencies: [
        "Domain",
        "Persistence"   // ← no file in Checkout imports Persistence
    ]
),
```

```swift
// Sources/Checkout/Checkout.swift
import Domain
```

---
