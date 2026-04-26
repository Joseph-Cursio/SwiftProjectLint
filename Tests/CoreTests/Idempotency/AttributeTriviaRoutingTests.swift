import Testing
@testable import SwiftProjectLintIdempotencyRules
@testable import SwiftProjectLintVisitors
import SwiftSyntax
import SwiftParser

/// OI-7 regression suite: doc-comment annotations must be read regardless of
/// where they sit relative to attributes and modifiers on a function
/// declaration.
///
/// Background: `EffectAnnotationParser` originally read only
/// `FunctionDeclSyntax.leadingTrivia`. That trivia position contains only
/// content before the declaration's *first token*, which when attributes are
/// present is the first `@` — so a doc comment placed between `@available`
/// and `func` was silently dropped. The fix (commit introducing this suite)
/// combines trivia from every header position: decl leading, each attribute's
/// trailing, each modifier's leading, and the `func` keyword's leading. See
/// `docs/ideas/doc-comments-after-attributes.md` for the full discovery note.
@Suite
struct AttributeTriviaRoutingTests {

    // MARK: - Helpers

    private func tableFrom(_ source: String) -> EffectSymbolTable {
        EffectSymbolTable.build(from: Parser.parse(source: source))
    }

    private func runContext(_ source: String) -> NonIdempotentInRetryContextVisitor {
        let visitor = NonIdempotentInRetryContextVisitor(
            pattern: NonIdempotentInRetryContext().pattern
        )
        visitor.walk(Parser.parse(source: source))
        visitor.analyze()
        return visitor
    }

    private func runEffect(_ source: String) -> IdempotencyViolationVisitor {
        let visitor = IdempotencyViolationVisitor(
            pattern: IdempotencyViolation().pattern
        )
        visitor.walk(Parser.parse(source: source))
        visitor.analyze()
        return visitor
    }

    // MARK: - Symbol-table reads across orderings

    @Test
    func docBeforeAttribute_parses() {
        let source = """
        /// @lint.effect non_idempotent
        @available(macOS 13.0, *)
        func sink() async throws {}
        """
        let signature = FunctionSignature(name: "sink", argumentLabels: [])
        #expect(tableFrom(source).effect(for: signature) == .nonIdempotent)
    }

    @Test
    func docBetweenAttributeAndModifier_parses() {
        // The OI-7 failure shape: `///` sits after `@available` and before the
        // `public` modifier. Under the pre-fix parser this was routed to the
        // modifier's leading trivia and dropped. Now it must be picked up.
        let source = """
        @available(macOS 13.0, *)
        /// @lint.effect non_idempotent
        public func sink() async throws {}
        """
        let signature = FunctionSignature(name: "sink", argumentLabels: [])
        #expect(tableFrom(source).effect(for: signature) == .nonIdempotent)
    }

    @Test
    func docBetweenAttributeAndFuncKeyword_parses() {
        // Variant of the same ordering with no modifier: `///` lands on the
        // `func` keyword's leading trivia.
        let source = """
        @available(macOS 13.0, *)
        /// @lint.effect non_idempotent
        func sink() async throws {}
        """
        let signature = FunctionSignature(name: "sink", argumentLabels: [])
        #expect(tableFrom(source).effect(for: signature) == .nonIdempotent)
    }

    @Test
    func docBetweenTwoAttributes_parses() {
        // `///` between two attributes lands on the trailing trivia of the
        // first attribute (or leading trivia of the second — SwiftSyntax
        // routes this consistently, but we collect from both positions).
        let source = """
        @available(macOS 13.0, *)
        /// @lint.context replayable
        @MainActor
        func handler() async throws {}
        """
        let signature = FunctionSignature(name: "handler", argumentLabels: [])
        #expect(tableFrom(source).context(for: signature) == .replayable)
    }

    @Test
    func docsOnBothSidesOfAttribute_parserPicksFirst() {
        // When a user writes annotations both before and after an attribute,
        // source order wins: the parser returns the first match it finds while
        // traversing the combined trivia in declaration order.
        let source = """
        /// @lint.effect idempotent
        @available(macOS 13.0, *)
        /// @lint.effect non_idempotent
        func confused() async throws {}
        """
        let signature = FunctionSignature(name: "confused", argumentLabels: [])
        #expect(tableFrom(source).effect(for: signature) == .idempotent)
    }

    @Test
    func nonDocCommentAfterAttribute_ignored() {
        // Only `///` (doc-line) and `/** … */` (doc-block) comments are
        // annotation-bearing. A plain `//` or `/* … */` between attribute and
        // func must remain invisible to the parser, even with the expanded
        // trivia collection.
        let source = """
        @available(macOS 13.0, *)
        // @lint.effect non_idempotent  ← plain comment, must be ignored
        func sink() async throws {}
        """
        let signature = FunctionSignature(name: "sink", argumentLabels: [])
        #expect(tableFrom(source).effect(for: signature) == nil)
    }

    // MARK: - End-to-end diagnostics through the new resolution path

    @Test
    func replayableHandlerWithAttributeBeforeDoc_flagsNonIdempotentCall() throws {
        // Full round-trip: a `@context replayable` function whose context
        // annotation sits between `@available` and `func`, calling a
        // `non_idempotent` callee. Pre-fix: 0 diagnostics (context silently
        // dropped). Post-fix: 1 diagnostic.
        let source = """
        /// @lint.effect non_idempotent
        func sink() async throws {}

        @available(macOS 13.0, *)
        /// @lint.context replayable
        func handler() async throws {
            try await sink()
        }
        """
        let issues = runContext(source).detectedIssues
        #expect(issues.count == 1)
        let issue = try #require(issues.first)
        #expect(issue.message.contains("replayable"))
        #expect(issue.message.contains("sink"))
    }

    @Test
    func idempotentCallerWithAttributeBeforeDoc_flagsNonIdempotentCall() throws {
        // Same mechanism, different rule: `@lint.effect idempotent` declared
        // on a function between `@available` and `public func`.
        let source = """
        /// @lint.effect non_idempotent
        func sink() async throws {}

        @available(macOS 13.0, *)
        /// @lint.effect idempotent
        public func process() async throws {
            try await sink()
        }
        """
        let issues = runEffect(source).detectedIssues
        #expect(issues.count == 1)
        let issue = try #require(issues.first)
        #expect(issue.ruleName == .idempotencyViolation)
        #expect(issue.message.contains("process"))
        #expect(issue.message.contains("sink"))
    }
}
