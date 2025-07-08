// swift-tools-version:5.9
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
        .package(url: "https://github.com/apple/swift-syntax.git", exact: "601.0.1")
    ],
    targets: [
        .target(
            name: "SwiftProjectLintCore",
            dependencies: [
                .product(name: "SwiftSyntax", package: "swift-syntax"),
                .product(name: "SwiftParser", package: "swift-syntax")
            ],
            path: "SwiftProjectLintCore/SwiftProjectLintCore"
        ),
        .executableTarget(
            name: "SwiftProjectLint",
            dependencies: ["SwiftProjectLintCore"],
            path: "SwiftProjectLint/SwiftProjectLint"
        ),
        .testTarget(
            name: "SwiftProjectLintCoreTests",
            dependencies: ["SwiftProjectLintCore"],
            path: "SwiftProjectLintCoreTests"
        ),
        .testTarget(
            name: "SwiftProjectLintTests",
            dependencies: ["SwiftProjectLintCore"],
            path: "SwiftProjectLintTests"
        ),
        // UI tests are configured in Xcode project and should be run through Xcode
        // .testTarget(
        //     name: "SwiftProjectLintUITests",
        //     dependencies: ["SwiftProjectLint"],
        //     path: "SwiftProjectLintUITests"
        // ),
    ]
) 
