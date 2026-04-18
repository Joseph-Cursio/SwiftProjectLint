import Testing
@testable import SwiftProjectLintVisitors
import SwiftSyntax
import SwiftParser

/// Tests that `EffectAnnotationParser` recognises attribute-form
/// annotations (`@Idempotent`, `@NonIdempotent`, `@Observational`,
/// `@ExternallyIdempotent(by:)`) in addition to the doc-comment form
/// (`/// @lint.effect <tier>`).
///
/// Verifies both per-form behaviour and the collision-withdraw semantics
/// when both forms disagree on the same declaration.
@Suite
struct AttributeFormAnnotationTests {

    private func firstFunction(in source: String) throws -> FunctionDeclSyntax {
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

    private func firstVariable(in source: String) throws -> VariableDeclSyntax {
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

    // MARK: - Attribute form on function declarations

    @Test
    func idempotentAttribute_onFunction_parses() throws {
        let decl = try firstFunction(in: """
        @Idempotent
        func foo() {}
        """)
        #expect(EffectAnnotationParser.parseEffect(declaration: decl) == .idempotent)
    }

    @Test
    func nonIdempotentAttribute_onFunction_parses() throws {
        let decl = try firstFunction(in: """
        @NonIdempotent
        func send() {}
        """)
        #expect(EffectAnnotationParser.parseEffect(declaration: decl) == .nonIdempotent)
    }

    @Test
    func observationalAttribute_onFunction_parses() throws {
        let decl = try firstFunction(in: """
        @Observational
        func logEvent() {}
        """)
        #expect(EffectAnnotationParser.parseEffect(declaration: decl) == .observational)
    }

    @Test
    func externallyIdempotentAttribute_withByLabel_parses() throws {
        let decl = try firstFunction(in: """
        @ExternallyIdempotent(by: "idempotencyKey")
        func charge(amount: Int, idempotencyKey: String) {}
        """)
        #expect(
            EffectAnnotationParser.parseEffect(declaration: decl)
                == .externallyIdempotent(keyParameter: "idempotencyKey")
        )
    }

    @Test
    func externallyIdempotentAttribute_withoutArguments_parses() throws {
        let decl = try firstFunction(in: """
        @ExternallyIdempotent
        func send() {}
        """)
        #expect(
            EffectAnnotationParser.parseEffect(declaration: decl)
                == .externallyIdempotent(keyParameter: nil)
        )
    }

    @Test
    func externallyIdempotentAttribute_withEmptyString_parsesAsNil() throws {
        // Empty-string "by:" normalises to nil — matches the macro's default
        // argument behaviour where `@ExternallyIdempotent` without an
        // argument is equivalent to `@ExternallyIdempotent(by: "")`.
        let decl = try firstFunction(in: """
        @ExternallyIdempotent(by: "")
        func send() {}
        """)
        #expect(
            EffectAnnotationParser.parseEffect(declaration: decl)
                == .externallyIdempotent(keyParameter: nil)
        )
    }

    // MARK: - Attribute form on variable declarations (closure bindings)

    @Test
    func idempotentAttribute_onLetBinding_parses() throws {
        let decl = try firstVariable(in: """
        @Idempotent
        let handler: () -> Void = {}
        """)
        #expect(EffectAnnotationParser.parseEffect(declaration: decl) == .idempotent)
    }

    @Test
    func nonIdempotentAttribute_onVarBinding_parses() throws {
        let decl = try firstVariable(in: """
        @NonIdempotent
        var sender: () -> Void = {}
        """)
        #expect(EffectAnnotationParser.parseEffect(declaration: decl) == .nonIdempotent)
    }

    // MARK: - Unknown attributes are ignored

    @Test
    func unrelatedAttribute_isIgnored() throws {
        let decl = try firstFunction(in: """
        @MainActor
        func foo() {}
        """)
        #expect(EffectAnnotationParser.parseEffect(declaration: decl) == nil)
    }

    @Test
    func availableAttribute_doesNotInterfere() throws {
        let decl = try firstFunction(in: """
        @available(macOS 13.0, *)
        @Idempotent
        func foo() {}
        """)
        #expect(EffectAnnotationParser.parseEffect(declaration: decl) == .idempotent)
    }

    // MARK: - Both forms present

    @Test
    func bothForms_agreeing_returnsThatTier() throws {
        let decl = try firstFunction(in: """
        /// @lint.effect idempotent
        @Idempotent
        func foo() {}
        """)
        #expect(EffectAnnotationParser.parseEffect(declaration: decl) == .idempotent)
    }

    @Test
    func bothForms_disagreeing_withdrawsViaCollisionPolicy() throws {
        // Doc comment says idempotent; attribute says non-idempotent.
        // Two conflicting signals from the same declaration → collision.
        let decl = try firstFunction(in: """
        /// @lint.effect idempotent
        @NonIdempotent
        func foo() {}
        """)
        #expect(EffectAnnotationParser.parseEffect(declaration: decl) == nil)
    }

    @Test
    func bothForms_disagreeingExternal_returnsNil() throws {
        // Observational doc-comment + `@ExternallyIdempotent(by:)` attribute:
        // tiers disagree, withdraw.
        let decl = try firstFunction(in: """
        /// @lint.effect observational
        @ExternallyIdempotent(by: "k")
        func foo(k: String) {}
        """)
        #expect(EffectAnnotationParser.parseEffect(declaration: decl) == nil)
    }

    // MARK: - Doc-comment-only still works (backward compat)

    @Test
    func docCommentOnly_parsesUnchanged() throws {
        let decl = try firstFunction(in: """
        /// @lint.effect non_idempotent
        func foo() {}
        """)
        #expect(EffectAnnotationParser.parseEffect(declaration: decl) == .nonIdempotent)
    }

    @Test
    func attributeOnly_parsesWithoutDocComment() throws {
        let decl = try firstFunction(in: """
        @NonIdempotent
        func foo() {}
        """)
        #expect(EffectAnnotationParser.parseEffect(declaration: decl) == .nonIdempotent)
    }
}
