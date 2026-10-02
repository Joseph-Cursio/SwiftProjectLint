@testable import Core
import SwiftParser
@testable import SwiftProjectLintRules
import SwiftSyntax
import Testing

@Suite
struct MemberImportVisibilityNotEnabledVisitorTests {

    /// Runs the visitor the way the cross-file engine does.
    private func analyze(_ files: [String: String]) -> [LintIssue] {
        var cache: [String: SourceFileSyntax] = [:]
        for (name, source) in files {
            cache[name] = Parser.parse(source: source)
        }
        let visitor = MemberImportVisibilityNotEnabledVisitor(fileCache: cache)
        visitor.setPattern(MemberImportVisibilityNotEnabled().pattern)
        for (name, ast) in cache.sorted(by: { $0.key < $1.key }) {
            visitor.setFilePath(name)
            visitor.setSourceLocationConverter(SourceLocationConverter(fileName: name, tree: ast))
            visitor.walk(ast)
        }
        visitor.finalizeAnalysis()
        return visitor.detectedIssues.filter { $0.ruleName == .memberImportVisibilityNotEnabled }
    }

    /// A manifest with one library target, `settings` spliced in after `targets:`.
    private func manifest(
        toolsVersion: String = "6.1",
        settings: String = "",
        trailer: String = ""
    ) -> String {
        """
        // swift-tools-version:\(toolsVersion)
        import PackageDescription

        let package = Package(
            name: "Shop",
            targets: [
                .target(name: "Shop"\(settings)),
                .testTarget(name: "ShopTests", dependencies: ["Shop"])
            ]
        )
        \(trailer)
        """
    }

    // MARK: - Positive

    @Test func flagsPackageThatNeverEnablesTheFeature() throws {
        let issues = analyze(["Package.swift": manifest()])

        let issue = try #require(issues.first)
        #expect(issues.count == 1)
        #expect(issue.severity == .info)
        #expect(issue.filePath == "Package.swift")
        #expect(issue.lineNumber == 4)
        #expect(issue.message.contains("Package 'Shop'"))
        #expect(issue.message.contains("SE-0444"))
        #expect(issue.suggestion?.contains("swift package migrate --to-feature MemberImportVisibility") == true)
    }

    /// swift-system has a target called `MemberImportVisibility`; a name is not a setting.
    @Test func targetNamedForTheFeatureDoesNotCount() {
        let source = manifest(trailer: """
        package.targets.append(.target(name: "MemberImportVisibility", path: "Tests/MemberImportVisibility"))
        """)
        #expect(analyze(["Package.swift": source]).count == 1)
    }

    @Test func flagsBenchmarksPackageBesideAnAdoptingRoot() throws {
        let issues = analyze([
            "Package.swift": manifest(
                settings: #", swiftSettings: [.enableUpcomingFeature("MemberImportVisibility")]"#
            ),
            "Benchmarks/Package.swift": manifest()
        ])
        let issue = try #require(issues.first)
        #expect(issues.count == 1)
        #expect(issue.filePath == "Benchmarks/Package.swift")
    }

    @Test func namesThePackageGenericallyWhenItsNameIsComputed() throws {
        let source = """
        // swift-tools-version:6.1
        import PackageDescription
        let name = "Shop"
        let package = Package(name: name, targets: [.target(name: "Shop")])
        """
        let issue = try #require(analyze(["Package.swift": source]).first)
        #expect(issue.message.hasPrefix("This package"))
    }

    // MARK: - Every spelling of "enabled"

    @Test("Enabled in any spelling is not reported", arguments: [
        // Inline on the target.
        #", swiftSettings: [.enableUpcomingFeature("MemberImportVisibility")]"#,
        // SwiftPM's own spelling, for compilers before 6.1.
        #", swiftSettings: [.enableExperimentalFeature("MemberImportVisibility")]"#,
        // As a compiler flag in one string.
        #", swiftSettings: [.unsafeFlags(["-enable-upcoming-feature MemberImportVisibility"])]"#,
        // As a compiler flag split across two strings.
        #", swiftSettings: [.unsafeFlags(["-enable-upcoming-feature", "MemberImportVisibility"])]"#
    ])
    func enabledOnTarget(settings: String) {
        #expect(analyze(["Package.swift": manifest(settings: settings)]).isEmpty)
    }

