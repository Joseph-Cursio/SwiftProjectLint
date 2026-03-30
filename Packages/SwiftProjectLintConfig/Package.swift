// swift-tools-version:6.2
import PackageDescription

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
            path: "Sources/SwiftProjectLintConfig"
        )
    ]
)
