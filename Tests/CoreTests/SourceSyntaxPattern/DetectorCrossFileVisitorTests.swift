@testable import Core
import SwiftParser
import SwiftSyntax
import Testing

/// Cross-file rules belong to `CrossFileAnalysisEngine`, not to the per-file detector.
///
/// A cross-file visitor reports from `finalizeAnalysis()`, once every file has been walked, and
/// only the engine calls that. The detector used to walk every cross-file visitor over every file
/// anyway and then discard what it had collected — roughly thirty extra walks per file in a real
/// run, for findings nobody would ever see. The engine then walked the same visitors again.
///
/// The spy below reports *during* the walk, which no real cross-file visitor does, so that a walk
/// is observable: any issue it produces through the detector means the detector walked it.
@Suite
struct DetectorCrossFileVisitorTests {

    final class WalkReportingCrossFileVisitor: CrossFileVisitorBase, CrossFilePatternVisitorProtocol {
        override func visit(_ node: SourceFileSyntax) -> SyntaxVisitorContinueKind {
            addIssue(node: Syntax(node))
            return .skipChildren
        }

        func finalizeAnalysis() { /* reports during the walk instead */ }
    }

    private static let spyPattern = SyntaxPattern(
        name: .couldBePrivate,
        visitor: WalkReportingCrossFileVisitor.self,
        severity: .info,
        category: .codeQuality,
        messageTemplate: "walked",
        suggestion: "",
        description: "Reports once per walked file"
    )

    private static func makeRegistry() -> PatternVisitorRegistry {
        let registry = PatternVisitorRegistry()
        registry.register(pattern: spyPattern)
        return registry
    }

    private static let source = "struct Walked {}"

    @Test func detectorDoesNotWalkCrossFileVisitorsByRule() {
        let detector = SourcePatternDetector(registry: Self.makeRegistry())
        let issues = detector.detectPatterns(
            in: Self.source,
            filePath: "Sources/Walked.swift",
            ruleIdentifiers: [.couldBePrivate]
        )
        #expect(issues.isEmpty)
    }

    @Test func detectorDoesNotWalkCrossFileVisitorsByCategory() {
        let detector = SourcePatternDetector(registry: Self.makeRegistry())
        let issues = detector.detectPatterns(
            in: Self.source,
            filePath: "Sources/Walked.swift",
            categories: [.codeQuality]
        )
        #expect(issues.isEmpty)
    }

    @Test func engineStillWalksCrossFileVisitors() {
        let engine = CrossFileAnalysisEngine(registry: Self.makeRegistry())
        let file = ProjectFile(name: "Walked.swift", content: Self.source, relativePath: "Sources/Walked.swift")
        let issues = engine.detectCrossFilePatterns(projectFiles: [file], ruleIdentifiers: [.couldBePrivate])
        #expect(issues.map(\.message) == ["walked"])
    }
}
