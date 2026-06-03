// swift-tools-version:6.2
import PackageDescription

// Consistent with SwiftLintRuleStudio: explicit Swift 6 language mode + the
// MemberImportVisibility upcoming feature. MainActor default isolation is NOT
// applied here — the engine orchestrates background AST analysis (actors / task
// groups), so main-actor pinning would serialize it on the main thread.
let swiftSettings: [SwiftSetting] = [
    .swiftLanguageMode(.v6),
    .enableUpcomingFeature("MemberImportVisibility")
]

let package = Package(
    name: "SwiftProjectLintEngine",
    platforms: [
        .macOS(.v26),
        .iOS(.v26)
    ],
    products: [
        .library(
            name: "SwiftProjectLintEngine",
            targets: ["SwiftProjectLintEngine"]
        )
    ],
    dependencies: [
        .package(path: "../SwiftProjectLintModels"),
        .package(path: "../SwiftProjectLintVisitors"),
        .package(path: "../SwiftProjectLintRegistry"),
        .package(path: "../SwiftProjectLintRules"),
        .package(path: "../SwiftProjectLintIdempotencyRules"),
        .package(path: "../SwiftProjectLintConfig"),
        .package(url: "https://github.com/apple/swift-syntax.git", exact: "602.0.0")
    ],
    targets: [
        .target(
            name: "SwiftProjectLintEngine",
            dependencies: [
                "SwiftProjectLintModels",
                "SwiftProjectLintVisitors",
                "SwiftProjectLintRegistry",
                "SwiftProjectLintRules",
                "SwiftProjectLintIdempotencyRules",
                "SwiftProjectLintConfig",
                .product(name: "SwiftSyntax", package: "swift-syntax"),
                .product(name: "SwiftParser", package: "swift-syntax")
            ],
            path: "Sources/SwiftProjectLintEngine",
            swiftSettings: swiftSettings
        )
    ]
)
