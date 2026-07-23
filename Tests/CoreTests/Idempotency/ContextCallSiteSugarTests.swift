import SwiftEffectInference
import SwiftParser
@testable import SwiftProjectLintVisitors
import SwiftSyntax
import Testing

/// The execution-context axis must survive call-site sugar, exactly as the effect axis does.
///
/// A declaration's label list names every parameter; a call site's names only what was written.
/// Keying the lookup on equality loses every call that omits a default or passes a trailing
/// closure — silently. On this axis that means the `once` contract simply evaporates: the rule
/// that exists to catch a re-runnable migration never fires. And because `applyOnceReachInference`
/// walks call sites too, a single miss does not drop one edge but *truncates the chain*, taking
/// every caller upstream of it with them.
///
/// Retry contexts are the worst possible place for this bug, because they are definitionally
/// closure-shaped: `withRetry { }`, `transaction { }`, `.run { }`.
@Suite("Context lookup survives call-site sugar")
struct ContextCallSiteSugarTests {

    private static func calls(in tree: SourceFileSyntax) -> [FunctionCallExprSyntax] {
        final class Collector: SyntaxVisitor {
            var found: [FunctionCallExprSyntax] = []
            override func visit(_ node: FunctionCallExprSyntax) -> SyntaxVisitorContinueKind {
                found.append(node)
                return .visitChildren
            }
        }
        let collector = Collector(viewMode: .sourceAccurate)
        collector.walk(tree)
        return collector.found
    }

    private func context(forCallTo name: String, in source: String) throws -> ContextEffect? {
        let tree = Parser.parse(source: source)
        let table = ContextSymbolTable.build(from: tree)
        let call = try #require(
            Self.calls(in: tree).first {
                $0.calledExpression.as(DeclReferenceExprSyntax.self)?.baseName.text == name
            }
        )
        return table.context(for: try #require(CallSiteShape.from(call: call)))
    }

    @Test("a once contract survives an omitted defaulted argument")
    func onceSurvivesOmittedDefault() throws {
        let source = """
        /// @lint.context once
        func migrate(schema: String, dryRun: Bool = false) {}

        func caller() {
            migrate(schema: "v2")
        }
        """

        #expect(try context(forCallTo: "migrate", in: source) == .once)
    }

    @Test("a replayable context survives a trailing closure")
    func replayableSurvivesTrailingClosure() throws {
        let source = """
        /// @lint.context replayable
        func withRetry(operation: () -> Void) {}

        func caller() {
            withRetry { }
        }
        """

        #expect(try context(forCallTo: "withRetry", in: source) == .replayable)
    }

    @Test("a context survives a trailing closure after ordinary arguments")
    func contextSurvivesTrailingClosureAfterArguments() throws {
        let source = """
        /// @lint.context strict_replayable
        func transaction(name: String, body: () -> Void) {}

        func caller() {
            transaction(name: "charge") { }
        }
        """

        #expect(try context(forCallTo: "transaction", in: source) == .strictReplayable)
    }

    // MARK: - Guard rails

    @Test("omitting a required argument still does not resolve")
    func requiredArgumentStillRequired() throws {
        let source = """
        /// @lint.context once
        func migrate(schema: String, target: String) {}

        func caller() {
            migrate(schema: "v2")
        }
        """

        #expect(try context(forCallTo: "migrate", in: source) == nil)
    }

    @Test("declarations that disagree still withdraw")
    func disagreeingDeclarationsWithdraw() throws {
        let source = """
        /// @lint.context once
        func run(step: Int, retries: Int = 0) {}

        /// @lint.context replayable
        func run(step: Int, backoff: Int = 0) {}

        func caller() {
            run(step: 1)
        }
        """

        // `run(step:)` could be either. Guessing is worse than silence.
        #expect(try context(forCallTo: "run", in: source) == nil)
    }
}
