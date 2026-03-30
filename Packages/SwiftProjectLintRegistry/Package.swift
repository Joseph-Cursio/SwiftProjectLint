// swift-tools-version:6.2
import PackageDescription

let package = Package(
    name: "SwiftProjectLintRegistry",
    platforms: [
        .macOS(.v26),
        .iOS(.v26)
    ],
    products: [
        .library(
            name: "SwiftProjectLintRegistry",
            targets: ["SwiftProjectLintRegistry"]
        )
    ],
    dependencies: [
        .package(path: "../SwiftProjectLintModels"),
        .package(path: "../SwiftProjectLintVisitors"),
        .package(url: "https://github.com/apple/swift-syntax.git", exact: "602.0.0")
    ],
    targets: [
        .target(
            name: "SwiftProjectLintRegistry",
            dependencies: [
                "SwiftProjectLintModels",
                "SwiftProjectLintVisitors",
                .product(name: "SwiftSyntax", package: "swift-syntax"),
                .product(name: "SwiftParser", package: "swift-syntax")
            ],
            path: "Sources/SwiftProjectLintRegistry"
        )
    ]
)
