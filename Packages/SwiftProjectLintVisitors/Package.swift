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
        // SwiftEffectInference owns the effect-classification engines that
        // SPL used to host directly (CallSiteEffectInferrer / BodyEffectInferrer
        // / EffectAnnotationParser / EffectSymbolTable). SPL is one of two
        // initial consumers (the other is SwiftInferProperties) per
        // SwiftEffectInference's docs/SwiftEffectInference Design v0.2.md §2/§10.
        // Local-path dep during pre-1.0 development, swap to versioned URL
        // before tagging 1.0.
        .package(path: "../../../SwiftEffectInference"),
        .package(url: "https://github.com/apple/swift-syntax.git", exact: "602.0.0")
    ],
    targets: [
        .target(
            name: "SwiftProjectLintVisitors",
            dependencies: [
                "SwiftProjectLintModels",
                "SwiftEffectInference",
                .product(name: "SwiftSyntax", package: "swift-syntax")
            ],
            path: "Sources/SwiftProjectLintVisitors"
        )
    ]
)
