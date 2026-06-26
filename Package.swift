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
        .package(url: "https://github.com/apple/swift-syntax.git", exact: "602.0.0"),
        .package(url: "https://github.com/nalexn/ViewInspector.git", from: "0.9.5"),
        .package(url: "https://github.com/apple/swift-argument-parser.git", from: "1.3.0"),
        .package(url: "https://github.com/jpsim/Yams.git", from: "5.0.0"),
        .package(url: "https://github.com/x-sheep/swift-property-based.git", from: "1.0.0"),
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
            revision: "6722e260f011c89c9f0334e5189a2c42590e41e4"
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
