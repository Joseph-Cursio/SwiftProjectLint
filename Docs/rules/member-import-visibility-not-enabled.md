[← Back to Rules](RULES.md)

## Member Import Visibility Not Enabled

**Identifier:** `Member Import Visibility Not Enabled`
**Category:** Modernization
**Severity:** Info

### Rationale

Before [SE-0444](https://github.com/swiftlang/swift-evolution/blob/main/proposals/0444-member-import-visibility.md), a file can use a module's extension members without importing that module, as long as the module is loaded some other way: another file in the target imports it, or a dependency does.

```swift
// Package.swift: App depends on Mid and Ext; Mid imports Ext.

// Sources/Ext/Ext.swift
extension Int { public var doubled: Int { self * 2 } }

// Sources/App/App.swift
import Mid                          // no `import Ext`
public func app() -> Int { 2.doubled }   // compiles anyway
```

`App.swift` compiles because of an import it cannot see. It stops compiling when that import moves, in a change to a file or a package nobody associates with it, and SwiftPM and Xcode builds can disagree about whether it compiles at all.

SE-0444 (Swift 6.1) adds the `MemberImportVisibility` upcoming feature. With it, a file must import the module that declares an extension member before using that member, and the compiler names the missing import. No language mode turns it on yet, so a package gets it only by asking for it.

### Discussion

`MemberImportVisibilityNotEnabledVisitor` reads every `Package.swift` in the run and reports a package, once, at its `Package(…)` call, when none of its manifests enables the feature. Whether a *file* relies on another file's import takes type information this linter does not have. What it can see is whether the package lets the compiler check, so that is what it reports.

The fix is one command (Swift 6.2 or later, [SE-0486](https://github.com/swiftlang/swift-evolution/blob/main/proposals/0486-adoption-tooling-for-swift-features.md)):

```
swift package migrate --to-feature MemberImportVisibility
```

It builds the package with the feature in migration mode, inserts the imports each file was relying on, and adds `.enableUpcomingFeature("MemberImportVisibility")` to every target in `Package.swift`. On the example above it adds `internal import Ext` to `App.swift`.

As of October 2026, 15 of 25 widely used Swift packages surveyed enable it, among them swift-collections, swift-foundation, swift-testing, swift-nio, SwiftPM, sourcekit-lsp, GRDB, Vapor and SwiftLint.

**Any spelling counts as enabled.** Manifests turn the feature on inline, through a shared `let swiftSettings`, or by appending to every target in a `for target in package.targets` loop, sometimes under a condition. The rule does not try to resolve which targets each form reaches. If the feature name appears in any of the package's manifests (`Package.swift` or a `Package@swift-X.Y.swift` variant) as an unlabeled string, such as `.enableUpcomingFeature("…")`, `.enableExperimentalFeature("…")` or an element of a feature list, or inside a compiler flag, the package counts as having adopted it. A package that enables it on some targets and not others is therefore not reported.

**Not reported:**
- A package in a test, fixture or example folder (`Tests/`, `Fixtures/`, `Examples/`, `IntegrationTests/`, …). With `--include-nested-packages`, SwiftPM's own repository has 170 fixture packages.
- A package with no Swift targets (only binary, system-library or plugin targets).
- A manifest with `swift-tools-version` below 5.8, which has no `.enableUpcomingFeature`. Adopting the feature there means raising the tools version first, a decision about which toolchains the package supports.
- Xcode projects. Their equivalent is the `SWIFT_UPCOMING_FEATURE_MEMBER_IMPORT_VISIBILITY` build setting in the `.pbxproj`, which this linter does not read.

### Non-Violating Examples

```swift
// swift-tools-version:6.1
import PackageDescription

let package = Package(
    name: "Shop",
    targets: [
        .target(name: "Shop", swiftSettings: [.enableUpcomingFeature("MemberImportVisibility")])
    ]
)
```

```swift
// swift-tools-version:6.1
import PackageDescription

let package = Package(name: "Shop", targets: [.target(name: "Shop")])

for target in package.targets {
    var settings = target.swiftSettings ?? []
    settings.append(.enableUpcomingFeature("MemberImportVisibility"))
    target.swiftSettings = settings
}
```

### Violating Examples

```swift
// swift-tools-version:6.1
import PackageDescription

let package = Package(
    name: "Shop",
    targets: [
        .target(name: "Shop", swiftSettings: [.swiftLanguageMode(.v6)]),
        .testTarget(name: "ShopTests", dependencies: ["Shop"])
    ]
)
```

---
