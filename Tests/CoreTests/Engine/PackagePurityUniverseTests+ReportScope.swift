@testable import Core
import Foundation
import Testing

/// What the facts were not built from, the rules that read them do not report on.
///
/// A test suite's folder — `test/`, `tests/`, `validation-test/` — is out of the universe but
/// reported as production. Its files were judged without the types they declare, and constructing a
/// type the facts do not know is judged pure: `probeValue`, building a `Probe` whose initializer
/// prints, was a Pure Function Property-Test Candidate under `tests/` and nothing under `prod/`.
/// `ProjectLinter.withinPurityScope` now drops the readers' findings on such a file, and only theirs;
/// on a manifest and a file that is not UTF-8 too, which the universe leaves out wherever they sit.
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

    @Test("every visitor that declares a purity input reports one rule, so the scope silences only readers")
    func everyPurityReadingVisitorReportsOneRule() {
        // The scope takes a reader by its visitor's declaration, and a visitor registered for
        // several rules would take every one of them off the files the facts leave out, including
        // a rule that reads none of the purity. None does today; one that should is a design call.
        let declaring = PurityGateDeclarationTests.registered.filter { !$0.packagePurityInputs.isEmpty }
        let rulesByVisitor = Dictionary(grouping: declaring) { ObjectIdentifier($0.visitor) }
            .mapValues { Set($0.map(\.name)) }
        let shared = rulesByVisitor.values.filter { $0.count > 1 }.map { $0.map(\.rawValue).sorted() }
        #expect(shared.isEmpty, "one visitor declares a purity input for several rules: \(shared)")
        #expect(Set(rulesByVisitor.values.joined()) == Self.readers)
    }

    @Test("a reported file the universe drops for its encoding is not judged: its own types are not in the facts")
    func purityReadersSkipAFileThatIsNotUTF8() async throws {
        // `swiftc` rejects a UTF-16 source, so the universe leaves it out (amendment C) wherever it
        // sits, while the lenient read still reports on it. Its path alone says production; the
        // run's facts say otherwise, and they decide.
        let factory = "Sources/App/Factory.swift"
        func lint(_ text: Data) async throws -> [LintIssue] {
            let root = try PackagePurityFixtures.makeProject(["Sources/App/Lib.swift": Self.appLib])
            defer { try? FileManager.default.removeItem(atPath: root) }
            try text.write(to: URL(fileURLWithPath: root).appendingPathComponent(factory))
            return await ProjectLinter().analyzeProject(
                at: root,
                ruleIdentifiers: Self.probeRules,
                detector: PatternRegistryFactory.createConfiguredSystem().detector
            )
        }
        let utf16 = try #require(PackagePurityFixtures.probeFactory.data(using: .utf16))
        #expect(utf16.starts(with: [0xFF, 0xFE]) || utf16.starts(with: [0xFE, 0xFF]), "no byte-order mark")
        let control = try await lint(Data(PackagePurityFixtures.probeFactory.utf8))
        let issues = try await lint(utf16)

        let judged = control.filter { $0.filePath == factory }
        #expect(PackagePurityFixtures.symbols(judged).contains("sentinelAdd"), "control: UTF-8 here is judged")
        let onFactory = issues.filter { $0.filePath == factory }
        #expect(onFactory.contains { Self.readers.contains($0.ruleName) } == false, "\(onFactory.map(\.message))")
        #expect(onFactory.contains { $0.ruleName == .printStatement }, "the lenient read no longer reports on it")
        #expect(PackagePurityFixtures.symbols(issues).contains("appSum"), "the readers did not run")
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
