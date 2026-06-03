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
        .package(url: "https://github.com/apple/swift-syntax.git", exact: "602.0.0")
    ],
    targets: [
        .target(
            name: "SwiftProjectLintVisitors",
            dependencies: [
                "SwiftProjectLintModels",
                .product(name: "SwiftSyntax", package: "swift-syntax")
            ],
            path: "Sources/SwiftProjectLintVisitors",
            swiftSettings: swiftSettings
        )
    ]
)
