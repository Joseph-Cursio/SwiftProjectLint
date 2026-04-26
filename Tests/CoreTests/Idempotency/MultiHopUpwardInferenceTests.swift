import Testing
@testable import SwiftProjectLintIdempotencyRules
@testable import SwiftProjectLintVisitors
import SwiftSyntax
import SwiftParser

/// Multi-hop / fixed-point upward inference fixtures.
///
/// These tests exercise behaviours unique to the multi-hop pathway in
/// `EffectSymbolTable.applyUpwardInference(multiHop: true)`:
///
/// - Chains longer than two hops resolve.
/// - Order of files / declarations does not change the result (fixed-point
///   convergence).
/// - Cyclic call graphs do not infinite-loop and saturate at the recorded
///   depth cap.
/// - Declared annotations still beat any depth of upward chain.
/// - Diagnostics expose the depth so users can trace the chain.
@Suite
struct MultiHopUpwardInferenceTests {

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

    // MARK: - Chain depth

    @Test
    func threeHopChain_resolves() throws {
        // handler @context replayable
        //   -> a (un-annotated)
        //     -> b (un-annotated)
        //       -> c (un-annotated)
        //         -> sink @lint.effect non_idempotent
        // c → non_idempotent depth 1
        // b → non_idempotent depth 2
        // a → non_idempotent depth 3
        // Diagnostic on handler→a should mention 3-hop chain.
        let files: [String: String] = [
            "Chain.swift": """
            /// @lint.effect non_idempotent
            func sink() async throws {}

            func c() async throws { try await sink() }
            func b() async throws { try await c() }
            func a() async throws { try await b() }

            /// @lint.context replayable
            func handler() async throws { try await a() }
            """
        ]
        let issues = runContext(files).detectedIssues
        #expect(issues.count == 1)
        let issue = try #require(issues.first)
        #expect(issue.message.contains("'a'"))
        #expect(issue.message.contains("3-hop chain"))
    }

    @Test
    func fiveHopChain_resolves() throws {
        // Chain depth equal to the default maxHops (5). The fixed-point
        // should still converge and the diagnostic should report depth 5
        // (and not be capped to a smaller value just because we hit the
        // iteration ceiling).
        let files: [String: String] = [
            "Chain.swift": """
            /// @lint.effect non_idempotent
            func sink() async throws {}

            func e() async throws { try await sink() }
            func d() async throws { try await e() }
            func c() async throws { try await d() }
            func b() async throws { try await c() }
            func a() async throws { try await b() }

            /// @lint.context replayable
            func handler() async throws { try await a() }
            """
        ]
        let issues = runContext(files).detectedIssues
        #expect(issues.count == 1)
        let issue = try #require(issues.first)
        #expect(issue.message.contains("5-hop chain"))
    }

    // MARK: - Order independence

    @Test
    func declarationOrderInsideOneFile_doesNotChangeResult() throws {
        // Same chain as `threeHopChain_resolves` but with declarations in
        // reverse order. Order-of-declaration must not affect the
        // fixed-point — the worklist re-walks until effects stabilise.
        let files: [String: String] = [
            "Reversed.swift": """
            /// @lint.context replayable
            func handler() async throws { try await a() }
            func a() async throws { try await b() }
            func b() async throws { try await c() }
            func c() async throws { try await sink() }

            /// @lint.effect non_idempotent
            func sink() async throws {}
            """
        ]
        let issues = runContext(files).detectedIssues
        #expect(issues.count == 1)
        let issue = try #require(issues.first)
        #expect(issue.message.contains("'a'"))
        #expect(issue.message.contains("3-hop chain"))
    }

    @Test
    func fileOrder_doesNotChangeResult() throws {
        // Same chain split across multiple files, exercising the cross-file
        // merge path. The dictionary iteration order over `fileCache` is
        // non-deterministic, so this test running stably is itself a
        // weak proof that the fixed-point doesn't depend on iteration
        // order. (Strong proof would require permuting and re-running.)
        let files: [String: String] = [
            "Handler.swift": """
            /// @lint.context replayable
            func handler() async throws { try await a() }
            """,
            "A.swift": "func a() async throws { try await b() }",
            "B.swift": "func b() async throws { try await c() }",
            "C.swift": "func c() async throws { try await sink() }",
            "Sink.swift": """
            /// @lint.effect non_idempotent
            func sink() async throws {}
            """
        ]
        let issues = runContext(files).detectedIssues
        #expect(issues.count == 1)
        let issue = try #require(issues.first)
        #expect(issue.message.contains("3-hop chain"))
    }

    // MARK: - Cycles do not loop

