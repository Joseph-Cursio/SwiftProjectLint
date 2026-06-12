[← Back to Rules](RULES.md)

## Preconcurrency Import

**Identifier:** `Preconcurrency Import`
**Category:** Code Quality
**Severity:** Info

### Rationale
`@preconcurrency import SomeModule` softens — and in many cases silences — concurrency diagnostics for *every* type vended by that module: `Sendable` checking is relaxed and isolation mismatches are downgraded. It is a legitimate, even recommended, way to consume a library that predates Swift Concurrency. But it is also a *blanket* escape hatch: once applied, a genuine concurrency problem involving that module's types compiles silently. Surfacing each one keeps the suppression visible so it can be reviewed — and removed once the dependency annotates its own concurrency.

### Discussion
`PreconcurrencyImportVisitor` checks every `import` declaration for a `@preconcurrency` attribute and reports it. The reported message names the module so the suppression is easy to locate and justify.

This is the import-level counterpart to [Preconcurrency Conformance](preconcurrency-conformance.md), which deliberately covers only `@preconcurrency` on *conformances* of your own types and explicitly skips imports. Between the two rules, both valid placements of `@preconcurrency` are now visible.

The severity is **Info**: unlike `nonisolated(unsafe)` or `@unchecked Sendable`, a `@preconcurrency` import is frequently the correct tool while waiting on an upstream dependency, so this is an audit signal rather than a defect.

### Non-Violating Examples
```swift
import Foundation
import SwiftUI

// @testable is unrelated to concurrency and is not flagged.
@testable import MyApp
```

### Violating Examples
```swift
@preconcurrency import LegacyKit

@preconcurrency public import LegacyKit.SubModule
```

### See Also
- [Preconcurrency Conformance](preconcurrency-conformance.md) — `@preconcurrency` on conformances.
- [Unchecked Sendable](unchecked-sendable.md) and [Nonisolated Unsafe](nonisolated-unsafe.md) — the other concurrency escape hatches.
