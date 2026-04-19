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

    // MARK: - Helpers

    private func tableOf(_ sources: String...) -> EffectSymbolTable {
        var table = EffectSymbolTable()
        for source in sources {
            table.merge(source: Parser.parse(source: source))
        }
        return table
    }

    private func runCrossFileEffect(files: [String: String]) -> IdempotencyViolationVisitor {
        let cache: [String: SourceFileSyntax] = files.mapValues { Parser.parse(source: $0) }
        let visitor = IdempotencyViolationVisitor(fileCache: cache)
        for (path, source) in cache {
            visitor.setFilePath(path)
            visitor.setSourceLocationConverter(
                SourceLocationConverter(fileName: path, tree: source)
            )
            visitor.walk(source)
        }
        visitor.finalizeAnalysis()
        return visitor
    }

    private func runCrossFileContext(files: [String: String]) -> NonIdempotentInRetryContextVisitor {
        let cache: [String: SourceFileSyntax] = files.mapValues { Parser.parse(source: $0) }
        let visitor = NonIdempotentInRetryContextVisitor(fileCache: cache)
        for (path, source) in cache {
            visitor.setFilePath(path)
            visitor.setSourceLocationConverter(
                SourceLocationConverter(fileName: path, tree: source)
            )
            visitor.walk(source)
        }
        visitor.finalizeAnalysis()
        return visitor
    }

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
    func closureProperty_untypedBinding_returnsNil() throws {
        // Inferred-type bindings don't declare the call-site shape — can't
        // extract a signature without the type annotation.
        let decl = try varDecl("var f = { (x: Int) in print(x) }")
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

    // MARK: - EffectSymbolTable closure-property integration

    @Test
    func symbolTable_mergesAnnotatedClosureProperty() throws {
        let source = """
        struct WeatherClient {
            /// @lint.effect idempotent
            var search: @Sendable (_ query: String) async throws -> String
        }
        """
        let table = tableOf(source)
        let signature = FunctionSignature(name: "search", argumentLabels: ["query"])
        #expect(table.effect(for: signature) == .idempotent)
    }

    @Test
    func symbolTable_unannotatedClosureProperty_notRecorded() throws {
        let source = """
        struct WeatherClient {
            var search: @Sendable (_ query: String) async throws -> String
        }
        """
        let table = tableOf(source)
        let signature = FunctionSignature(name: "search", argumentLabels: ["query"])
        #expect(table.effect(for: signature) == nil)
    }

    @Test
    func symbolTable_collision_closurePropertyVsFunctionDecl() throws {
        // A struct declares `search(query:)` as a closure property with
        // `idempotent`, and a separate type declares a method with the
        // same signature as `non_idempotent`. Collision policy withdraws.
        let source = """
        struct WeatherClient {
            /// @lint.effect idempotent
            var search: @Sendable (_ query: String) async throws -> String
        }
        struct MailClient {
            /// @lint.effect non_idempotent
            func search(query: String) async throws -> String { "" }
        }
        """
        let table = tableOf(source)
        let signature = FunctionSignature(name: "search", argumentLabels: ["query"])
        #expect(table.effect(for: signature) == nil)
        #expect(table.isCollision(signature: signature))
    }

    @Test
    func symbolTable_closureProperty_contextAnnotationLands() throws {
        // `@lint.context strict_replayable` on a closure-property declaration
        // should populate the context entry the same way a function decl does.
        let source = """
        struct Workflow {
            /// @lint.context strict_replayable
            var run: @Sendable () async throws -> Void
        }
        """
        let table = tableOf(source)
        let signature = FunctionSignature(name: "run", argumentLabels: [])
        #expect(table.context(for: signature) == .strictReplayable)
    }

    @Test
    func symbolTable_closureInNestedClosure_skipped() throws {
        // Mirrors FunctionDeclCollector: we don't collect declarations
        // that live inside a closure body (they're not nominal surfaces
        // addressable by bare name from outside the closure).
        let source = """
        func outer() {
            _ = { (x: Int) -> Void in
                /// @lint.effect idempotent
                var inner: (Int) -> Void = { _ in }
                inner(x)
            }
        }
        """
        let table = tableOf(source)
        let signature = FunctionSignature(name: "inner", argumentLabels: ["_"])
        #expect(table.effect(for: signature) == nil)
    }

    @Test
    func extractsSignatureFromCallSite_matchingDeclarationForm() throws {
        let source = """
        func receiver() {
            create(key: "k", value: "v", expires: nil)
        }
        """
        // Dig out the one FunctionCallExprSyntax inside the body.
        final class Finder: SyntaxVisitor {
            var call: FunctionCallExprSyntax?
            override func visit(_ node: FunctionCallExprSyntax) -> SyntaxVisitorContinueKind {
                if call == nil { call = node }
                return .skipChildren
            }
            init() { super.init(viewMode: .sourceAccurate) }
        }
        let finder = Finder()
        finder.walk(Parser.parse(source: source))
        let found = try #require(finder.call)
        let signature = FunctionSignature.from(call: found)
        #expect(signature?.name == "create")
        #expect(signature?.argumentLabels == ["key", "value", "expires"])
    }

    // MARK: - Overloads at different arities resolve correctly

    @Test
    func overloadsOnArity_resolveIndependently() throws {
        // Two honestly distinct overloads of `emit` at arities 1 and 2, each
        // annotated differently. The pre-fix policy withdrew both on name
        // collision. The new policy resolves them independently and both
        // annotations stand.
        let files: [String: String] = [
            "Service.swift": """
            /// @lint.effect observational
            func emit(_ name: String) {}

            /// @lint.effect non_idempotent
            func emit(_ name: String, _ payload: String) {}
            """,
            "Handler.swift": """
            /// @lint.context replayable
            func handle() async throws {
                emit("metric")                 // observational — no diagnostic
                emit("metric", "payload")      // non_idempotent — should flag
            }
            """
        ]

        let issues = runCrossFileContext(files: files).detectedIssues
        #expect(issues.count == 1)
        let issue = try #require(issues.first)
        #expect(issue.message.contains("emit"))
        #expect(issue.filePath == "Handler.swift")
    }

    @Test
    func overloadsOnFirstLabel_resolveIndependently() throws {
        // Same arity, different first argument label. Swift distinguishes these
        // at the call site; so must the symbol table.
        let files: [String: String] = [
            "Service.swift": """
            /// @lint.effect non_idempotent
            func record(to store: String) {}

            /// @lint.effect observational
            func record(for metric: String) {}
            """,
            "Handler.swift": """
            /// @lint.context replayable
            func handle() async throws {
                record(for: "tick")            // observational — silent
                record(to: "db")               // non_idempotent — flag
            }
            """
        ]

        let issues = runCrossFileContext(files: files).detectedIssues
        #expect(issues.count == 1)
        let issue = try #require(issues.first)
        #expect(issue.filePath == "Handler.swift")
    }

    // MARK: - The round-2 MemoryPersistDriver shape

    @Test
    func protocolRequirementPlusExtensionDefaultPlusConcreteAnnotation_resolves() throws {
        // Faithful reproduction of round-2 `MemoryPersistDriver.create`:
        // - A protocol requirement declares `create(key:value:expires:)` (no body, unannotated).
        // - A protocol extension provides a default `create(key:value:)` (different arity, unannotated).
        // - The concrete conformer provides `create(key:value:expires:)` annotated non_idempotent.
        //
        // Pre-fix: bare-name policy withdraws all three → zero diagnostics on caller.
        // Post-fix: `create(key:value:expires:)` has exactly one ANNOTATED declaration
        //           (unannotated protocol requirement is ignored); entry survives;
        //           caller's call via the 3-arg form resolves and flags.
        let files: [String: String] = [
            "PersistDriver.swift": """
            protocol PersistDriver {
                func create(key: String, value: String, expires: String?) async throws
            }

            extension PersistDriver {
                func create(key: String, value: String) async throws {
                    try await create(key: key, value: value, expires: nil)
                }
            }
            """,
            "MemoryPersistDriver.swift": """
            struct MemoryPersistDriver: PersistDriver {
                /// @lint.effect non_idempotent
                func create(key: String, value: String, expires: String?) async throws {}
            }
            """,
            "Handler.swift": """
            /// @lint.context replayable
            func handleWebhook(driver: MemoryPersistDriver) async throws {
                try await driver.create(key: "id", value: "v", expires: nil)
            }
            """
        ]

        let issues = runCrossFileContext(files: files).detectedIssues
        #expect(
            issues.count == 1,
            "Expected the post-fix policy to resolve the 3-arg create despite protocol/extension siblings"
        )
        let issue = try #require(issues.first)
        #expect(issue.message.contains("create"))
        #expect(issue.filePath == "Handler.swift")
    }

    // MARK: - Collision still fires when multiple ANNOTATED declarations disagree

    @Test
    func twoAnnotatedDeclarationsSameSignature_conflictingEffects_stillWithdraw() {
        // Signature-aware keying does NOT weaken real collisions: two annotated
        // declarations of the same signature with conflicting effects still
        // withdraw the entry.
        let files: [String: String] = [
            "Handler.swift": """
            /// @lint.effect idempotent
            func process() async throws {
                try await insert(1)
            }
            """,
            "DatabaseA.swift": """
            /// @lint.effect non_idempotent
            func insert(_ id: Int) async throws {}
            """,
            "DatabaseB.swift": """
            /// @lint.effect idempotent
            func insert(_ id: Int) async throws {}
            """
        ]

        // Both `insert(_:)` declarations share signature; conflicting effects
        // withdraw; no diagnostic on caller.
        #expect(runCrossFileEffect(files: files).detectedIssues.isEmpty)
    }

    @Test
    func twoAnnotatedDeclarationsSameSignature_matchingEffects_keep() throws {
        let files: [String: String] = [
            "Handler.swift": """
            /// @lint.effect idempotent
            func process() async throws {
                try await insert(1)
            }
            """,
            "DatabaseA.swift": """
            /// @lint.effect non_idempotent
            func insert(_ id: Int) async throws {}
            """,
            "DatabaseB.swift": """
            /// @lint.effect non_idempotent
            func insert(_ id: Int) async throws {}
            """
        ]

        let issues = runCrossFileEffect(files: files).detectedIssues
        #expect(issues.count == 1)
        #expect(issues.first?.message.contains("insert") == true)
    }

    // MARK: - Unannotated declarations are invisible

    @Test
    func symbolTable_onlyAnnotatedDeclarationsCountTowardCollision() {
        let table = tableOf(
            """
            func insert(_ id: Int) {}
            """,
            """
            /// @lint.effect non_idempotent
            func insert(_ id: Int) {}
            """,
            """
            func insert(_ id: Int) {}
            """
        )
        let signature = FunctionSignature(name: "insert", argumentLabels: ["_"])
        // Only one ANNOTATED declaration → not a collision, entry kept.
        #expect(!table.isCollision(signature: signature))
        #expect(table.effect(for: signature) == .nonIdempotent)
    }
}
