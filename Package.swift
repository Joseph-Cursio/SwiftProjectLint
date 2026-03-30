// swift-tools-version:6.2
import PackageDescription

let package = Package(
    name: "SwiftProjectLint",
    platforms: [
        .macOS(.v26),
        .iOS(.v26)
    ],
    products: [
        .library(
            name: "Core",
            targets: ["Core"]
        ),
        .executable(
            name: "App",
            targets: ["App"]
        ),
        .executable(
            name: "CLI",
            targets: ["CLI"]
        )
    ],
    dependencies: [
        .package(path: "Packages/SwiftProjectLintModels"),
        .package(path: "Packages/SwiftProjectLintVisitors"),
        .package(path: "Packages/SwiftProjectLintRegistry"),
        .package(path: "Packages/SwiftProjectLintRules"),
        .package(path: "Packages/SwiftProjectLintConfig"),
        .package(path: "Packages/SwiftProjectLintEngine"),
        .package(url: "https://github.com/apple/swift-syntax.git", exact: "602.0.0"),
        .package(url: "https://github.com/nalexn/ViewInspector.git", from: "0.9.5"),
        .package(url: "https://github.com/apple/swift-argument-parser.git", from: "1.3.0"),
        .package(url: "https://github.com/jpsim/Yams.git", from: "5.0.0")
    ],
    targets: [
        .target(
            name: "Core",
            dependencies: [
                "SwiftProjectLintEngine"
            ],
            path: "Sources/Core"
        ),
        .executableTarget(
            name: "CLI",
            dependencies: [
                "Core",
                .product(name: "ArgumentParser", package: "swift-argument-parser")
            ],
            path: "Sources/CLI"
        ),
        .executableTarget(
            name: "App",
            dependencies: ["Core"],
            path: "Sources/App",
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
            name: "CLITests",
            dependencies: ["Core", "CLI"],
            path: "Tests/CLITests"
        ),
        .testTarget(
            name: "CoreTests",
            dependencies: ["Core"],
            path: "Tests/CoreTests"
        ),
        .testTarget(
            name: "AppTests",
            dependencies: ["Core", "App", "ViewInspector"],
            path: "Tests/AppTests",
            swiftSettings: [
                .enableUpcomingFeature("MemberImportVisibility")
            ]
        )
        // UI tests are configured in Xcode project and should be run through Xcode
        // .testTarget(
        //     name: "UITests",
        //     dependencies: ["App"],
        //     path: "Tests/UITests"
        // ),
    ]
)
