import Foundation
import SwiftEffectInference
import SwiftParser
@testable import SwiftProjectLintIdempotencyRules
import SwiftProjectLintModels
@testable import SwiftProjectLintVisitors
import SwiftSyntax
import Testing

/// The idempotency rules share one effect table per run.
///
/// Four rules resolve callees through an `EffectSymbolTable`. Each used to build its own, and
/// three ran upward inference on it separately, each pass bounded by its own wall-clock budget, so
/// one run could judge the same callee differently in different rules. The cross-file engine now
/// builds a `ProjectEffectTables` once and hands it to every visitor.
@Suite("Idempotency — one effect table per run")
struct SharedEffectTableTests {

    /// Two files that give each of the four rules something to report, partly through a two-hop
    /// upward chain that crosses files: `zorkRelay` → `zorkHelper` → the declared `zorkInsert`.
    /// The names mean nothing to the heuristic, so only the table can grade them.
    private static let files = [
        "Leaf.swift": """
        /// @lint.effect non_idempotent
        func zorkInsert(_ value: Int) {}
        func zorkHelper() { zorkInsert(1) }
        func zorkRelay() { zorkHelper() }

        /// @lint.effect externally_idempotent(by: idempotencyKey)
        func charge(idempotencyKey: String, amount: Int) async throws {}
        """,
        "Callers.swift": """
        import Foundation

        /// @lint.effect idempotent
        func syncAll() { zorkRelay() }

        /// @lint.context replayable
        func handleWebhook(amount: Int) async throws {
            zorkRelay()
            try await charge(idempotencyKey: UUID().uuidString, amount: amount)
        }

        /// @lint.context strict_replayable
        func handleStrict() async throws {
            mysteryCall()
        }
        """,
    ]

    private static let rules: [RuleIdentifier] = [
        .idempotencyViolation, .nonIdempotentInRetryContext,
        .missingIdempotencyKey, .unannotatedInStrictReplayableContext,
    ]

    /// What identifies a finding, for comparing runs.
    private struct Finding: Hashable, CustomStringConvertible {
        let rule: RuleIdentifier
        let file: String
        let line: Int
        let message: String

        init(_ issue: LintIssue) {
            rule = issue.ruleName
            file = URL(fileURLWithPath: issue.filePath).lastPathComponent
            line = issue.lineNumber
            message = issue.message
        }

        var description: String { "\(rule.rawValue) \(file):\(line)" }
    }

    @Test("the four rules run together report exactly what each reports alone")
    func togetherMatchesAlone() async throws {
        var alone: [Finding] = []
        for rule in Self.rules {
            let found = try await PackagePurityFixtures.lint(Self.files, ruleIdentifiers: [rule])
            #expect(found.isEmpty == false, "\(rule.rawValue) found nothing, so the comparison proves little")
            alone += found.map(Finding.init)
        }
        let together = try await PackagePurityFixtures.lint(Self.files, ruleIdentifiers: Self.rules)
            .map(Finding.init)

        #expect(Set(together) == Set(alone))
        #expect(together.count == alone.count)
    }

    @Test("a visitor handed the run's tables reads them instead of building its own")
    func visitorsReadTheSharedTables() throws {
        let leaf = try #require(Self.files["Leaf.swift"])
        let callers = try #require(Self.files["Callers.swift"])
        // Built from Leaf.swift alone: the visitors below are walked over Callers.swift only, so
        // any grade they find for a `zork` callee or for `charge` came from these tables.
        let tables = ProjectEffectTables(sources: [Parser.parse(source: leaf)], enabledFrameworks: nil)
        let callersTree = Parser.parse(source: callers)

        func run(_ visitor: some CrossFileVisitorBase & CrossFilePatternVisitorProtocol) -> [LintIssue] {
            visitor.sharedEffectTables = tables
            visitor.setFilePath("Callers.swift")
            visitor.setSourceLocationConverter(SourceLocationConverter(fileName: "Callers.swift", tree: callersTree))
            visitor.walk(callersTree)
            visitor.finalizeAnalysis()
            return visitor.detectedIssues
        }
        let cache = ["Callers.swift": callersTree]

        let violation = run(IdempotencyViolationVisitor(fileCache: cache))
        #expect(violation.contains { $0.ruleName == .idempotencyViolation && $0.message.contains("zorkRelay") })

        let retry = run(NonIdempotentInRetryContextVisitor(fileCache: cache))
        #expect(retry.contains { $0.ruleName == .nonIdempotentInRetryContext && $0.message.contains("zorkRelay") })

        let missingKey = run(MissingIdempotencyKeyVisitor(fileCache: cache))
        #expect(missingKey.contains { $0.ruleName == .missingIdempotencyKey && $0.message.contains("charge") })
    }

    @Test("a directly driven visitor still learns declarations from the files it walks")
    func directDriveBuildsItsOwnTables() throws {
        let source = """
        /// @lint.effect non_idempotent
        func zorkInsert(_ value: Int) {}

        /// @lint.effect idempotent
        func syncAll() { zorkInsert(1) }
        """
        let visitor = IdempotencyViolationVisitor(pattern: IdempotencyViolation().pattern)
        visitor.walk(Parser.parse(source: source))
        visitor.finalizeAnalysis()

        #expect(visitor.sharedEffectTables == nil)
        #expect(visitor.detectedIssues.contains { $0.message.contains("zorkInsert") })
    }

    @Test("upward inference leaves declared lookups as they were")
    func inferredKeepsDeclaredAnswers() throws {
        let leaf = try #require(Self.files["Leaf.swift"])
        let tables = ProjectEffectTables(sources: [Parser.parse(source: leaf)], enabledFrameworks: nil)
        let insert = FunctionSignature(name: "zorkInsert", argumentLabels: ["_"])
        let relay = FunctionSignature(name: "zorkRelay", argumentLabels: [])

        #expect(tables.declared.effect(for: CallSiteShape(signature: insert)) == .nonIdempotent)
        #expect(tables.inferred.effect(for: CallSiteShape(signature: insert)) == .nonIdempotent)
        #expect(tables.declared.upwardInference(for: relay) == nil)
        #expect(tables.inferred.upwardInference(for: relay)?.effect == .nonIdempotent)
        #expect(tables.inferred.upwardInference(for: relay)?.depth == 2)
    }
}
