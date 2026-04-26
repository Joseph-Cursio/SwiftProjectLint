import Testing
@testable import SwiftProjectLintIdempotencyRules
@testable import SwiftProjectLintVisitors
import SwiftSyntax
import SwiftParser

/// Phase-2.3 upward inference fixtures. Body analysis computes an inferred
/// effect for an un-annotated function from the lattice lub of its direct
/// callees' effects. Declared effects always win; upward inference fills
/// the gap between "declared" and "heuristic-downward" in the rule lookup
/// cascade.
@Suite
struct UpwardInferrerUnitTests {

    // MARK: - Lattice lub

    @Test
    func lub_empty_isNil() {
        #expect(UpwardEffectInferrer.leastUpperBound(of: []) == nil)
    }

    @Test
    func lub_onlyObservational_isObservational() {
        #expect(
            UpwardEffectInferrer.leastUpperBound(of: [.observational, .observational])
                == .observational
        )
    }

    @Test
    func lub_observationalAndIdempotent_isIdempotent() {
        #expect(
            UpwardEffectInferrer.leastUpperBound(of: [.observational, .idempotent])
                == .idempotent
        )
    }

    @Test
    func lub_idempotentAndExternallyIdempotent_isExternallyIdempotent() {
        #expect(
            UpwardEffectInferrer.leastUpperBound(
                of: [.idempotent, .externallyIdempotent(keyParameter: "k")]
            ) == .externallyIdempotent(keyParameter: "k")
        )
    }

    @Test
    func lub_nonIdempotentDominates() {
        #expect(
            UpwardEffectInferrer.leastUpperBound(
                of: [.observational, .idempotent, .externallyIdempotent(keyParameter: nil), .nonIdempotent]
            ) == .nonIdempotent
        )
    }

    // MARK: - Body walk semantics

    /// Helper that wraps the bare-effect resolver into the
    /// `UpwardInference?` shape the inferrer now requires. All single-pass
    /// fixtures here treat resolver-supplied effects as anchors (depth 0),
    /// matching the symbol-table's behaviour for declared / heuristic
    /// effects.
    private func infer(
        _ source: String,
        resolve: @escaping (FunctionCallExprSyntax) -> DeclaredEffect?
    ) -> [FunctionSignature: UpwardInference] {
        UpwardEffectInferrer.inferEffects(
            in: Parser.parse(source: source),
            resolveCalleeEffect: { call in
                guard let effect = resolve(call) else { return nil }
                return UpwardInference(effect: effect, depth: 0)
            }
        )
    }

    @Test
    func unannotatedCallerWithNonIdempotentCallee_infersNonIdempotent() {
        let source = """
        func caller() {
            callee()
        }
        """
        let result = infer(source) { _ in .nonIdempotent }
        let sig = FunctionSignature(name: "caller", argumentLabels: [])
        #expect(result[sig]?.effect == .nonIdempotent)
        #expect(result[sig]?.depth == 1)
    }

    @Test
    func annotatedCaller_notInferred() {
        // The inferrer skips any declaration carrying `@lint.effect`. The
        // user's annotation is authoritative and must not be second-guessed.
        let source = """
        /// @lint.effect idempotent
        func caller() {
            callee()
        }
        """
        let result = infer(source) { _ in .nonIdempotent }
        let sig = FunctionSignature(name: "caller", argumentLabels: [])
        #expect(result[sig] == nil)
    }

    @Test
    func escapingClosureBoundary_notTraversed() {
        // Calls inside `Task { }` / `withTaskGroup` / `.task` are in a
        // different retry context. Upward inference stops at those
        // boundaries, same as the rule visitors.
        //
        // Resolver returns effects only for the NAMED callees we care about
        // (`callee`), not for the escape-introducing wrappers (`Task`).
        // Realistic resolvers behave the same way — `Task()` itself is
        // neither annotated nor heuristically inferable, so lookup returns
        // nil and it contributes nothing. This fixture verifies the body
        // walk skips the closure body even when the closure would otherwise
        // contain recognised effects.
        let source = """
        func caller() {
            Task {
                callee()
            }
        }
        """
        let result = infer(source) { call in
            guard let sig = FunctionSignature.from(call: call),
                  sig.name == "callee" else { return nil }
            return .nonIdempotent
        }
        let sig = FunctionSignature(name: "caller", argumentLabels: [])
        // `callee()` sits inside an escaping closure boundary and does not
        // contribute. `Task(...)` itself has no effect in the resolver.
        // Net result: no effects collected, no inference.
        #expect(result[sig] == nil)
    }

    @Test
    func nestedFunctionNotTreatedAsInnerBody() {
        // A nested function is its own inference site. The outer function's
        // body walk must stop at the inner function's boundary — otherwise
        // the inner's callees would leak into the outer's inferred effect.
        let source = """
        func outer() {
            func inner() {
                callee()
            }
            otherCall()
        }
        """
        let result = infer(source) { call in
            let sig = FunctionSignature.from(call: call)
            return sig?.name == "callee" ? .nonIdempotent : nil
        }
        let outerSig = FunctionSignature(name: "outer", argumentLabels: [])
        let innerSig = FunctionSignature(name: "inner", argumentLabels: [])
        // outer should NOT inherit from inner's body (no evidence from
        // otherCall resolver); inner should infer non_idempotent.
        #expect(result[outerSig] == nil)
        #expect(result[innerSig]?.effect == .nonIdempotent)
    }

    @Test
    func bodyWithNoRecognisedCalls_producesNoInference() {
        let source = """
        func pureLooking() {
            let x = 1 + 2
            _ = x
        }
        """
        let result = infer(source) { _ in nil }
        #expect(result.isEmpty)
    }

    // MARK: - Rank ordering matches the proposal's lattice

    @Test
    func rankOrdering_observationalBelowIdempotent() {
        #expect(
            UpwardEffectInferrer.leastUpperBound(of: [.idempotent, .observational])
                == .idempotent
        )
    }

    @Test
    func rankOrdering_externallyIdempotentAboveIdempotent() {
        #expect(
            UpwardEffectInferrer.leastUpperBound(
                of: [.idempotent, .externallyIdempotent(keyParameter: nil)]
            ) == .externallyIdempotent(keyParameter: nil)
        )
    }
}

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
            """
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
            """
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
            """
        ]
        // Two diagnostics expected: the replayable->helper edge is silent
        // (helper is declared idempotent, which is trusted in replayable),
        // but the idempotent-helper->non_idempotent-sink edge fires in
        // IdempotencyViolationVisitor.
        #expect(runContext(files).detectedIssues.isEmpty)
    }

    @Test
    func upwardBeatsHeuristicDownward() throws {
        // A function named `insert` would normally be heuristic-downward-
        // inferred non_idempotent from its name. But if its body only calls
        // `logMetric` (heuristic-downward observational), upward inference
        // produces `observational` — the body-based signal overrides the
        // name-based one.
        //
        // Note: this test depends on `logMetric` not matching any
        // non-idempotent whitelist name and on `logger.info` or similar
        // not being invoked. We use a neutral helper name that's NOT in
        // any whitelist, and the inner body does nothing observable, so
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
            """
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
            """
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
            """
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
            """
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
            """
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
