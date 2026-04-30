import Testing
@testable import SwiftProjectLintVisitors
import SwiftSyntax
import SwiftParser

/// Phase-2 third-slice: closure-binding annotation parsing. Exercises
/// `EffectAnnotationParser` on `VariableDeclSyntax` and the accompanying
/// `VariableDeclSyntax.closureInitializer` / `.firstBindingName` helpers.
@Suite
struct ClosureBindingAnnotationParserTests {

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

    // MARK: - closureInitializer recognition

    @Test
    func letBindingWithClosure_exposesClosureInitializer() throws {
        let decl = try firstVariableDecl(
            in: "let handler: @Sendable () -> Void = { print(\"hi\") }"
        )
        #expect(decl.closureInitializer != nil)
        #expect(decl.firstBindingName == "handler")
    }

    @Test
    func varBindingWithClosure_exposesClosureInitializer() throws {
        let decl = try firstVariableDecl(in: "var handler = { print(\"hi\") }")
        #expect(decl.closureInitializer != nil)
        #expect(decl.firstBindingName == "handler")
    }

    @Test
    func multiBindingDecl_hasNoClosureInitializer() throws {
        // Swift permits `let a = {}, b = {}` — annotation attachment is
        // ambiguous in this shape, so the helper returns nil.
        let decl = try firstVariableDecl(in: "let a = {}, b = {}")
        #expect(decl.closureInitializer == nil)
        #expect(decl.firstBindingName == nil)
    }

    @Test
    func nonClosureInitializer_hasNoClosureInitializer() throws {
        let decl = try firstVariableDecl(in: "let count = 42")
        #expect(decl.closureInitializer == nil)
        #expect(decl.firstBindingName == "count")
    }

    @Test
    func uninitializedLet_hasNoClosureInitializer() throws {
        let decl = try firstVariableDecl(in: "let handler: (() -> Void)? = nil")
        #expect(decl.closureInitializer == nil)
        #expect(decl.firstBindingName == "handler")
    }

    // MARK: - parseContext(declaration:) on VariableDeclSyntax

    @Test
    func contextAnnotation_aboveLetClosure_parses() throws {
        let decl = try firstVariableDecl(
            in: """
            /// @lint.context replayable
            let handler = { event in print(event) }
            """
        )
        #expect(ContextAnnotationParser.parseContext(declaration: decl) == .replayable)
    }

    @Test
    func contextAnnotation_retrySafe_parses() throws {
        let decl = try firstVariableDecl(
            in: """
            /// @lint.context retry_safe
            let handler = { event in print(event) }
            """
        )
        #expect(ContextAnnotationParser.parseContext(declaration: decl) == .retrySafe)
    }

    @Test
    func contextAnnotation_once_parses() throws {
        let decl = try firstVariableDecl(
            in: """
            /// @lint.context once
            let handler = { event in print(event) }
            """
        )
        #expect(ContextAnnotationParser.parseContext(declaration: decl) == .once)
    }

    @Test
    func noAnnotation_returnsNil() throws {
        let decl = try firstVariableDecl(in: "let handler = { event in print(event) }")
        #expect(ContextAnnotationParser.parseContext(declaration: decl) == nil)
        #expect(EffectAnnotationParser.parseEffect(declaration: decl) == nil)
    }

    // MARK: - parseEffect(declaration:) on VariableDeclSyntax

    @Test
    func effectAnnotation_nonIdempotent_parses() throws {
        let decl = try firstVariableDecl(
            in: """
            /// @lint.effect non_idempotent
            let sender = { message in send(message) }
            """
        )
        #expect(EffectAnnotationParser.parseEffect(declaration: decl) == .nonIdempotent)
    }

    @Test
    func effectAnnotation_observational_parses() throws {
        let decl = try firstVariableDecl(
            in: """
            /// @lint.effect observational
            let audit = { event in print(event) }
            """
        )
        #expect(EffectAnnotationParser.parseEffect(declaration: decl) == .observational)
    }

    // MARK: - Trivia-combining: annotation between attributes / modifiers

    @Test
    func annotationBetweenAttributes_parses() throws {
        let decl = try firstVariableDecl(
            in: """
            @available(macOS 13.0, *)
            /// @lint.context replayable
            public let handler = { event in print(event) }
            """
        )
        #expect(ContextAnnotationParser.parseContext(declaration: decl) == .replayable)
    }

    @Test
    func annotationBeforeModifier_parses() throws {
        let decl = try firstVariableDecl(
            in: """
            /// @lint.context replayable
            public let handler = { event in print(event) }
            """
        )
        #expect(ContextAnnotationParser.parseContext(declaration: decl) == .replayable)
    }

    // MARK: - Stored property on a type declaration

    @Test
    func storedPropertyClosure_inClass_parses() throws {
        // Walk explicitly — the first VariableDeclSyntax we hit is the
        // stored property, not the enclosing class decl.
        final class Finder: SyntaxVisitor {
            var decl: VariableDeclSyntax?
            init() { super.init(viewMode: .sourceAccurate) }
            override func visit(_ node: VariableDeclSyntax) -> SyntaxVisitorContinueKind {
                if decl == nil { decl = node }
                return .skipChildren
            }
        }
        let source = """
        class C {
            /// @lint.context replayable
            let handler: @Sendable () -> Void = { print("hi") }
        }
        """
        let finder = Finder()
        finder.walk(Parser.parse(source: source))
        let decl = try #require(finder.decl)
        #expect(ContextAnnotationParser.parseContext(declaration: decl) == .replayable)
        #expect(decl.closureInitializer != nil)
        #expect(decl.firstBindingName == "handler")
    }
}
