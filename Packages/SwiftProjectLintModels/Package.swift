// swift-tools-version:6.2
import PackageDescription

// Consistent with SwiftLintRuleStudio: explicit Swift 6 language mode + the
// MemberImportVisibility upcoming feature. MainActor default isolation is NOT
// applied here — this package feeds the background AST-analysis engine.
let swiftSettings: [SwiftSetting] = [
    .swiftLanguageMode(.v6),
    .enableUpcomingFeature("MemberImportVisibility")
]

let package = Package(
    name: "SwiftProjectLintModels",
    platforms: [
        .macOS(.v26),
        .iOS(.v26)
    ],
    products: [
        .library(
            name: "SwiftProjectLintModels",
            targets: ["SwiftProjectLintModels"]
        )
    ],
    targets: [
        .target(
            name: "SwiftProjectLintModels",
            path: "Sources/SwiftProjectLintModels",
            swiftSettings: swiftSettings
        )
    ]
)
