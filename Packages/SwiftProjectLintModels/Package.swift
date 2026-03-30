// swift-tools-version:6.2
import PackageDescription

let package = Package(
    name: "SwiftProjectLintModels",
    platforms: [
        .macOS(.v26),
        .iOS(.v26)
    ],
    products: [
        .library(
            name: "SwiftProjectLintModels",
            targets: ["SwiftProjectLintModels"]
        )
    ],
    targets: [
        .target(
            name: "SwiftProjectLintModels",
            path: "Sources/SwiftProjectLintModels"
        )
    ]
)
