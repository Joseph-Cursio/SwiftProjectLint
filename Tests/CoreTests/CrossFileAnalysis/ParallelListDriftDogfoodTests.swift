@testable import Core
import Foundation
import SwiftParser
@testable import SwiftProjectLintRules
import SwiftSyntax
import Testing

/// Runs `ParallelListDrift` over SwiftProjectLint's *own* sources — the case that
/// motivated the rule. `BuiltInRules.registerAll()` hand-registers one factory per
/// category while `PatternCategory` declares the categories as enum cases; the two
/// lists are meant to correspond, and the rule must notice where they do not.
///
/// This is a real-source regression test, not a synthetic one: it reads the checked-in
/// files, so if the two lists are ever reconciled (or drift further) the expectation
/// below documents which way it went.
@Suite
struct ParallelListDriftDogfoodTests {

    /// Repository root, derived from this file's location at compile time:
    /// `<root>/Tests/CoreTests/CrossFileAnalysis/<this file>` — up four levels.
    private static var repositoryRoot: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()   // CrossFileAnalysis
            .deletingLastPathComponent()   // CoreTests
            .deletingLastPathComponent()   // Tests
            .deletingLastPathComponent()   // repository root
    }

    private func analyze(realFiles: [String]) throws -> [LintIssue] {
        var cache: [String: SourceFileSyntax] = [:]
        for relative in realFiles {
            let absolute = Self.repositoryRoot.appendingPathComponent(relative).path
            let source = try String(contentsOfFile: absolute, encoding: .utf8)
            cache[relative] = Parser.parse(source: source)
        }
        let visitor = ParallelListDriftVisitor(fileCache: cache)
        visitor.setPattern(ParallelListDrift().pattern)
        for (name, ast) in cache {
            visitor.setFilePath(name)
            visitor.setSourceLocationConverter(SourceLocationConverter(fileName: name, tree: ast))
            visitor.walk(ast)
        }
        visitor.finalizeAnalysis()
        return visitor.detectedIssues.filter { $0.ruleName == .parallelListDrift }
    }

    @Test("registerAll() is flagged as drifted from PatternCategory")
    func registerAllDriftsFromPatternCategory() throws {
        let issues = try analyze(realFiles: [
            "Packages/SwiftProjectLintRules/Sources/SwiftProjectLintRules/BuiltInRules.swift",
            "Packages/SwiftProjectLintModels/Sources/SwiftProjectLintModels/PatternCategory.swift"
        ])

        let onRegisterAll = try #require(issues.first { $0.filePath.hasSuffix("BuiltInRules.swift") })
        // `idempotency` is registered by a separate package and `other` is a catch-all —
        // both legitimate, and both exactly what a human should be asked to confirm.
        #expect(onRegisterAll.message.contains("idempotency"))
        #expect(onRegisterAll.message.contains("other"))
        #expect(onRegisterAll.message.contains("registration run"))
    }
}
