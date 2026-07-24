# Architectural Boundary Rule — Design Notes

> Status: Implemented (Option B — config-driven).
>
> **Scope:** This rule is designed exclusively for **single-target monolith apps**. If your project uses separate SPM targets or modules, the compiler already enforces architectural boundaries at build time — this rule adds nothing. See the "Why It's Valuable for Monoliths" section for details.

---

## The Idea

Two related suggestions came up in the same conversation:

1. **Enforce architectural boundaries** — flag files that import frameworks they shouldn't (e.g. `Domain/` importing `CoreData`)
2. **Forbidden type usage across layers** — flag specific types used outside their designated layer (e.g. `URLSession` used in a `Domain/` file)

These are the same concept viewed from two angles and belong in one rule with two detection modes.

---

## Why It's Valuable for Monoliths

Multi-target Swift projects get architectural enforcement for free — if `Domain` is its own SPM target and `Infrastructure` imports it (not the reverse), the compiler rejects violations at build time. No linter needed.

**Single-target apps have no such guard.** Layer separation exists only as a folder convention. Nothing stops a domain model from reaching into CoreData or a view model from calling `URLSession.shared` directly. This is the common case for indie apps and smaller teams — and exactly where a lint rule adds value.

For multi-target or modular projects, this is better handled at the build graph level. That's closer to [SwiftGen](https://github.com/SwiftGen/SwiftGen), [Periphery](https://github.com/peripheryapp/periphery), or the purpose-built [swift-dependencies](https://github.com/pointfreeco/swift-dependencies) territory. The iOS/macOS ecosystem already has tools here: ArchUnit (Java), Dependency Cruiser (JS), and for Swift — Tuist's project validation handles this at the build graph level, which is the right place for it.

---

## The Two Detection Signals

### Import-based (coarser, framework-level)

Checks `ImportDeclSyntax` against a forbidden framework list per layer.

```swift
// Domain/UserRepository.swift
import CoreData   // ← should flag: persistence framework in domain layer
```

**Good for:** `CoreData`, `SwiftData`, `UIKit`, `SwiftUI`, `Alamofire`, `GRDB` — frameworks you'd never legitimately import in a domain layer.

**Limitation:** Can't ban `Foundation` — it's imported everywhere. So `URLSession` (which lives in Foundation) slips through.

### Type-based (finer, symbol-level)

Checks `IdentifierTypeSyntax` and `DeclReferenceExprSyntax` against a forbidden symbol list per layer.

```swift
// Domain/OrderService.swift
let session = URLSession.shared   // ← should flag: networking type in domain layer
```

**Good for:** Specific types within broadly-imported frameworks — `URLSession`, `UserDefaults`, `NSManagedObject`, `NSFetchRequest`.

**Catches what import-checking misses.**

### Together: one config block, two checks

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

---

## Config System — Current State

The existing config schema (`.swiftprojectlint.yml`) supports:

```yaml
disabled_rules: [...]
enabled_only: [...]
excluded_paths: [...]
rules:
  "Rule Name":
    severity: warning
    excluded_paths: [...]
```

Per-rule config is limited to `severity` and `excluded_paths`. `LintConfigurationLoader` does not read arbitrary structured keys. An `architectural_layers:` block in the YAML would be silently ignored today.

**Key files:**
- `Packages/SwiftProjectLintConfig/Sources/SwiftProjectLintConfig/Configuration/LintConfiguration.swift`
- `Packages/SwiftProjectLintConfig/Sources/SwiftProjectLintConfig/Configuration/LintConfigurationLoader.swift`

---

## Implementation Options

### Option A — Convention-based (no config changes)

Hardcode common layer folder names and a fixed forbidden import/type list. Zero schema work. Ships in one session.

```swift
// Hardcoded in the visitor
private static let domainFolders = ["Domain", "UseCases", "BusinessLogic"]
private static let domainForbiddenImports: Set<String> = [
    "CoreData", "SwiftData", "UIKit", "SwiftUI", "AppKit", "Alamofire"
]
private static let domainForbiddenTypes: Set<String> = [
    "URLSession", "UserDefaults", "NSManagedObject"
]
```

**Pros:** Fast to ship, no pre-work, covers common projects out of the box.  
**Cons:** Inflexible — projects with non-standard folder names get nothing or noise. Can't add custom forbidden types. Hardcoded policy in source code.

### Option B — Config-driven (correct architecture)

Extend the config system to support arbitrary structured rule config, then build the rule on top.

**Pre-work required (before touching the visitor):**

1. Add a `LayerPolicy` struct to `SwiftProjectLintModels`:
   ```swift
   public struct LayerPolicy: Sendable {
       public let name: String
       public let paths: [String]
       public let forbiddenImports: Set<String>
       public let forbiddenTypes: Set<String>
   }
   ```

2. Add `architecturalLayers: [LayerPolicy]` to `LintConfiguration`.

3. Add a `parse` branch in `LintConfigurationLoader` for the `architectural_layers` YAML key.

4. Thread `LintConfiguration` (or just the `[LayerPolicy]`) through to the visitor at analysis time — the visitor needs the policy to know what to check.

**Then the rule itself** is straightforward: check the current file path against each layer's `paths`, then check imports and type references against the forbidden lists.

**Pros:** Fully configurable per-project, extensible to future layer rules, clean architecture.  
**Cons:** Two sessions of work — config layer first, then rule. More code surface.

---

## Recommendation

**Option B.** The config system is already clean and worth preserving. Hardcoding layer policy in source code creates a rule that only works for projects that happen to follow your naming conventions, and will need constant updating as edge cases emerge.

The pre-work is real but contained: one new struct, one new field on `LintConfiguration`, one new parse branch in the loader, and threading the config to the visitor. Once that plumbing exists, it benefits any future rule that needs structured per-rule config — not just this one.

**Suggested commit sequence when ready to build:**

1. `Add LayerPolicy model and architecturalLayers to LintConfiguration`
2. `Parse architectural_layers from YAML in LintConfigurationLoader`
3. `Add ArchitecturalBoundary visitor (import-based check)`
4. `Extend ArchitecturalBoundary visitor with type-usage check`
5. `Add ArchitecturalBoundary tests and docs`

---

## Open Questions

- Should layers be user-defined only, or should there be built-in presets (e.g. `preset: clean-architecture`) that provide sensible defaults?
- How should the rule behave for files that don't match any defined layer — ignore, or warn that the file is uncategorized?
- Should `forbidden_types` match exact names only, or support prefix/suffix patterns (e.g. `NS*` to ban all ObjC bridging types)?
