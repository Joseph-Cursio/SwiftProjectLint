// swift-tools-version:6.2
import PackageDescription

// Consistent with SwiftLintRuleStudio: explicit Swift 6 language mode + the
// MemberImportVisibility upcoming feature. MainActor default isolation is NOT
// applied here — this package runs background AST visitors.
let swiftSettings: [SwiftSetting] = [
    .swiftLanguageMode(.v6),
    .enableUpcomingFeature("MemberImportVisibility")
]

let package = Package(
    name: "SwiftProjectLintVisitors",
    platforms: [
        .macOS(.v26),
        .iOS(.v26)
    ],
    products: [
        .library(
            name: "SwiftProjectLintVisitors",
            targets: ["SwiftProjectLintVisitors"]
        )
    ],
    dependencies: [
        .package(path: "../SwiftProjectLintModels"),
        .package(url: "https://github.com/apple/swift-syntax.git", exact: "602.0.0"),
        // The leaf effect-lattice library: single source of truth for the
        // `Effect` type and its `lub`. `DeclaredEffect` here is now a typealias
        // onto `SwiftEffectInference.Effect` (see EffectAnnotationParser.swift).
        // Revision-pinned because SEI carries no version tags yet; keep this
        // SHA aligned with the root package's pin. Both pin swift-syntax exact
        // 602.0.0, so there is no version conflict.
        .package(
            url: "https://github.com/Joseph-Cursio/SwiftEffectInference.git",
            revision: "b0751356cba09ed798a01a0a8930902d9955174c"
        )
    ],
    targets: [
        .target(
            name: "SwiftProjectLintVisitors",
            dependencies: [
                "SwiftProjectLintModels",
                .product(name: "SwiftSyntax", package: "swift-syntax"),
                .product(name: "SwiftEffectInference", package: "SwiftEffectInference")
            ],
            path: "Sources/SwiftProjectLintVisitors",
            swiftSettings: swiftSettings
        )
    ]
)
