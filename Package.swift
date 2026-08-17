// swift-tools-version:6.2
import PackageDescription

// Consistent with SwiftLintRuleStudio. Non-UI targets (Core, CLI, tests) get
// Swift 6 language mode + MemberImportVisibility but stay nonisolated — Core
// drives background AST analysis and feeds the batch CLI, so MainActor default
// isolation would be wrong here. Only the SwiftUI App target adds MainActor
// default isolation.
let engineSwiftSettings: [SwiftSetting] = [
    .swiftLanguageMode(.v6),
    .enableUpcomingFeature("MemberImportVisibility")
]

let uiSwiftSettings: [SwiftSetting] = [
    .swiftLanguageMode(.v6),
    .defaultIsolation(MainActor.self),
    .enableUpcomingFeature("MemberImportVisibility")
]

let package = Package(
    name: "SwiftProjectLint",
    platforms: [
        .macOS(.v26),
        .iOS(.v26)
    ],
    products: [
        .library(
            name: "Core",
            targets: ["Core"]
        ),
        .executable(
            name: "App",
            targets: ["App"]
        ),
        .executable(
            name: "CLI",
            targets: ["CLI"]
        )
    ],
    dependencies: [
        .package(path: "Packages/SwiftProjectLintModels"),
        .package(path: "Packages/SwiftProjectLintVisitors"),
        .package(path: "Packages/SwiftProjectLintRegistry"),
        .package(path: "Packages/SwiftProjectLintRules"),
        .package(path: "Packages/SwiftProjectLintIdempotencyRules"),
        .package(path: "Packages/SwiftProjectLintConfig"),
        .package(path: "Packages/SwiftProjectLintEngine"),
        .package(url: "https://github.com/swiftlang/swift-syntax.git", exact: "602.0.0"),
        // Pinned to the exact commit that fixes ViewInspector on macOS 27
        // (nalexn/ViewInspector#421, merged 2026-08-09). There is no 0.10.4 tag
        // yet — 0.10.4 is the default branch — so a revision pin is the only way
        // to get the fix reproducibly. Swap for `from:` once the tag lands.
        .package(
            url: "https://github.com/nalexn/ViewInspector.git",
            revision: "6be008f348a757e7c0c6901c2dde983e5bba069f"
        ),
        .package(url: "https://github.com/apple/swift-argument-parser.git", from: "1.3.0"),
        .package(url: "https://github.com/jpsim/Yams.git", from: "5.0.0"),
        .package(url: "https://github.com/x-sheep/swift-property-based.git", from: "1.0.0"),
        // The conformance-law catalog, test-only. This package already had the
        // generator *engine* (`swift-property-based`, above) and used it for
        // hand-written property suites, but nothing ran the laws the standard
        // protocols already owe: `swift-infer discover` measured 59 such laws
        // over 22 carriers across the seven nested packages, checked by nothing.
        // `PropertyLawKit` is the catalog that runs them — one
        // `check<Protocol>PropertyLaws` call per conformance.
        //
        // Test-only, and deliberately kit-only. Recording verdicts back to
        // `swift-infer` needs `SwiftInferKitEvidence`, which would add a
        // dependency edge from this package to SwiftInferProperties — the
        // opposite direction from the one the toolchain's dependency graph has,
        // where the two leaves meet only at SwiftEffectInference. Running the
        // laws is the value; feeding the verdicts back is a separate decision.
        .package(url: "https://github.com/Joseph-Cursio/SwiftPropertyLaws.git", from: "3.28.0"),
        .package(url: "https://github.com/Joseph-Cursio/LintStudioUI.git", from: "1.3.0"),
        // The leaf effect-lattice library — now the single source of truth for
        // the `Effect` type and its `lub`. SPL's `DeclaredEffect` is a typealias
        // onto `SwiftEffectInference.Effect`, consumed transitively through the
        // SwiftProjectLintVisitors / SwiftProjectLintIdempotencyRules packages
        // (which declare their own SEI dependency at this same revision). This
        // root-level declaration also backs CoreTests' direct `import` of the
        // lattice laws. Pinned by revision because SEI carries no version tags
        // yet; keep this SHA aligned with the nested packages' pins. Both pin
        // swift-syntax exact 602.0.0, so there is no version conflict.
        .package(
            url: "https://github.com/Joseph-Cursio/SwiftEffectInference.git",
            revision: "c66fceb825eebf77477631388e1ba4326a7aa4e6"
        )
    ],
    targets: [
        .target(
            name: "Core",
            dependencies: [
                "SwiftProjectLintEngine",
                .product(name: "LintStudioCore", package: "LintStudioUI")
            ],
            path: "Sources/Core",
            swiftSettings: engineSwiftSettings
        ),
        .executableTarget(
            name: "CLI",
            dependencies: [
                "Core",
                .product(name: "ArgumentParser", package: "swift-argument-parser")
            ],
            path: "Sources/CLI",
            swiftSettings: engineSwiftSettings
        ),
        .executableTarget(
            name: "App",
            dependencies: [
                "Core",
                .product(name: "LintStudioUI", package: "LintStudioUI")
            ],
            path: "Sources/App",
            resources: [
                .process("Assets.xcassets"),
                .process("Resources")
            ],
            swiftSettings: uiSwiftSettings
        ),
        .testTarget(
            name: "CLITests",
            dependencies: ["Core", "CLI"],
            path: "Tests/CLITests",
            swiftSettings: engineSwiftSettings
        ),
        .testTarget(
            name: "CoreTests",
            dependencies: [
                "Core",
                "SwiftProjectLintIdempotencyRules",
                .product(name: "PropertyBased", package: "swift-property-based"),
                .product(name: "PropertyLawKit", package: "SwiftPropertyLaws"),
                .product(name: "SwiftEffectInference", package: "SwiftEffectInference")
            ],
            path: "Tests/CoreTests",
            swiftSettings: engineSwiftSettings
        ),
        .testTarget(
            name: "AppTests",
            dependencies: [
                "Core", "App", "ViewInspector",
                .product(name: "LintStudioUI", package: "LintStudioUI")
            ],
            path: "Tests/AppTests",
            swiftSettings: engineSwiftSettings
        )
        // UI tests are configured in Xcode project and should be run through Xcode
        // .testTarget(
        //     name: "UITests",
        //     dependencies: ["App"],
        //     path: "Tests/UITests"
        // ),
    ]
)
