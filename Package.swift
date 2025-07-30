// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "SwiftProjectLint",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .library(
            name: "SwiftProjectLintCore",
            targets: ["SwiftProjectLintCore"]
        ),
        .executable(
            name: "SwiftProjectLint",
            targets: ["SwiftProjectLint"]
        ),
    ],
    dependencies: [
        .package(url: "https://github.com/apple/swift-syntax.git", exact: "601.0.0"),
        .package(url: "https://github.com/nalexn/ViewInspector.git", from: "0.9.5")
    ],
    targets: [
        .target(
            name: "SwiftProjectLintCore",
            dependencies: [
                .product(name: "SwiftSyntax", package: "swift-syntax"),
                .product(name: "SwiftParser", package: "swift-syntax")
            ],
            path: "Sources/SwiftProjectLintCore"
        ),
        .executableTarget(
            name: "SwiftProjectLint",
            dependencies: ["SwiftProjectLintCore"],
            path: "Sources/SwiftProjectLint"
        ),
        .testTarget(
            name: "SwiftProjectLintCoreTests",
            dependencies: ["SwiftProjectLintCore", "ViewInspector"],
            path: "Tests/SwiftProjectLintCoreTests"
        ),
        .testTarget(
            name: "SwiftProjectLintTests",
            dependencies: ["SwiftProjectLintCore", "SwiftProjectLint", "ViewInspector"],
            path: "Tests/SwiftProjectLintTests"
        ),
        // UI tests are configured in Xcode project and should be run through Xcode
        // .testTarget(
        //     name: "SwiftProjectLintUITests",
        //     dependencies: ["SwiftProjectLint"],
        //     path: "Tests/SwiftProjectLintUITests"
        // ),
    ]
) 
