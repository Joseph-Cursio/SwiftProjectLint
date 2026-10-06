@testable import Core
import Foundation
import Testing

/// A nested package's types are in the table only when the root compiles that package — the
/// shared spec's amendment B — checked through `ProjectLinter`.
///
/// The case that forced the bound: an app whose `ReportBuilder` is a pure kernel building the
/// app's plain `Row`, beside an unrelated `Demo/` package that declares its own `Row` minting a
/// `UUID`. With every nested package in the table, SEI read the app's `Row(n:)` as that namesake,
/// so `rows` stopped being a function of its inputs, `ReportBuilder` lost Direct Instantiation's
/// pure-kernel exemption, and the run gained a warning — exit 1 at the default threshold — though
/// it said it had not analysed `Demo/`.
@Suite("The package purity takes the nested packages the root compiles")
struct PackagePurityNestedPackageTests {

    @Test("an unrelated nested package's namesake neither refutes nor costs an exemption")
    func unrelatedNestedPackageDoesNotRefute() async throws {
        let issues = try await PackagePurityFixtures.lint(Self.app(manifest: Self.manifest(dependencies: "")))
        #expect(Self.warnsAboutReportBuilder(issues) == false, "Demo's Row took ReportBuilder's exemption")
        #expect(PackagePurityFixtures.symbols(issues).isSuperset(of: ["rowCount", "rows", "render"]))
    }

    @Test("the same package, listed as a local dependency, is in the table")
    func dependedOnNestedPackageRefutes() async throws {
        let issues = try await PackagePurityFixtures.lint(
            Self.app(manifest: Self.manifest(dependencies: #".package(path: "Demo")"#))
        )
        let candidates = PackagePurityFixtures.symbols(issues)
        #expect(candidates.contains("render"), "the rule produced nothing, so the absences prove nothing")
        #expect(candidates.contains("rowCount") == false)
        #expect(candidates.contains("rows") == false)
        #expect(Self.warnsAboutReportBuilder(issues))
    }

    @Test("a root with no manifest takes every nested package, as SwiftLintRuleStudio's does")
    func rootWithoutManifestIncludesEveryNestedPackage() async throws {
        var files = Self.app(manifest: nil)
        files["Core/Package.swift"] = Self.manifest(dependencies: "")
        files["Core/Sources/Core/Item.swift"] = PackagePurityFixtures.refutingItem
        files["App/Callers.swift"] = PackagePurityFixtures.callers
        let candidates = PackagePurityFixtures.symbols(try await PackagePurityFixtures.lint(files))
        #expect(candidates.contains("sentinelAdd"))
        #expect(candidates.contains("countOf") == false, "Core/ was left out of an Xcode-style root's table")
        #expect(candidates.contains("rowCount") == false, "Demo/ was left out of an Xcode-style root's table")
    }

    // MARK: - Fixtures

    /// The probe the review ran: an executable `App`, its plain `Row`, a pure kernel building it, a
    /// screen holding the kernel, and an unrelated `Demo/` package declaring a refuting `Row`.
    private static func app(manifest: String?) -> [String: String] {
        var files = [
            "Sources/App/Row.swift": "struct Row: Equatable { let n: Int }\n",
            "Sources/App/ReportBuilder.swift": """
            struct ReportBuilder {
                func rows(_ values: [Int]) -> [Row] { values.map { Row(n: $0) } }
            }
            """,
            "Sources/App/Report.swift": """
            final class ReportScreen {
                let builder = ReportBuilder()
                func render(_ values: [Int]) -> Int { builder.rows(values).count }
            }
            func rowCount(_ n: Int) -> Int { Row(n: n).n * 2 }
            """,
            "Sources/App/main.swift": "print(ReportScreen().render([1, 2]))\n",
            "Demo/Package.swift": """
            // swift-tools-version:6.0
            import PackageDescription
            let package = Package(name: "Demo", targets: [.target(name: "Demo")])
            """,
            "Demo/Sources/Demo/Row.swift": "import Foundation\nstruct Row { let id = UUID(); let n: Int }\n"
        ]
        if let manifest { files["Package.swift"] = manifest }
        return files
    }

    private static func manifest(dependencies: String) -> String {
        """
        // swift-tools-version:6.0
        import PackageDescription
        let package = Package(
            name: "App",
            dependencies: [\(dependencies)],
            targets: [.executableTarget(name: "App")]
        )
        """
    }

    private static func warnsAboutReportBuilder(_ issues: [LintIssue]) -> Bool {
        issues.contains { $0.ruleName == .directInstantiation && $0.message.contains("ReportBuilder") }
    }
}