    @Test func enabledThroughASharedSettingsConstant() {
        let source = """
        // swift-tools-version:6.1
        import PackageDescription

        let swiftSettings: [SwiftSetting] = [
            .swiftLanguageMode(.v6),
            .enableUpcomingFeature("MemberImportVisibility")
        ]

        let package = Package(
            name: "Shop",
            targets: [.target(name: "Shop", swiftSettings: swiftSettings)]
        )
        """
        #expect(analyze(["Package.swift": source]).isEmpty)
    }

    /// The swift-log / swift-nio shape: appended to every target after the `Package` is built.
    @Test func enabledInALoopOverEveryTarget() {
        let source = manifest(trailer: """
        for target in package.targets where target.type != .plugin {
            var settings = target.swiftSettings ?? []
            settings.append(.enableUpcomingFeature("MemberImportVisibility"))
            target.swiftSettings = settings
        }
        """)
        #expect(analyze(["Package.swift": source]).isEmpty)
    }

    @Test func enabledThroughAMappedFeatureList() {
        let source = manifest(trailer: """
        let features = ["ExistentialAny", "MemberImportVisibility"]
        for target in package.targets {
            target.swiftSettings = features.map { .enableUpcomingFeature($0) }
        }
        """)
        #expect(analyze(["Package.swift": source]).isEmpty)
    }

    /// The package decided once, even if only a version-specific manifest says so.
    @Test func enabledOnlyInAVersionSpecificManifest() {
        let issues = analyze([
            "Package.swift": manifest(toolsVersion: "6.0"),
            "Package@swift-6.1.swift": manifest(
                settings: #", swiftSettings: [.enableUpcomingFeature("MemberImportVisibility")]"#
            )
        ])
        #expect(issues.isEmpty)
    }

    // MARK: - Not judged

    @Test func toolsVersionWithoutUpcomingFeaturesIsSkipped() {
        #expect(analyze(["Package.swift": manifest(toolsVersion: "5.7")]).isEmpty)
    }

    @Test func toolsVersionIsReadWhenNotOnTheFirstLine() {
        let source = "import CompilerPluginSupport\n" + manifest(toolsVersion: "5.7")
        #expect(analyze(["Package.swift": source]).isEmpty)
    }

    @Test func toolsVersionCanOmitTheMinorVersion() throws {
        let version = MemberImportVisibilityNotEnabledVisitor.toolsVersion(
            of: Parser.parse(source: "// swift-tools-version: 6\nimport PackageDescription")
        )
        let parsed = try #require(version)
        #expect(parsed.major == 6 && parsed.minor == 0)
    }

    @Test func packageWithoutSwiftTargetsIsSkipped() {
        let source = """
        // swift-tools-version:6.1
        import PackageDescription
        let package = Package(
            name: "Vendored",
            targets: [.binaryTarget(name: "Vendored", path: "Vendored.xcframework")]
        )
        """
        #expect(analyze(["Package.swift": source]).isEmpty)
    }

    @Test("Fixture and example packages are skipped", arguments: [
        "Fixtures/Miscellaneous/Simple/Package.swift",
        "Tests/SPM/Package.swift",
        "IntegrationTests/allocation-counter/Package.swift",
        "Examples/hello-world/Package.swift"
    ])
    func fixturePackageIsSkipped(path: String) {
        #expect(analyze([path: manifest()]).isEmpty)
    }

    @Test func versionSpecificManifestAloneIsNotReported() {
        #expect(analyze(["Package@swift-6.1.swift": manifest()]).isEmpty)
    }
}
