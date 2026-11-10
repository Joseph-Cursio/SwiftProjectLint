import SwiftEffectInference
import SwiftParser
@testable import SwiftProjectLintIdempotencyRules
import SwiftProjectLintModels
@testable import SwiftProjectLintVisitors
import SwiftSyntax
import Testing

/// End-to-end: upward inference changes diagnostic behaviour on real rule
/// invocations. Declared beats upward; upward beats heuristic-downward;
/// collision short-circuits both.
@Suite
struct UpwardInferenceIntegrationTests {

    private func runContext(_ files: [String: String]) -> NonIdempotentInRetryContextVisitor {
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

    private func runEffect(_ files: [String: String]) -> IdempotencyViolationVisitor {
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

    // MARK: - New diagnostics enabled by upward inference

    @Test
    func replayableCallsUnannotatedHelperCallingNonIdempotent_flagsViaUpward() throws {
        // The shape Phase 2.2 couldn't catch and Phase 2.3 now does.
        //   A @context replayable
        //     -> helper (unannotated; body calls annotated non-idempotent)
        //       -> sink @lint.effect non_idempotent
        // Pre-Phase-2.3: silent. Post-Phase-2.3: helper is upward-inferred
        // non_idempotent from its body; the replayable->helper edge fires.
        let files: [String: String] = [
            "Sink.swift": """
            /// @lint.effect non_idempotent
            func sink() async throws {}
            """,
            "Helper.swift": """
            func helper() async throws {
                try await sink()
            }
            """,
            "Handler.swift": """
            /// @lint.context replayable
            func handler() async throws {
                try await helper()
            }
            """,
        ]
        let issues = runContext(files).detectedIssues
        #expect(issues.count == 1)
        let issue = try #require(issues.first)
        #expect(issue.message.contains("helper"))
        #expect(issue.message.contains("inferred"))
        #expect(issue.message.contains("body"))
    }

    @Test
    func upwardFromHeuristicDownward_propagatesChain() throws {
        // Callees with heuristic-downward inference propagate upward.
        //   A @context replayable
        //     -> helper (unannotated; body calls `insert` — downward-inferred non-idempotent)
        // The upward inferrer respects heuristic-downward results, so
        // helper becomes upward-inferred non-idempotent.
        let files: [String: String] = [
            "Handler.swift": """
            func helper() async throws {
                insert(1)
            }

            /// @lint.context replayable
            func handler() async throws {
                try await helper()
            }
            """,
        ]
        let issues = runContext(files).detectedIssues
        #expect(issues.count == 1)
        let issue = try #require(issues.first)
        #expect(issue.message.contains("helper"))
        #expect(issue.message.contains("inferred"))
    }

    // MARK: - Precedence

    @Test
    func declaredBeatsUpward() {
        // helper is declared idempotent. Body calls an annotated non-idempotent
        // function, but the declaration wins — upward inference does NOT run
        // on annotated decls.
        let files: [String: String] = [
            "Sink.swift": """
            /// @lint.effect non_idempotent
            func sink() async throws {}
            """,
            "Helper.swift": """
            /// @lint.effect idempotent
            func helper() async throws {
                try await sink()
            }
            """,
            "Handler.swift": """
            /// @lint.context replayable
            func handler() async throws {
                try await helper()
            }
            """,
        ]
        // Two diagnostics expected: the replayable->helper edge is silent
        // (helper is declared idempotent, which is trusted in replayable),
        // but the idempotent-helper->non_idempotent-sink edge fires in
        // IdempotencyViolationVisitor.
        #expect(runContext(files).detectedIssues.isEmpty)
    }

    @Test
    func upwardBeatsHeuristicDownward() {
        // A function named `insert` would normally be heuristic-downward-
        // inferred non_idempotent from its name. But if its body only calls
        // `logMetric` (heuristic-downward observational), upward inference
        // produces `observational` — the body-based signal overrides the
        // name-based one.
        //
        // Note: this test depends on `logMetric` not matching any
        // non-idempotent allowlist name and on `logger.info` or similar
        // not being invoked. We use a neutral helper name that's NOT in
        // any allowlist, and the inner body does nothing observable, so
        // upward inference finds no callee effects and produces no
        // inference. The test below instead uses a logger-shaped call.
        let files: [String: String] = [
            "Insert.swift": """
            func insert() async throws {
                logger.info("noop")
            }
            """,
            "Handler.swift": """
            /// @lint.context replayable
            func handler() async throws {
                try await insert()
            }
            """,
        ]
        // `insert` body calls `logger.info(...)` → heuristic-downward
        // observational. Upward: insert is inferred observational. That
        // overrides the name-based non_idempotent downward inference.
        // Result: zero diagnostics. (Without upward inference, insert
        // would be non_idempotent by name and fire.)
        #expect(runContext(files).detectedIssues.isEmpty)
    }

    // MARK: - Multi-hop chains (Phase 2.3 follow-up)

    @Test
    func twoHopChainCaughtViaMultiHop() throws {
        // Three-link chain that one-hop inference missed:
        //   handler @context replayable
        //     -> outerHelper (unannotated, body calls innerHelper)
        //       -> innerHelper (unannotated, body calls sink)
        //         -> sink @lint.effect non_idempotent
        //
        // Multi-hop fixed-point:
        //   pass 1: innerHelper → (non_idempotent, depth 1)
        //   pass 2: outerHelper → (non_idempotent, depth 2)  ← chains through
        //   pass 3: no changes; converged
        // Rule fires on handler→outerHelper with depth=2 in the diagnostic.
        let files: [String: String] = [
            "All.swift": """
            /// @lint.effect non_idempotent
            func sink() async throws {}

            func innerHelper() async throws {
                try await sink()
            }

            func outerHelper() async throws {
                try await innerHelper()
            }

            /// @lint.context replayable
            func handler() async throws {
                try await outerHelper()
            }
            """,
        ]
        let issues = runContext(files).detectedIssues
        #expect(issues.count == 1)
        let issue = try #require(issues.first)
        #expect(issue.message.contains("outerHelper"))
        #expect(issue.message.contains("inferred"))
        #expect(issue.message.contains("2-hop chain"))
    }

    // MARK: - Collision interaction

    @Test
    func collisionOnCallee_skipsUpwardInferenceToo() {
        // If `helper` is annotated twice with conflicting effects, the
        // symbol table withdraws it. Upward inference must NOT run on
        // `helper`'s signature — the ambiguity is user-expressed, and a
        // body-based guess would paper over it.
        let files: [String: String] = [
            "Helper1.swift": """
            /// @lint.effect idempotent
            func helper() async throws {}
            """,
            "Helper2.swift": """
            /// @lint.effect non_idempotent
            func helper() async throws {}
            """,
            "Handler.swift": """
            /// @lint.context replayable
            func handler() async throws {
                try await helper()
            }
            """,
        ]
        #expect(runContext(files).detectedIssues.isEmpty)
    }

    // MARK: - Silent when no evidence

    @Test
    func helperWithNoRecognisedBody_producesNoInference() {
        let files: [String: String] = [
            "Helper.swift": """
            func helper() async throws {
                let _ = 1 + 1
            }
            """,
            "Handler.swift": """
            /// @lint.context replayable
            func handler() async throws {
                try await helper()
            }
            """,
        ]
        #expect(runContext(files).detectedIssues.isEmpty)
    }

    // MARK: - Idempotent caller + upward-inferred non-idempotent callee

    @Test
    func idempotentCallerCallsUpwardInferredNonIdempotent_flags() throws {
        let files: [String: String] = [
            "Sink.swift": """
            /// @lint.effect non_idempotent
            func sink() async throws {}
            """,
            "Helper.swift": """
            func helper() async throws {
                try await sink()
            }
            """,
            "Process.swift": """
            /// @lint.effect idempotent
            func process() async throws {
                try await helper()
            }
            """,
        ]
        let issues = runEffect(files).detectedIssues
        #expect(issues.count == 1)
        let issue = try #require(issues.first)
        #expect(issue.ruleName == .idempotencyViolation)
        #expect(issue.message.contains("helper"))
        #expect(issue.message.contains("inferred"))
        #expect(issue.message.contains("body"))
    }
}
