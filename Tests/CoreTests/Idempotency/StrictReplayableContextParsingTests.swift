import Testing
@testable import SwiftProjectLintVisitors
import SwiftSyntax
import SwiftParser

/// Parsing-level coverage for `/// @lint.context strict_replayable`. The
/// visitor-level behaviour (new diagnostic firing on unannotated callees)
/// is covered by `UnannotatedInStrictReplayableContextVisitorTests`.
///
/// Round-9 / phase-2 strict-replayable slice. See
/// `docs/claude_phase_2_strict_replayable_plan.md`.
@Suite
struct StrictReplayableContextParsingTests {

    private func firstFunctionDecl(in source: String) throws -> FunctionDeclSyntax {
        final class Finder: SyntaxVisitor {
            var decl: FunctionDeclSyntax?
            init() { super.init(viewMode: .sourceAccurate) }
            override func visit(_ node: FunctionDeclSyntax) -> SyntaxVisitorContinueKind {
                if decl == nil { decl = node }
                return .skipChildren
            }
        }
        let finder = Finder()
        finder.walk(Parser.parse(source: source))
        return try #require(finder.decl)
    }

    private func allFunctionDecls(in source: String) -> [FunctionDeclSyntax] {
        final class Finder: SyntaxVisitor {
            var decls: [FunctionDeclSyntax] = []
            init() { super.init(viewMode: .sourceAccurate) }
            override func visit(_ node: FunctionDeclSyntax) -> SyntaxVisitorContinueKind {
                decls.append(node)
                return .skipChildren
            }
        }
        let finder = Finder()
        finder.walk(Parser.parse(source: source))
        return finder.decls
    }

    private func firstVariableDecl(in source: String) throws -> VariableDeclSyntax {
        final class Finder: SyntaxVisitor {
            var decl: VariableDeclSyntax?
            init() { super.init(viewMode: .sourceAccurate) }
            override func visit(_ node: VariableDeclSyntax) -> SyntaxVisitorContinueKind {
                if decl == nil { decl = node }
                return .skipChildren
            }
        }
        let finder = Finder()
        finder.walk(Parser.parse(source: source))
        return try #require(finder.decl)
    }

    @Test
    func contextAnnotation_strictReplayable_parses_onFunction() throws {
        let decl = try firstFunctionDecl(
            in: """
            /// @lint.context strict_replayable
            func handle(_ event: String) async throws {}
            """
        )
        #expect(EffectAnnotationParser.parseContext(declaration: decl) == .strictReplayable)
    }

    @Test
    func contextAnnotation_strictReplayable_parses_onClosureBinding() throws {
        let decl = try firstVariableDecl(
            in: """
            /// @lint.context strict_replayable
            let handler = { event in print(event) }
            """
        )
        #expect(EffectAnnotationParser.parseContext(declaration: decl) == .strictReplayable)
    }

    @Test
    func contextAnnotation_strictReplayable_distinctFromReplayable() {
        let decls = allFunctionDecls(
            in: """
            /// @lint.context replayable
            func relaxed() {}
            /// @lint.context strict_replayable
            func strict() {}
            """
        )
        #expect(decls.count == 2)
        #expect(EffectAnnotationParser.parseContext(declaration: decls[0]) == .replayable)
        #expect(EffectAnnotationParser.parseContext(declaration: decls[1]) == .strictReplayable)
    }

    @Test
    func contextAnnotation_unknownVariant_returnsNil() throws {
        let decl = try firstFunctionDecl(
            in: """
            /// @lint.context ultra_strict_replayable
            func handle() {}
            """
        )
        #expect(EffectAnnotationParser.parseContext(declaration: decl) == nil)
    }

    @Test
    func contextAnnotation_strictReplayable_withTrailingContent_stillParses() throws {
        // The parser reads only the first whitespace-separated token after
        // `@lint.context`, so trailing content is tolerated. Documents
        // present behaviour rather than enforcing a specific policy.
        let decl = try firstFunctionDecl(
            in: """
            /// @lint.context strict_replayable reason: "SQS at-least-once"
            func handle() {}
            """
        )
        #expect(EffectAnnotationParser.parseContext(declaration: decl) == .strictReplayable)
    }
}
