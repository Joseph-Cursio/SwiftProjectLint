@testable import Core
import Testing

/// What the rule refuses to guess: manifests and targets it cannot read, and files it cannot place.
@Suite
struct UndeclaredTargetDependencyManifestReadingTests {

    private func analyze(files: [String: String]) -> [LintIssue] {
        UndeclaredTargetDependencyHarness.analyze(files: files)
    }

    /// The three-layer manifest from the rule doc: Checkout and Persistence may use Domain only.
    private let layeredManifest = """
    // swift-tools-version:6.0
    import PackageDescription

    let package = Package(
        name: "App",
        targets: [
            .target(name: "Domain"),
            .target(name: "Persistence", dependencies: ["Domain"]),
            .target(name: "Checkout", dependencies: [.target(name: "Domain")]),
            .testTarget(name: "CheckoutTests", dependencies: ["Checkout"])
        ]
    )
    """

    // MARK: - Negative: what the manifest does not state

    @Test func skipsATargetWhoseDependenciesAreComputed() {
        let issues = analyze(files: [
            "Package.swift": """
            let shared: [Target.Dependency] = [.target(name: "Domain")]
            let package = Package(
                name: "App",
                targets: [
                    .target(name: "Domain"),
                    .target(name: "Persistence"),
                    .target(name: "Checkout", dependencies: shared + ["Persistence"]),
                    .target(name: "Billing")
                ]
            )
            """,
            "Sources/Checkout/Checkout.swift": "import Domain",
            "Sources/Billing/Billing.swift": "import Persistence"
        ])

        // Checkout's list cannot be enumerated; Billing's is a literal empty list and still checked.
        #expect(issues.map(\.filePath) == ["Sources/Billing/Billing.swift"])
    }

    @Test func refusesAManifestWithAComputedTargetName() {
        let issues = analyze(files: [
            "Package.swift": """
            let name = "Checkout"
            let package = Package(
                name: "App",
                targets: [
                    .target(name: "Persistence", path: "Lib"),
                    .target(name: "App", path: "Sources"),
                    .target(name: name, path: "Sources/Checkout")
                ]
            )
            """,
            "Sources/Checkout/Checkout.swift": "import Persistence"
        ])

        // Reading around the unnamed target would hand its file to `App`, whose path encloses it,
        // and report `App` for an import `App` never makes.
        #expect(issues.isEmpty)
    }

    @Test func refusesAManifestWhenABareTargetCallCannotBePlaced() {
        let issues = analyze(files: [
            "Package.swift": """
            func register(_ target: Target) {}
            register(.target(name: "Checkout"))
            let package = Package(
                name: "App",
                targets: [.target(name: "Persistence", path: "Lib"), .target(name: "App", path: "Sources")]
            )
            """,
            "Sources/Checkout/Checkout.swift": "import Persistence"
        ])

        // `.target(name:)` alone could be a Target or a Target.Dependency. Either guess reports a
        // finding here — against `Checkout` if it is taken as a target, against `App` if it is not.
        #expect(issues.isEmpty)
    }

    @Test func refusesAPackageWithAVersionSpecificManifest() {
        let issues = analyze(files: [
            "Package.swift": layeredManifest,
            "Package@swift-5.9.swift": layeredManifest,
            "Sources/Checkout/Checkout.swift": "import Persistence"
        ])

        #expect(issues.isEmpty)
    }

    @Test func anExcludedFileBelongsToNoTarget() {
        let issues = analyze(files: [
            "Package.swift": """
            let package = Package(
                name: "App",
                targets: [
                    .target(name: "Persistence"),
                    .target(name: "Checkout", exclude: ["Legacy"])
                ]
            )
            """,
            "Sources/Checkout/Legacy/Old.swift": "import Persistence",
            "Sources/Checkout/Checkout.swift": "struct Checkout {}"
        ])

        #expect(issues.isEmpty)
    }

    @Test func aNestedPackagesFilesAreNotClaimedByTheOuterPackage() {
        let issues = analyze(files: [
            "Package.swift": """
            let package = Package(
                name: "Outer",
                targets: [.target(name: "Persistence"), .target(name: "Everything", path: ".")]
            )
            """,
            "Vendor/Inner/Package.swift": #"let package = Package(name: "Inner", targets: [.target(name: "Inner")])"#,
            "Vendor/Inner/Sources/Inner/Inner.swift": "import Persistence"
        ])

        #expect(issues.isEmpty)
    }

    @Test func producesNothingWithoutAManifest() {
        let issues = analyze(files: [
            "Sources/Checkout/Checkout.swift": "import Persistence"
        ])

        #expect(issues.isEmpty)
    }
}
