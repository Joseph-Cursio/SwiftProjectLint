// swift-tools-version:6.2
import PackageDescription

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
                "SwiftProjectLintConfig",
                .product(name: "SwiftSyntax", package: "swift-syntax"),
                .product(name: "SwiftParser", package: "swift-syntax")
            ],
            path: "Sources/SwiftProjectLintEngine"
        )
    ]
)
