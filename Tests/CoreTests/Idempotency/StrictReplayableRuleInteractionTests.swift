import SwiftParser
@testable import SwiftProjectLintIdempotencyRules
import SwiftProjectLintModels
import SwiftProjectLintVisitors
import SwiftSyntax
import Testing

/// Cross-rule interaction: strict_replayable + declared non-idempotent callee
/// should fire ONLY the existing rule (never double-fire).
@Suite
struct StrictReplayableRuleInteractionTests {

    @Test
    func strictCallsDeclaredNonIdempotent_onlyExistingRuleFires() {
        let source = """
        /// @lint.effect non_idempotent
        func insert(_ id: Int) async throws {}

        /// @lint.context strict_replayable
        func handle(_ id: Int) async throws {
            try await insert(id)
        }
        """

        let sourceFile = Parser.parse(source: source)

        let existingVisitor = NonIdempotentInRetryContextVisitor(
            pattern: NonIdempotentInRetryContext().pattern
        )
        existingVisitor.walk(sourceFile)
        existingVisitor.analyze()

        let newVisitor = UnannotatedStrictReplayableVisitor(
            pattern: UnannotatedInStrictReplayableContext().pattern
        )
        newVisitor.walk(sourceFile)
        newVisitor.analyze()

        #expect(existingVisitor.detectedIssues.count == 1)
        #expect(existingVisitor.detectedIssues.first?.ruleName == .nonIdempotentInRetryContext)
        #expect(existingVisitor.detectedIssues.first?.message.contains("strict_replayable") == true)
        #expect(newVisitor.detectedIssues.isEmpty)
    }

    @Test
    func strictCallsUnannotated_onlyNewRuleFires() {
        let source = """
        func mystery() async throws {}

        /// @lint.context strict_replayable
        func handle() async throws {
            try await mystery()
        }
        """

        let sourceFile = Parser.parse(source: source)

        let existingVisitor = NonIdempotentInRetryContextVisitor(
            pattern: NonIdempotentInRetryContext().pattern
        )
        existingVisitor.walk(sourceFile)
        existingVisitor.analyze()

        let newVisitor = UnannotatedStrictReplayableVisitor(
            pattern: UnannotatedInStrictReplayableContext().pattern
        )
        newVisitor.walk(sourceFile)
        newVisitor.analyze()

        #expect(existingVisitor.detectedIssues.isEmpty)
        #expect(newVisitor.detectedIssues.count == 1)
        #expect(newVisitor.detectedIssues.first?.ruleName == .unannotatedInStrictReplayableContext)
    }
}
