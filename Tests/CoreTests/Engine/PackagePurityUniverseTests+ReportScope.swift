@testable import Core
import Foundation
import Testing

/// What the universe leaves out, the rules that read it do not report on.
///
/// A test suite's folder — `test/`, `tests/`, `validation-test/` — is out of the universe but
/// reported as production. Its files were judged without the types they declare, and constructing a
/// type the facts do not know is judged pure: `probeValue`, building a `Probe` whose initializer
/// prints, was a Pure Function Property-Test Candidate under `tests/` and nothing under `prod/`.
/// `ProjectLinter.withinPurityScope` now drops the readers' findings on such a file, and only theirs.
extension PackagePurityUniverseTests {

    /// The suites of `testSuiteNamesakeDoesNotRefuteProduction`: each suite name, at the root and
    /// below a production folder.
    static let suiteFolders = ["test/Parse", "validation-test/stdlib", "tests", "utils/tool/tests"]

    /// What the readers report in production, so a run that reports nothing proves nothing.
    static let appLib = "func appSum(_ first: Int, _ second: Int) -> Int { first + second }\n"

    /// Three readers the fixture moves, and Print Statement, which reads no purity.
    static let probeRules: [RuleIdentifier] = [
        .pureFunctionCandidate, .pureClosureCandidate, .impureClosureInventory, .printStatement
    ]

    /// Every rule whose visitor declares a purity input.
    static var readers: Set<RuleIdentifier> { Set(PurityGateDeclarationTests.declaredRules) }

    @Test(
        "a rule that reads the purity reports nothing on a test suite's file; other rules still do",
        arguments: suiteFolders
    )
    func purityReadersSkipATestSuitesFile(suite: String) async throws {
        let factory = "\(suite)/Support/Factory.swift"
        let issues = try await PackagePurityFixtures.lint(
            ["Sources/App/Lib.swift": Self.appLib, factory: PackagePurityFixtures.probeFactory],
            ruleIdentifiers: Self.probeRules
        )
        let onFactory = issues.filter { $0.filePath == factory }
        // Judged without `Probe`, `probeValue` and the `probeTotals` closure were candidates, and
        // Impure Closure Inventory did not list the closure.
        #expect(onFactory.contains { Self.readers.contains($0.ruleName) } == false, "\(onFactory.map(\.message))")
        #expect(onFactory.contains { $0.ruleName == .printStatement }, "a rule that reads no purity fell silent")
        #expect(PackagePurityFixtures.symbols(issues).contains("appSum"), "the readers did not run")
    }

    @Test("the same file in a production folder is judged, with its own types")
    func theSameFileInProductionIsJudged() async throws {
        let factory = "prod/Support/Factory.swift"
        let issues = try await PackagePurityFixtures.lint(
            ["Sources/App/Lib.swift": Self.appLib, factory: PackagePurityFixtures.probeFactory],
            ruleIdentifiers: Self.probeRules
        )
        let onFactory = issues.filter { $0.filePath == factory }
        let symbols = PackagePurityFixtures.symbols(onFactory)
        #expect(symbols.contains("sentinelAdd"), "the readers did not report on the file")
        #expect(symbols.contains("probeValue") == false, "Probe's printing init did not refute")
        #expect(onFactory.contains { $0.ruleName == .impureClosureInventory })
        #expect(onFactory.contains { $0.ruleName == .pureClosureCandidate } == false)
        #expect(onFactory.contains { $0.ruleName == .printStatement })
    }

    @Test("a manifest is not judged either: no target compiles it, so the facts do not know its types")
    func purityReadersSkipAManifest() async throws {
        let manifest = """
        // swift-tools-version:5.9
        import PackageDescription

        func sentinelAdd(_ first: Int, _ second: Int) -> Int { first + second }

        let package = Package(name: "App", targets: [.target(name: "App")])
        """
        let issues = try await PackagePurityFixtures.lint(
            ["Package.swift": manifest, "Sources/App/Lib.swift": Self.appLib],
            ruleIdentifiers: [.pureFunctionCandidate]
        )
        let symbols = PackagePurityFixtures.symbols(issues)
        #expect(symbols.contains("appSum"), "the rule did not run")
        #expect(symbols.contains("sentinelAdd") == false)
    }

    /// The broad form of the first two, over the corpus that moves every purity consumer: the same
    /// package with its target's sources under `tests/Lib/` instead of `Sources/Lib/`.
    @Test("moved into a test suite's folder, a package loses exactly the readers' findings there")
    func onlyTheReadersFallSilentInASuite() async throws {
        func lint(placingLibAt folder: String) async throws -> [LintIssue] {
            var files: [String: String] = ["\(folder)Item.swift": PackagePurityFixtures.refutingItem]
            for (path, text) in PurityGateCorpus.files {
                files[path.replacingOccurrences(of: "Sources/Lib/", with: folder)] = text
            }
            return try await PackagePurityFixtures.lint(files, ruleIdentifiers: PurityGateDeclarationTests.ruleNames)
        }
        let production = try await lint(placingLibAt: "Sources/Lib/")
        let suite = try await lint(placingLibAt: "tests/Lib/")

        let readersInProduction = Set(production.filter {
            Self.readers.contains($0.ruleName) && $0.filePath.hasPrefix("Sources/Lib/")
        }.map(\.ruleName))
        // Per-file and cross-file readers, and one that reads the purity only for an exemption.
        #expect(readersInProduction.isSuperset(of: [
            .pureFunctionCandidate, .pureClosureCandidate, .impureClosureInventory, .couldBePrivate,
            .directInstantiation
        ]), "the corpus no longer moves the readers: \(readersInProduction)")
        let readersInSuite = suite.filter { Self.readers.contains($0.ruleName) && $0.filePath.hasPrefix("tests/") }
        #expect(readersInSuite.isEmpty, "\(PurityGateCorpus.rendered(readersInSuite))")

        func others(_ issues: [LintIssue]) -> [String] {
            PurityGateCorpus.rendered(issues.filter { !Self.readers.contains($0.ruleName) })
                .map { $0.replacingOccurrences(of: "tests/Lib/", with: "Sources/Lib/") }
                .sorted()
        }
        #expect(others(production).isEmpty == false, "no other rule reported, so their agreement proves nothing")
        #expect(others(suite) == others(production))
    }
}
