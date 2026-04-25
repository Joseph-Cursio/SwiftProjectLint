import Testing
@testable import Core
@testable import SwiftProjectLintRules
@testable import SwiftProjectLintVisitors
import SwiftSyntax
import SwiftParser

/// Exercises the OI-4 Phase-1.1 collision refinement: the `EffectSymbolTable`
/// keys entries on `FunctionSignature` (name + argument labels) rather than
/// bare name, and ignores unannotated declarations for collision detection.
///
/// Motivation, from the round-2 trial (`docs/phase1-round-2/trial-findings.md`):
/// `MemoryPersistDriver.create(key:value:expires:)` was annotated in the wild,
/// but cross-file resolution withdrew the entry because `create` also appeared
/// as a protocol requirement (unannotated) and as an extension default with a
/// different arity. Neither genuinely conflicted with the annotation, but the
/// bare-name policy treated all three as collisions.
@Suite
struct SignatureAwareCollisionTests {

    // MARK: - FunctionSignature extraction

    @Test
    func extractsSignatureFromDeclaration_externalLabelWinsOverInternalName() throws {
        let source = "func send(to email: String) {}"
        let firstStatement = try #require(Parser.parse(source: source).statements.first)
        let decl = try #require(firstStatement.item.as(FunctionDeclSyntax.self))
        let signature = FunctionSignature.from(declaration: decl)
        #expect(signature.name == "send")
        #expect(signature.argumentLabels == ["to"])
        #expect(signature.description == "send(to:)")
    }

    @Test
    func extractsSignatureFromDeclaration_underscoreForSuppressedLabel() throws {
        let source = "func upsert(_ id: Int) {}"
        let firstStatement = try #require(Parser.parse(source: source).statements.first)
        let decl = try #require(firstStatement.item.as(FunctionDeclSyntax.self))
        let signature = FunctionSignature.from(declaration: decl)
        #expect(signature.argumentLabels == ["_"])
        #expect(signature.description == "upsert(_:)")
    }

    // MARK: - Closure-typed stored properties (FunctionSignature.from(declaration: VariableDecl))

    /// Helper: extract a `VariableDeclSyntax` from the first statement of a source.
    private func varDecl(_ source: String) throws -> VariableDeclSyntax {
        let firstStatement = try #require(Parser.parse(source: source).statements.first)
        // Member-level decls land in `MemberBlockItemListSyntax`, so we also
        // accept a struct-wrapped source and dig out the first member.
        if let decl = firstStatement.item.as(VariableDeclSyntax.self) {
            return decl
        }
        if let structDecl = firstStatement.item.as(StructDeclSyntax.self),
           let member = structDecl.memberBlock.members.first,
           let varDecl = member.decl.as(VariableDeclSyntax.self) {
            return varDecl
        }
        fatalError("expected a var decl in the first statement or first struct member")
    }

    @Test
    func closureProperty_plainFunctionType_producesUnderscoreLabel() throws {
        // `(Int) -> Void` has one unlabeled parameter. Callers write
        // `f(0)`, which matches `f(_:)`. No Path-A remap.
        let decl = try varDecl("var f: (Int) -> Void")
        let signature = try #require(FunctionSignature.from(declaration: decl))
        #expect(signature.description == "f(_:)")
    }

    @Test
    func closureProperty_pathARemap_underscoreInternalNameBecomesLabel() throws {
        // `(_ id: Int) -> Void` — Swift function-type semantics call this
        // `f(_:)`. Path A honours the macro-relabeling convention
        // (`@DependencyClient` & friends) that exposes the var as
        // `f(id:)`. See the `from(declaration: VariableDeclSyntax)` docs.
        let decl = try varDecl("var f: (_ id: Int) -> Void")
        let signature = try #require(FunctionSignature.from(declaration: decl))
        #expect(signature.description == "f(id:)")
    }

