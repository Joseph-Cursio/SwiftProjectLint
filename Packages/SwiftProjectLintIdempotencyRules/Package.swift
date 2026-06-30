// swift-tools-version:6.2
import PackageDescription

// Consistent with SwiftLintRuleStudio: explicit Swift 6 language mode + the
// MemberImportVisibility upcoming feature. MainActor default isolation is NOT
// applied here — these rules run as background AST analysis (actors / task
// groups), so main-actor pinning would defeat their parallelism.
let swiftSettings: [SwiftSetting] = [
    .swiftLanguageMode(.v6),
    .enableUpcomingFeature("MemberImportVisibility")
]

let package = Package(
    name: "SwiftProjectLintIdempotencyRules",
    platforms: [
        .macOS(.v26),
        .iOS(.v26)
    ],
    products: [
        .library(
            name: "SwiftProjectLintIdempotencyRules",
            targets: ["SwiftProjectLintIdempotencyRules"]
        )
    ],
    dependencies: [
        .package(path: "../SwiftProjectLintModels"),
        .package(path: "../SwiftProjectLintVisitors"),
        .package(path: "../SwiftProjectLintRegistry"),
        .package(url: "https://github.com/apple/swift-syntax.git", exact: "602.0.0"),
        // Idempotency rule visitors pattern-match `Effect` cases (via the
        // `DeclaredEffect` alias re-exported by SwiftProjectLintVisitors).
        // MemberImportVisibility requires importing the defining module, so
        // these targets depend on SEI directly. Keep this SHA aligned with the
        // root and SwiftProjectLintVisitors pins.
        .package(
            url: "https://github.com/Joseph-Cursio/SwiftEffectInference.git",
            revision: "b0751356cba09ed798a01a0a8930902d9955174c"
        )
    ],
    targets: [
        .target(
            name: "SwiftProjectLintIdempotencyRules",
            dependencies: [
                "SwiftProjectLintModels",
                "SwiftProjectLintVisitors",
                "SwiftProjectLintRegistry",
                .product(name: "SwiftSyntax", package: "swift-syntax"),
                .product(name: "SwiftEffectInference", package: "SwiftEffectInference")
            ],
            path: "Sources/SwiftProjectLintIdempotencyRules",
            swiftSettings: swiftSettings
        )
    ]
)
