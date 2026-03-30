// swift-tools-version:6.2
import PackageDescription

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
            path: "Sources/SwiftProjectLintVisitors"
        )
    ]
)
