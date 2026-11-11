import SwiftEffectInference
import SwiftParser
import SwiftProjectLintModels
@testable import SwiftProjectLintVisitors
import Testing

extension MultiHopUpwardInferenceTests {
    // MARK: - Heuristic-downward leaves still anchor chains

    @Test
    func heuristicDownwardLeaf_anchorsMultiHopChain() throws {
        // Same chain shape but the leaf is inferred by the downward heuristic
        // (`insert` matches the non-idempotent name allowlist) rather than
        // declared. Multi-hop should still propagate up the chain.
        let files: [String: String] = [
            "Chain.swift": """
            func leaf() async throws { insert(1) }
            func mid() async throws { try await leaf() }
            func top() async throws { try await mid() }

            /// @lint.context replayable
            func handler() async throws { try await top() }
            """,
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
            """,
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
        table.applyBodyInference(to: [source], multiHop: true) {
            HeuristicEffectInferrer.infer(call: $0)
        }

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
        table.applyBodyInference(
            to: [source],
            multiHop: true,
            wallClockBudget: .zero
        ) { _, _ in nil }

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
        table.applyBodyInference(
            to: [source],
            multiHop: true,
            wallClockBudget: .seconds(30)
        ) { _, _ in nil }

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
        table.applyBodyInference(to: [source]) {
            HeuristicEffectInferrer.infer(call: $0)
        }

        let leafSig = FunctionSignature(name: "leaf", argumentLabels: [])
        let midSig = FunctionSignature(name: "mid", argumentLabels: [])

        // One-hop: leaf inferred, mid not.
        #expect(table.upwardInferredEffect(for: leafSig) == .nonIdempotent)
        #expect(table.upwardInferredEffect(for: midSig) == nil)
    }
}
