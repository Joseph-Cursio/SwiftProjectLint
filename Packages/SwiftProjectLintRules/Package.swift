// swift-tools-version:6.2
import PackageDescription

let package = Package(
    name: "SwiftProjectLintRules",
    platforms: [
        .macOS(.v26),
        .iOS(.v26)
    ],
    products: [
        .library(
            name: "SwiftProjectLintRules",
            targets: ["SwiftProjectLintRules"]
        )
    ],
    dependencies: [
        .package(path: "../SwiftProjectLintModels"),
        .package(path: "../SwiftProjectLintVisitors"),
        .package(path: "../SwiftProjectLintRegistry"),
        .package(url: "https://github.com/apple/swift-syntax.git", exact: "602.0.0")
    ],
    targets: [
        .target(
            name: "SwiftProjectLintRules",
            dependencies: [
                "SwiftProjectLintModels",
                "SwiftProjectLintVisitors",
                "SwiftProjectLintRegistry",
                .product(name: "SwiftSyntax", package: "swift-syntax")
            ],
            path: "Sources/SwiftProjectLintRules"
        )
    ]
)