    @Test
    func mutualRecursionWithNonIdempotentLeaf_terminates() throws {
        // a calls b; b calls a; b also calls sink (declared non_idempotent).
        // Naive iteration without an exit condition would loop forever as
        // depth keeps rising. The depth cap and effect-equality termination
        // jointly prevent that.
        let files: [String: String] = [
            "Cycle.swift": """
            /// @lint.effect non_idempotent
            func sink() async throws {}

            func a() async throws { try await b() }
            func b() async throws {
                try await a()
                try await sink()
            }

            /// @lint.context replayable
            func handler() async throws { try await a() }
            """
        ]
        let issues = runContext(files).detectedIssues
        // Both `a` and `b` end up upward-inferred non_idempotent (b directly
        // from sink; a through b after the second pass). Only handler→a is
        // checked here; one diagnostic.
        #expect(issues.count == 1)
        let issue = try #require(issues.first)
        #expect(issue.message.contains("'a'"))
        // Depth from the cycle is bounded by maxHops (5). Don't assert an
        // exact depth — different convergence orderings could legally
        // produce 2, 3, 4, or 5 here. Just assert the chain hint is
        // present (depth > 1).
        #expect(issue.message.contains("hop chain"))
    }

    @Test
    func pureCycleNoLeaf_producesNoInference() {
        // a calls b, b calls a. Neither calls anything declared or
        // heuristically inferable. The lub of an empty/cyclic-only callee
        // set is undefined, so neither function gets an inferred effect.
        // Crucial: must not infinite-loop trying to converge.
        let files: [String: String] = [
            "PureCycle.swift": """
            func a() async throws { try await b() }
            func b() async throws { try await a() }

            /// @lint.context replayable
            func handler() async throws { try await a() }
            """
        ]
        #expect(runContext(files).detectedIssues.isEmpty)
    }

    // MARK: - Declared still wins at any depth

    @Test
    func declaredIdempotentAnywhereInChain_stopsPropagation() {
        // a (un-annotated) -> b (DECLARED idempotent) -> sink (non_idempotent)
        // b's annotation is authoritative; upward inference does not run on
        // b. So a's only callee resolves as `idempotent`, and a inherits
        // `idempotent`. handler → a is silent.
        // (Whether b → sink fires is the IdempotencyViolation rule's job,
        // separately tested. This test isolates the propagation behaviour.)
        let files: [String: String] = [
            "Chain.swift": """
            /// @lint.effect non_idempotent
            func sink() async throws {}

            /// @lint.effect idempotent
            func b() async throws { try await sink() }

            func a() async throws { try await b() }

            /// @lint.context replayable
            func handler() async throws { try await a() }
            """
        ]
        // handler→a is silent because a is upward-inferred idempotent
        // through b's declared annotation.
        let contextIssues = runContext(files).detectedIssues
        #expect(contextIssues.isEmpty)
    }

    // MARK: - Heuristic-downward leaves still anchor chains

    @Test
    func heuristicDownwardLeaf_anchorsMultiHopChain() throws {
        // Same chain shape but the leaf is inferred by the downward heuristic
        // (`insert` matches the non-idempotent name whitelist) rather than
        // declared. Multi-hop should still propagate up the chain.
        let files: [String: String] = [
            "Chain.swift": """
            func leaf() async throws { insert(1) }
            func mid() async throws { try await leaf() }
            func top() async throws { try await mid() }

            /// @lint.context replayable
            func handler() async throws { try await top() }
            """
        ]
        let issues = runContext(files).detectedIssues
        #expect(issues.count == 1)
        let issue = try #require(issues.first)
        #expect(issue.message.contains("'top'"))
        #expect(issue.message.contains("hop chain"))
    }

    // MARK: - Idempotency violation rule (not just retry context)

    @Test
    func idempotentCallerThroughTwoHopChain_flags() throws {
        // process @lint.effect idempotent
        //   -> helper (un-annotated)
        //     -> middle (un-annotated)
        //       -> sink @lint.effect non_idempotent
        // The IdempotencyViolation rule fires on idempotent→non_idempotent
        // resolved through the multi-hop chain.
        let files: [String: String] = [
            "Chain.swift": """
            /// @lint.effect non_idempotent
            func sink() async throws {}

            func middle() async throws { try await sink() }
            func helper() async throws { try await middle() }

            /// @lint.effect idempotent
            func process() async throws { try await helper() }
            """
        ]
        let issues = runEffect(files).detectedIssues
        #expect(issues.count == 1)
        let issue = try #require(issues.first)
        #expect(issue.ruleName == .idempotencyViolation)
        #expect(issue.message.contains("'helper'"))
        #expect(issue.message.contains("2-hop chain"))
    }

    // MARK: - Symbol-table-level depth introspection

