@testable import Core
import Foundation
@testable import SwiftProjectLintEngine
@testable import SwiftProjectLintVisitors
import Testing

extension PurityGateDeclarationTests {
    // MARK: - The run

    @Test("a narrow run builds nothing: no universe walk, and the purity is withheld")
    func narrowRunWithholds() async throws {
        let path = try PurityGateCorpus.makeProject()
        defer { try? FileManager.default.removeItem(atPath: path) }
        let linter = ProjectLinter()
        let gated = await linter.discoverFiles(at: path, configuration: .default, resolvingUniverse: false)
        let open = await linter.discoverFiles(at: path, configuration: .default)
        #expect(gated.constructionUniverse == nil, "not resolved, which is not the same as empty")
        let stamp = open.constructionUniverse?.contains { $0.hasSuffix("Stamp.swift") }
        #expect(stamp == true, "the nested package fell out")
        #expect(gated.reportable == open.reportable)

        let tripwire = PurityTripwire()
        let parse = await ProjectLinter.sharedParse(gated, projectRoot: path, withholdingBy: tripwire)
        #expect(parse.purity.isWithheld)
        #expect(parse.judged == nil, "a withheld table was built from no files, which is not the same as none")
        #expect(parse.analysable.keys.contains { $0.hasSuffix("Stamp.swift") } == false)
        #expect(tripwire.recorded.isEmpty)

        // A resolved universe that holds nothing builds an empty table; it is not withheld.
        let empty = ProjectLinter.DiscoveredFiles(reportable: [], evidenceOnly: [], constructionUniverse: [])
        let built = await ProjectLinter.sharedParse(empty, projectRoot: path, withholdingBy: tripwire)
        #expect(built.purity.isWithheld == false)
        #expect(built.judged?.isEmpty == true, "a resolved universe that holds nothing was built from no file")
    }

    @Test("a run narrowed by flags or by configuration takes no universe walk; one that reads purity does")
    func narrowRunsSkipTheUniverseWalk() async throws {
        let path = try PurityGateCorpus.makeProject()
        defer { try? FileManager.default.removeItem(atPath: path) }
        func walks(_ rules: [RuleIdentifier]?, _ configuration: LintConfiguration = .default) async -> [Bool] {
            let discovery = RecordingDiscovery()
            _ = await ProjectLinter(fileDiscovery: discovery) { CrossFileAnalysisEngine(registry: $0) }
                .lint(
                    at: path, targetType: .auto, categories: nil, ruleIdentifiers: rules,
                    detector: PatternRegistryFactory.createConfiguredSystem().detector,
                    configuration: configuration
                )
            return discovery.nestedFlags
        }
        #expect(await walks([.forceTry, .printStatement]) == [false])
        #expect(await walks([.forceTry, .directInstantiation]) == [false, true])
        #expect(await walks(nil, LintConfiguration(enabledOnlyRules: [.forceTry, .printStatement])) == [false])
        #expect(await walks(nil, LintConfiguration(disabledRules: [.forceTry])) == [false, true])
    }

    @Test("a tripped run that is cancelled meanwhile still never returns the first pass's findings")
    func cancelledTrippedRunNeverReturnsTheFirstPass() async throws {
        let path = try PurityGateCorpus.makeProject()
        defer { try? FileManager.default.removeItem(atPath: path) }
        let registry = PatternVisitorRegistry()
        registry.register(pattern: SyntaxPattern(
            name: .couldBePrivate, visitor: CancellingUndeclaredReader.self, severity: .info,
            category: .codeQuality, messageTemplate: "read", suggestion: "", description: "test reader"
        ))
        // Its own task, so the reader cancels the lint and not the test.
        let detector = SourcePatternDetector(registry: registry)
        let run = await Task {
            await PurityGateCorpus.lint(at: path, rules: [.couldBePrivate], detector: detector)
        }.value
        #expect(run.trips.isEmpty == false)
        // Pass 1 judged without the table, counted the `Item` closure pure, and cancelled the run.
        // Its finding must not survive, whatever the cancelled rerun manages to report.
        let firstPass = try #require(CancellingUndeclaredReader.emitted.all.first, "pass 1 reported nothing")
        #expect(run.issues.contains { $0.message == firstPass } == false, "\(run.issues.map(\.message))")
    }

    @Test("the caller's detector never keeps a purity catalog a run withheld")
    func theCallersDetectorKeepsNoPurityCatalog() async throws {
        let path = try PurityGateCorpus.makeProject()
        defer { try? FileManager.default.removeItem(atPath: path) }
        let detector = PatternRegistryFactory.createConfiguredSystem().detector
        let run = await PurityGateCorpus.lint(at: path, rules: [.forceTry], detector: detector)
        #expect(run.demand.inputs.isEmpty)
        #expect(detector.knownCleanInstanceMethods.isWithheld == false)
        #expect(detector.knownImpurePackageFunctions.isWithheld == false)
    }

    @Test("a rerun is reported to the linter's notice, naming what was read")
    func rerunIsReported() async throws {
        let path = try PurityGateCorpus.makeProject()
        defer { try? FileManager.default.removeItem(atPath: path) }
        let notices = NoticeBox()
        _ = await ProjectLinter { notices.append($0) }.lint(
            at: path, targetType: .auto, categories: nil, ruleIdentifiers: [.printStatement],
            detector: UndeclaredReader.oracle.detector(), configuration: .default
        )
        #expect(notices.all.count == 1)
        #expect(notices.all.first?.contains("PurityInferrer()") == true, "\(notices.all)")
    }
}
