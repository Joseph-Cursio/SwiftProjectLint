import Testing
@testable import Core
@testable import SwiftProjectLintRules
@testable import SwiftProjectLintVisitors
import SwiftSyntax
import SwiftParser

/// Exercises the cross-file pathway: declarations in one file resolved against
/// callers in another, plus the collision policy for bare-name ambiguity.
///
/// The collision policy (OI-4 resolution): a function name seen more than once
/// across the files merged into the `EffectSymbolTable` — whether annotated in
/// both places, in neither, or only in one — has its entry withdrawn. Lookups
/// return nil for collided names. The rule treats the callee as unknown and
/// stays silent.
@Suite
struct CrossFileIdempotencyTests {

    // MARK: - Helpers

    private func runCrossFileEffect(
        files: [String: String]
    ) -> IdempotencyViolationVisitor {
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

    private func runCrossFileContext(
        files: [String: String]
    ) -> NonIdempotentInRetryContextVisitor {
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

    // MARK: - Positive: cross-file resolution works

    @Test
    func callerInFileA_nonIdempotentCalleeInFileB_flags() throws {
        let files: [String: String] = [
            "Handler.swift": """
            /// @lint.effect idempotent
            func process() async throws {
                try await insert(1)
            }
            """,
            "Database.swift": """
            /// @lint.effect non_idempotent
            func insert(_ id: Int) async throws {}
            """
        ]

        let visitor = runCrossFileEffect(files: files)
        let issues = visitor.detectedIssues
        #expect(issues.count == 1)
        let issue = try #require(issues.first)
        #expect(issue.ruleName == .idempotencyViolation)
        #expect(issue.message.contains("insert"))
        #expect(issue.filePath == "Handler.swift")
    }

    @Test
    func callerInFileA_idempotentCalleeInFileB_noDiagnostic() {
        let files: [String: String] = [
            "Handler.swift": """
            /// @lint.effect idempotent
            func process() async throws {
                try await upsert(1)
            }
            """,
            "Database.swift": """
            /// @lint.effect idempotent
            func upsert(_ id: Int) async throws {}
            """
        ]

        #expect(runCrossFileEffect(files: files).detectedIssues.isEmpty)
    }

    @Test
    func replayableCallerInFileA_nonIdempotentCalleeInFileB_flags() throws {
        let files: [String: String] = [
            "Handler.swift": """
            /// @lint.context replayable
            func handle() async throws {
                try await insert(1)
            }
            """,
            "Database.swift": """
            /// @lint.effect non_idempotent
            func insert(_ id: Int) async throws {}
            """
        ]

        let visitor = runCrossFileContext(files: files)
        let issues = visitor.detectedIssues
        #expect(issues.count == 1)
        let issue = try #require(issues.first)
        #expect(issue.ruleName == .nonIdempotentInRetryContext)
        #expect(issue.filePath == "Handler.swift")
    }

    // MARK: - Collision policy

    @Test
    func collisionWithConflictingEffects_withdrawsEntry_noDiagnostic() {
        // Two files both define `insert`, with conflicting effects. The entry
        // is withdrawn and the caller's call to `insert` is treated as unknown.
        // Expected: zero diagnostics, even though one of the callees would
        // otherwise fire the rule.
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

        #expect(runCrossFileEffect(files: files).detectedIssues.isEmpty)
    }

    @Test
    func collisionWithSameEffect_keepsEntry_stillFlags() throws {
        // Two files define `insert` with the *same* non_idempotent effect. The
        // entry survives collision detection, so the caller's call to `insert`
        // still flags.
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

    @Test
    func collisionAnnotatedAndUnannotated_withdrawsEntry_noDiagnostic() {
        // File A annotates `insert` as non_idempotent; file B has a different
        // `insert` with no annotation. Without type info we can't know which
        // the caller means — the entry is withdrawn and the rule stays silent.
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
            "OtherModule.swift": """
            func insert(_ x: String) async throws {}
            """
        ]

        #expect(runCrossFileEffect(files: files).detectedIssues.isEmpty)
    }

    @Test
    func collisionDetectedByIsCollision() {
        // Direct check of the symbol table's collision reporting. Handy for
        // diagnostics that might want to surface the ambiguity to the user.
        let source = """
        /// @lint.effect non_idempotent
        func insert(_ id: Int) {}

        /// @lint.effect idempotent
        func insert(_ id: String) {}
        """

        var table = EffectSymbolTable()
        table.merge(source: Parser.parse(source: source))

        #expect(table.isCollision(name: "insert"))
        #expect(table.effect(for: "insert") == nil)
    }

    // MARK: - Phase-1-correct negative: the per-file mode from Phase 3

    @Test
    func perFileUseStillWorks_calleeAndCallerSameFile() {
        // Sanity check that the single-file path (used by the tests elsewhere
        // and by the Phase-3 positive demo) continues to resolve correctly
        // after the cross-file retrofit.
        let files: [String: String] = [
            "Demo.swift": """
            /// @lint.effect non_idempotent
            func insert(_ id: Int) async throws {}

            /// @lint.context replayable
            func handle() async throws {
                try await insert(1)
            }
            """
        ]

        let issues = runCrossFileContext(files: files).detectedIssues
        #expect(issues.count == 1)
    }
}