    @Test
    func closureProperty_labelledFunctionType_usesExplicitLabel() throws {
        let decl = try varDecl("var f: (id: Int) -> Void")
        let signature = try #require(FunctionSignature.from(declaration: decl))
        #expect(signature.description == "f(id:)")
    }

    @Test
    func closureProperty_attributedType_peelsAttributes() throws {
        // TCA `@DependencyClient`'s canonical shape — `@Sendable` attribute
        // wraps the function type, and the closure is async-throws. Path A
        // remaps `_ query:` → `query`.
        let decl = try varDecl(
            "var search: @Sendable (_ query: String) async throws -> String"
        )
        let signature = try #require(FunctionSignature.from(declaration: decl))
        #expect(signature.description == "search(query:)")
    }

    @Test
    func closureProperty_multipleParameters_preservesOrder() throws {
        let decl = try varDecl(
            "var f: (_ id: Int, label: String, _ count: Int) -> Void"
        )
        let signature = try #require(FunctionSignature.from(declaration: decl))
        // id (path A) / label (canonical) / count (path A).
        #expect(signature.description == "f(id:label:count:)")
    }

    @Test
    func closureProperty_nonFunctionTypedVar_returnsNil() throws {
        let decl = try varDecl("var count: Int")
        #expect(FunctionSignature.from(declaration: decl) == nil)
    }

    @Test
    func closureProperty_untypedBinding_typedClosureSignature_extractsFromArity() throws {
        // Typeless binding with an explicit closure-literal parameter clause.
        // Closures are positional at the call site, so all labels are `_`;
        // only arity is derived.
        let decl = try varDecl("var f = { (x: Int) in print(x) }")
        let signature = try #require(FunctionSignature.from(declaration: decl))
        #expect(signature.description == "f(_:)")
    }

    @Test
    func closureProperty_untypedBinding_shorthandClosureSignature_extractsFromArity() throws {
        // Shorthand `a, b in` form. Arity still visible in the signature.
        let decl = try varDecl("var f = { a, b in print(a, b) }")
        let signature = try #require(FunctionSignature.from(declaration: decl))
        #expect(signature.description == "f(_:_:)")
    }

    @Test
    func closureProperty_untypedBinding_emptyParameterClause_returnsZeroArity() throws {
        // `{ () in ... }` — explicit empty parameter clause, arity 0.
        let decl = try varDecl("var f = { () in print(\"hi\") }")
        let signature = try #require(FunctionSignature.from(declaration: decl))
        #expect(signature.description == "f()")
    }

    @Test
    func closureProperty_untypedBinding_anonymousArgs_returnsNil() throws {
        // `{ $0 + $1 }` — no explicit parameter list, arity only visible
        // via body analysis. Staying nil keeps the fallback conservative.
        let decl = try varDecl("var f = { $0 + $1 }")
        #expect(FunctionSignature.from(declaration: decl) == nil)
    }

    @Test
    func closureProperty_untypedBinding_nonClosureInitializer_returnsNil() throws {
        // Non-closure initializers stay nil — only closure literals are a
        // callable pseudo-method.
        let decl = try varDecl("var count = 42")
        #expect(FunctionSignature.from(declaration: decl) == nil)
    }

    @Test
    func closureProperty_multiBindingVar_returnsNil() throws {
        // `var a: (Int) -> Void, b: (String) -> Void` — ambiguous which
        // binding the annotation (if any) applies to. Skip entirely.
        let decl = try varDecl(
            "var a: (Int) -> Void, b: (String) -> Void"
        )
        #expect(FunctionSignature.from(declaration: decl) == nil)
    }

    @Test
    func closureProperty_memberLevelStruct_stillExtracts() throws {
        // Verify extraction works when the var is nested in a struct
        // (the common TCA shape). The helper digs into the first member.
        let decl = try varDecl("""
        struct Client {
            var search: @Sendable (_ query: String) async throws -> String
        }
        """)
        let signature = try #require(FunctionSignature.from(declaration: decl))
        #expect(signature.description == "search(query:)")
    }

}
