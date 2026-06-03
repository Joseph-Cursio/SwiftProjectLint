// swift-tools-version:6.2
import PackageDescription

// Consistent with SwiftLintRuleStudio: explicit Swift 6 language mode + the
// MemberImportVisibility upcoming feature. MainActor default isolation is NOT
// applied here — config parsing feeds the background AST engine.
let swiftSettings: [SwiftSetting] = [
    .swiftLanguageMode(.v6),
    .enableUpcomingFeature("MemberImportVisibility")
]

let package = Package(
    name: "SwiftProjectLintConfig",
    platforms: [
        .macOS(.v26),
        .iOS(.v26)
    ],
    products: [
        .library(
            name: "SwiftProjectLintConfig",
            targets: ["SwiftProjectLintConfig"]
        )
    ],
    dependencies: [
        .package(path: "../SwiftProjectLintModels"),
        .package(url: "https://github.com/jpsim/Yams.git", from: "5.0.0")
    ],
    targets: [
        .target(
            name: "SwiftProjectLintConfig",
            dependencies: [
                "SwiftProjectLintModels",
                .product(name: "Yams", package: "Yams")
            ],
            path: "Sources/SwiftProjectLintConfig",
            swiftSettings: swiftSettings
        )
    ]
)
