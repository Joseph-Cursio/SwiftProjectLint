import enum SwiftEffectInference.Effect
import SwiftParser
@testable import SwiftProjectLintIdempotencyRules
import SwiftProjectLintModels
@testable import SwiftProjectLintVisitors
import SwiftSyntax
import Testing

/// End-to-end fixtures: the rule visitors consult the inferrer as a fallback
/// after symbol-table lookup. Declared effects on the same callee must still
/// win.
@Suite
struct HeuristicInferenceIntegrationTests {

    private func runEffect(_ source: String) -> IdempotencyViolationVisitor {
        let visitor = IdempotencyViolationVisitor(pattern: IdempotencyViolation().pattern)
        visitor.walk(Parser.parse(source: source))
        visitor.analyze()
        return visitor
    }

    private func runContext(_ source: String) -> NonIdempotentInRetryContextVisitor {
        let visitor = NonIdempotentInRetryContextVisitor(
            pattern: NonIdempotentInRetryContext().pattern
        )
        visitor.walk(Parser.parse(source: source))
        visitor.analyze()
        return visitor
    }

    // MARK: - Inference fires rules on un-annotated callees

    @Test
    func replayableCallsInferredNonIdempotent_flags() throws {
        // `insert` has no `@lint.effect` annotation anywhere in the project,
        // but the heuristic infers non_idempotent from its name. The
        // nonIdempotentInRetryContext rule fires on that inferred signal.
        let source = """
        func insert(_ row: Row) async throws {}

        /// @lint.context replayable
        func handle(_ row: Row) async throws {
            try await insert(row)
        }
        """
        let issues = runContext(source).detectedIssues
        #expect(issues.count == 1)
        let issue = try #require(issues.first)
        #expect(issue.ruleName == .nonIdempotentInRetryContext)
        #expect(issue.message.contains("inferred"))
        #expect(issue.message.contains("insert"))
    }

    @Test
    func idempotentCallerCallsInferredNonIdempotent_flags() throws {
        let source = """
        func insert(_ row: Row) async throws {}

        /// @lint.effect idempotent
        func process(_ row: Row) async throws {
            try await insert(row)
        }
        """
        let issues = runEffect(source).detectedIssues
        #expect(issues.count == 1)
        let issue = try #require(issues.first)
        #expect(issue.ruleName == .idempotencyViolation)
        #expect(issue.message.contains("inferred"))
    }

    @Test
    func observationalCallerCallsInferredIdempotent_flags() {
        // Observational must call only observational/pure. An inferred-
        // idempotent call (like `upsert`) still breaks that contract.
        let source = """
        func upsert(_ row: Row) async throws {}

        /// @lint.effect observational
        func logAndStore(_ row: Row) async throws {
            try await upsert(row)
        }
        """
        let issues = runEffect(source).detectedIssues
        #expect(issues.count == 1)
        #expect(issues.first?.message.contains("inferred") == true)
    }

    // MARK: - Declared beats inferred

    @Test
    func declaredEffectOverridesInference() {
        // `insert` is declared `@lint.effect idempotent` — that overrides the
        // name-based non_idempotent inference. The replayable caller
        // produces no diagnostic.
        let source = """
        /// @lint.effect idempotent
        func insert(_ row: Row) async throws {}

        /// @lint.context replayable
        func handle(_ row: Row) async throws {
            try await insert(row)
        }
        """
        #expect(runContext(source).detectedIssues.isEmpty)
    }

    @Test
    func declaredEffectOverridesInference_acrossFiles() {
        // `insert` is declared `idempotent` in a sibling file. The inferrer
        // never runs for annotated callees even when the declaration is
        // cross-file.
        let files: [String: String] = [
            "Handler.swift": """
            /// @lint.context replayable
            func handle(_ row: Row) async throws {
                try await insert(row)
            }
            """,
            "Database.swift": """
            /// @lint.effect idempotent
            func insert(_ row: Row) async throws {}
            """,
        ]
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
        #expect(visitor.detectedIssues.isEmpty)
    }

    // MARK: - Inference is silent on unlisted names (no noise)

    @Test
    func unlistedName_producesNoDiagnostic() {
        let source = """
        func doThing(_ row: Row) async throws {}

        /// @lint.context replayable
        func handle(_ row: Row) async throws {
            try await doThing(row)
        }
        """
        #expect(runContext(source).detectedIssues.isEmpty)
    }

    @Test
    func saveIsNotInferredAsNonIdempotent() {
        // Regression guard: `save` is deliberately OUT of the allowlist.
        // If someone later adds it to `nonIdempotentNames`, this test
        // starts failing and forces the decision to be re-litigated.
        let source = """
        func save(_ row: Row) async throws {}

        /// @lint.context replayable
        func handle(_ row: Row) async throws {
            try await save(row)
        }
        """
        #expect(runContext(source).detectedIssues.isEmpty)
    }

    // MARK: - Observational inference via logger receiver

    @Test
    func replayableCallsLoggerInfo_noDiagnostic() {
        // `logger.info(...)` infers observational, which is trusted in a
        // replayable context. This is exactly the shape the OI-5
        // `observational` tier was introduced to absorb — now with no
        // annotation required on `logger.info` itself.
        let source = """
        /// @lint.context replayable
        func handle(_ event: Event) async throws {
            logger.info("handling \\(event.id)")
        }
        """
        #expect(runContext(source).detectedIssues.isEmpty)
    }

    @Test
    func idempotentCallerInferredObservational_noDiagnostic() {
        let source = """
        /// @lint.effect idempotent
        func process(_ event: Event) async throws {
            logger.debug("processing")
        }
        """
        #expect(runEffect(source).detectedIssues.isEmpty)
    }

    // MARK: - Override hint in diagnostic prose

    // MARK: - Inference skips collision-withdrawn entries

    @Test
    func collisionWithdrawnEntry_doesNotFallToInference() {
        // Two annotated `insert(_:)` declarations with conflicting effects.
        // The symbol table withdraws the entry (OI-4 collision policy).
        // Inference must NOT run — the user expressed intent via two
        // conflicting annotations, and a heuristic guess would paper over
        // the ambiguity with a third interpretation the user did not ask
        // for. Regression guard for the gate added alongside the inferrer.
        let files: [String: String] = [
            "Handler.swift": """
            /// @lint.context replayable
            func handle(_ id: Int) async throws {
                try await insert(id)
            }
            """,
            "DatabaseA.swift": """
            /// @lint.effect idempotent
            func insert(_ id: Int) async throws {}
            """,
            "DatabaseB.swift": """
            /// @lint.effect non_idempotent
            func insert(_ id: Int) async throws {}
            """,
        ]
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
        // Under the collision-skip-inference rule: zero diagnostics.
        // Without the rule: inference would infer non_idempotent from
        // the name `insert` and fire, substituting a name-based guess
        // for a user-expressed disagreement.
        #expect(visitor.detectedIssues.isEmpty)
    }

    @Test
    func inferredDiagnosticPromptsUserToAnnotate() throws {
        let source = """
        func insert(_ row: Row) async throws {}

        /// @lint.context replayable
        func handle(_ row: Row) async throws {
            try await insert(row)
        }
        """
        let issues = runContext(source).detectedIssues
        let issue = try #require(issues.first)
        // The inferred-flavour prose must tell users how to override the
        // heuristic when it's wrong, matching the rule-doc's override
        // recommendation.
        #expect(issue.message.contains("annotate"))
        #expect(issue.message.contains("@lint.effect"))
    }
}
