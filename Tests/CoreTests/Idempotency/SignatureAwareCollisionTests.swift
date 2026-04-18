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
    func extractsSignatureFromDeclaration_externalLabelWinsOverInternalName() {
        let source = "func send(to email: String) {}"
        let decl = Parser.parse(source: source)
            .statements.first!
            .item.as(FunctionDeclSyntax.self)!
        let signature = FunctionSignature.from(declaration: decl)
        #expect(signature.name == "send")
        #expect(signature.argumentLabels == ["to"])
        #expect(signature.description == "send(to:)")
    }

    @Test
    func extractsSignatureFromDeclaration_underscoreForSuppressedLabel() {
        let source = "func upsert(_ id: Int) {}"
        let decl = Parser.parse(source: source)
            .statements.first!
            .item.as(FunctionDeclSyntax.self)!
        let signature = FunctionSignature.from(declaration: decl)
        #expect(signature.argumentLabels == ["_"])
        #expect(signature.description == "upsert(_:)")
    }

    @Test
    func extractsSignatureFromCallSite_matchingDeclarationForm() {
        let source = """
        func receiver() {
            create(key: "k", value: "v", expires: nil)
        }
        """
        // Dig out the one FunctionCallExprSyntax inside the body.
        var found: FunctionCallExprSyntax?
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
        found = finder.call
        let signature = FunctionSignature.from(call: found!)
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
        #expect(issues.count == 1, "Expected the post-fix policy to resolve the 3-arg create despite protocol/extension siblings")
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