    @Test
    func upwardInferenceExposesDepthOnSymbolTable() throws {
        // Direct symbol-table API check — independent of any rule visitor.
        // Verifies that depth values are recorded and queryable so future
        // tooling can surface them without going through diagnostics.
        let source = Parser.parse(source: """
        /// @lint.effect non_idempotent
        func sink() async throws {}

        func leaf() async throws { try await sink() }
        func mid() async throws { try await leaf() }
        func top() async throws { try await mid() }
        """)
        var table = EffectSymbolTable()
        table.merge(source: source)
        table.applyUpwardInference(
            to: [source],
            multiHop: true,
            heuristicEffectForCall: { HeuristicEffectInferrer.infer(call: $0) }
        )

        let leafSig = FunctionSignature(name: "leaf", argumentLabels: [])
        let midSig = FunctionSignature(name: "mid", argumentLabels: [])
        let topSig = FunctionSignature(name: "top", argumentLabels: [])

        let leaf = try #require(table.upwardInference(for: leafSig))
        let mid = try #require(table.upwardInference(for: midSig))
        let top = try #require(table.upwardInference(for: topSig))

        #expect(leaf.effect == .nonIdempotent)
        #expect(leaf.depth == 1)
        #expect(mid.effect == .nonIdempotent)
        #expect(mid.depth == 2)
        #expect(top.effect == .nonIdempotent)
        #expect(top.depth == 3)
    }

    // MARK: - Wall-clock budget (pathological-corpus safety net)

    @Test
    func wallClockBudgetExpired_skipsInference() {
        // Defensive guard for large corpora where a single upward-inference
        // pass can run for minutes (the swift-nio case — 258 files ×
        // ~346 LOC average produced a 12-minute hang before this guard
        // shipped). A zero budget means the deadline has already passed
        // by the time the inner-loop check runs, so no source is
        // processed. Useful primarily as a degenerate regression guard
        // that the budget parameter is actually wired in and checked.
        let source = Parser.parse(source: """
        /// @lint.effect non_idempotent
        func sink() async throws {}

        func leaf() async throws { try await sink() }
        func mid() async throws { try await leaf() }
        """)
        var table = EffectSymbolTable()
        table.merge(source: source)
        table.applyUpwardInferenceImportAware(
            to: [source],
            multiHop: true,
            wallClockBudget: .zero,
            heuristicEffectForCall: { _, _ in nil }
        )

        let leafSig = FunctionSignature(name: "leaf", argumentLabels: [])
        let midSig = FunctionSignature(name: "mid", argumentLabels: [])

        // Zero budget ⇒ no work ⇒ no inference recorded.
        #expect(table.upwardInferredEffect(for: leafSig) == nil)
        #expect(table.upwardInferredEffect(for: midSig) == nil)
    }

    @Test
    func wallClockBudgetGenerous_inferenceStillLands() {
        // Sanity check the happy path: a generous budget on a tiny
        // corpus does NOT interfere with normal inference. Ensures the
        // guard isn't a correctness regression on small inputs.
        let source = Parser.parse(source: """
        /// @lint.effect non_idempotent
        func sink() async throws {}

        func leaf() async throws { try await sink() }
        func mid() async throws { try await leaf() }
        """)
        var table = EffectSymbolTable()
        table.merge(source: source)
        table.applyUpwardInferenceImportAware(
            to: [source],
            multiHop: true,
            wallClockBudget: .seconds(30),
            heuristicEffectForCall: { _, _ in nil }
        )

        let leafSig = FunctionSignature(name: "leaf", argumentLabels: [])
        let midSig = FunctionSignature(name: "mid", argumentLabels: [])

        #expect(table.upwardInferredEffect(for: leafSig) == .nonIdempotent)
        #expect(table.upwardInferredEffect(for: midSig) == .nonIdempotent)
    }

    // MARK: - One-hop default still works for callers that opt out

    @Test
    func multiHopDefaultIsOff_onSymbolTable() {
        // Direct API verification: `applyUpwardInference` defaults to
        // `multiHop: false`. A two-hop chain through that default-off
        // table produces the one-hop result (only the direct caller of
        // the leaf is inferred).
        let source = Parser.parse(source: """
        /// @lint.effect non_idempotent
        func sink() async throws {}

        func leaf() async throws { try await sink() }
        func mid() async throws { try await leaf() }
        """)
        var table = EffectSymbolTable()
        table.merge(source: source)
        table.applyUpwardInference(
            to: [source],
            heuristicEffectForCall: { HeuristicEffectInferrer.infer(call: $0) }
        )

        let leafSig = FunctionSignature(name: "leaf", argumentLabels: [])
        let midSig = FunctionSignature(name: "mid", argumentLabels: [])

        // One-hop: leaf inferred, mid not.
        #expect(table.upwardInferredEffect(for: leafSig) == .nonIdempotent)
        #expect(table.upwardInferredEffect(for: midSig) == nil)
    }
}
