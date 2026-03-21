// swift-tools-version:6.2
import PackageDescription

let package = Package(
    name: "SwiftProjectLint",
    platforms: [
        .macOS(.v14)
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
        .executable(
            name: "SwiftProjectLintCLI",
            targets: ["SwiftProjectLintCLI"]
        )
    ],
    dependencies: [
        .package(url: "https://github.com/apple/swift-syntax.git", exact: "602.0.0"),
        .package(url: "https://github.com/nalexn/ViewInspector.git", from: "0.9.5"),
        .package(url: "https://github.com/apple/swift-argument-parser.git", from: "1.3.0"),
        .package(url: "https://github.com/jpsim/Yams.git", from: "5.0.0")
    ],
    targets: [
        .target(
            name: "SwiftProjectLintCore",
            dependencies: [
                .product(name: "SwiftSyntax", package: "swift-syntax"),
                .product(name: "SwiftParser", package: "swift-syntax"),
                .product(name: "Yams", package: "Yams")
            ],
            path: "Sources/SwiftProjectLintCore"
        ),
        .executableTarget(
            name: "SwiftProjectLintCLI",
            dependencies: [
                "SwiftProjectLintCore",
                .product(name: "ArgumentParser", package: "swift-argument-parser")
            ],
            path: "Sources/SwiftProjectLintCLI"
        ),
        .executableTarget(
            name: "SwiftProjectLint",
            dependencies: ["SwiftProjectLintCore"],
            path: "Sources/SwiftProjectLint",
            resources: [
                .process("Assets.xcassets"),
                .process("Resources")
            ],
            swiftSettings: [
                .defaultIsolation(MainActor.self),
                .enableUpcomingFeature("MemberImportVisibility")
            ]
        ),
        .testTarget(
            name: "SwiftProjectLintCLITests",
            dependencies: ["SwiftProjectLintCore", "SwiftProjectLintCLI"],
            path: "Tests/SwiftProjectLintCLITests"
        ),
        .testTarget(
            name: "SwiftProjectLintCoreTests",
            dependencies: ["SwiftProjectLintCore"],
            path: "Tests/SwiftProjectLintCoreTests"
        ),
        .testTarget(
            name: "SwiftProjectLintTests",
            dependencies: ["SwiftProjectLintCore", "SwiftProjectLint", "ViewInspector"],
            path: "Tests/SwiftProjectLintTests",
            swiftSettings: [
                .enableUpcomingFeature("MemberImportVisibility")
            ]
        )
        // UI tests are configured in Xcode project and should be run through Xcode
        // .testTarget(
        //     name: "SwiftProjectLintUITests",
        //     dependencies: ["SwiftProjectLint"],
        //     path: "Tests/SwiftProjectLintUITests"
        // ),
    ]
) 
