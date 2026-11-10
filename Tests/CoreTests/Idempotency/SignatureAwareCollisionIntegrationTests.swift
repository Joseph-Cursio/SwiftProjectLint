import SwiftEffectInference
import SwiftParser
@testable import SwiftProjectLintIdempotencyRules
import SwiftProjectLintModels
@testable import SwiftProjectLintVisitors
import SwiftSyntax
import Testing

/// Integration-level tests for the signature-aware collision policy:
/// `EffectSymbolTable` end-to-end behavior, overload resolution,
/// the round-2 `MemoryPersistDriver` shape, multi-annotated-declaration
/// collisions, and the unannotated-declaration invisibility rule.
///
/// Kept separate from `SignatureAwareCollisionTests`, which exercises
/// the primitives (`FunctionSignature` extraction + closure-typed
/// stored property signatures).
@Suite
struct SignatureAwareCollisionIntegrationTests {

    // MARK: - Helpers

    func tableOf(_ sources: String...) -> EffectSymbolTable {
        var table = EffectSymbolTable()
        for source in sources {
            table.merge(source: Parser.parse(source: source))
        }
        return table
    }

    func runCrossFileEffect(files: [String: String]) -> IdempotencyViolationVisitor {
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

    func runCrossFileContext(files: [String: String]) -> NonIdempotentInRetryContextVisitor {
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

    // MARK: - EffectSymbolTable closure-property integration

    @Test
    func symbolTable_mergesAnnotatedClosureProperty() {
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
    func symbolTable_unannotatedClosureProperty_notRecorded() {
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
    func symbolTable_collision_closurePropertyVsFunctionDecl() {
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
    func symbolTable_closureProperty_contextAnnotationLands() {
        // `@lint.context strict_replayable` on a closure-property declaration
        // should populate the context entry the same way a function decl does.
        let source = """
        struct Workflow {
            /// @lint.context strict_replayable
            var run: @Sendable () async throws -> Void
        }
        """
        let contexts = ContextSymbolTable.build(from: Parser.parse(source: source))
        let signature = FunctionSignature(name: "run", argumentLabels: [])
        #expect(contexts.context(for: signature) == .strictReplayable)
    }

    @Test
    func symbolTable_closureInNestedClosure_skipped() {
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
            """,
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
            """,
        ]

        let issues = runCrossFileContext(files: files).detectedIssues
        #expect(issues.count == 1)
        let issue = try #require(issues.first)
        #expect(issue.filePath == "Handler.swift")
    }
}
