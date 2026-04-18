import Testing
@testable import Core
@testable import SwiftProjectLintRules
@testable import SwiftProjectLintVisitors
import SwiftSyntax
import SwiftParser

/// Transitive-propagation fixtures for the once-contract rule.
///
/// Direct call sites are exercised by `OnceContractViolationTriggerTests`.
/// This suite exercises the once-reach inference layer specifically:
/// chains of un-annotated helpers between the trigger position (loop or
/// replayable body) and the `@lint.context once` callee.
@Suite
struct OnceReachTransitiveTests {

    private func runRule(_ files: [String: String]) -> OnceContractViolationVisitor {
        let cache: [String: SourceFileSyntax] = files.mapValues { Parser.parse(source: $0) }
        let visitor = OnceContractViolationVisitor(fileCache: cache)
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

    // MARK: - Multi-hop chains

    @Test
    func threeHopChain_resolves() throws {
        // a → b → c → bootstrap (declared @context once)
        // a's reach depth: 3 (3 hops to reach the once-callee).
        // runAll's loop call to a fires with `3-hop chain` in the message.
        let files: [String: String] = [
            "Chain.swift": """
            /// @lint.context once
            func bootstrap() {}

            func c() { bootstrap() }
            func b() { c() }
            func a() { b() }

            func runAll(_ items: [Int]) {
                for _ in items {
                    a()
                }
            }
            """
        ]
        let issues = runRule(files).detectedIssues
        #expect(issues.count == 1)
        let issue = try #require(issues.first)
        #expect(issue.message.contains("'a'"))
        #expect(issue.message.contains("3-hop chain"))
    }

    @Test
    func fiveHopChain_resolvesAndSaturatesAtMaxHops() throws {
        // Chain depth 5, equal to the default maxHops cap. Convergence
        // should still happen and the recorded depth should be 5.
        let files: [String: String] = [
            "Chain.swift": """
            /// @lint.context once
            func bootstrap() {}

            func e() { bootstrap() }
            func d() { e() }
            func c() { d() }
            func b() { c() }
            func a() { b() }

            func runAll() {
                for _ in 0..<3 {
                    a()
                }
            }
            """
        ]
        let issues = runRule(files).detectedIssues
        #expect(issues.count == 1)
        let issue = try #require(issues.first)
        #expect(issue.message.contains("5-hop chain"))
    }

    // MARK: - Order independence

    @Test
    func declarationOrderInsideOneFile_doesNotChangeResult() throws {
        // Same chain as `threeHopChain_resolves` but in reverse declaration
        // order. Fixed-point iteration must not depend on declaration order.
        let files: [String: String] = [
            "Reversed.swift": """
            func runAll(_ items: [Int]) {
                for _ in items {
                    a()
                }
            }
            func a() { b() }
            func b() { c() }
            func c() { bootstrap() }

            /// @lint.context once
            func bootstrap() {}
            """
        ]
        let issues = runRule(files).detectedIssues
        #expect(issues.count == 1)
        let issue = try #require(issues.first)
        #expect(issue.message.contains("3-hop chain"))
    }

    @Test
    func fileOrder_doesNotChangeResult() throws {
        // Chain split across multiple files in arbitrary fileCache
        // iteration order. Stable resolution is itself a weak proof of
        // order-independence.
        let files: [String: String] = [
            "Caller.swift": """
            func runAll(_ items: [Int]) {
                for _ in items {
                    a()
                }
            }
            """,
            "A.swift": "func a() { b() }",
            "B.swift": "func b() { c() }",
            "C.swift": "func c() { bootstrap() }",
            "Bootstrap.swift": """
            /// @lint.context once
            func bootstrap() {}
            """
        ]
        let issues = runRule(files).detectedIssues
        #expect(issues.count == 1)
        let issue = try #require(issues.first)
        #expect(issue.message.contains("3-hop chain"))
    }

    // MARK: - Termination on cycles

    @Test
    func mutualRecursionWithOnceLeaf_terminates() throws {
        // a calls b; b calls a; b also calls bootstrap. A loop around
        // a should fire once (depth bounded by the cycle's interaction
        // with the once-leaf). Critical: must not infinite-loop.
        let files: [String: String] = [
            "Cycle.swift": """
            /// @lint.context once
            func bootstrap() {}

            func a() { b() }
            func b() {
                a()
                bootstrap()
            }

            func runAll() {
                for _ in 0..<3 {
                    a()
                }
            }
            """
        ]
        let issues = runRule(files).detectedIssues
        #expect(issues.count == 1)
        let issue = try #require(issues.first)
        #expect(issue.message.contains("'a'"))
        #expect(issue.message.contains("hop chain"))
    }

    @Test
    func pureCycleNoOnceLeaf_producesNoDiagnostic() {
        // a → b → a, neither reaches a `@context once` callee.
        // Reach inference must produce nothing AND not loop forever.
        let files: [String: String] = [
            "Cycle.swift": """
            func a() { b() }
            func b() { a() }

            func runAll() {
                for _ in 0..<3 {
                    a()
                }
            }
            """
        ]
        #expect(runRule(files).detectedIssues.isEmpty)
    }

    // MARK: - Annotated intermediates block propagation

    @Test
    func annotatedReplayableHelperDoesNotPropagateReach() throws {
        // helper is annotated `@context replayable`. The DIRECT call from
        // helper to bootstrap fires the existing direct rule. The OUTER
        // call to helper from runAll's loop should NOT fire transitively
        // — annotated context decls are excluded from reach inference,
        // so helper is not in the reach map.
        let files: [String: String] = [
            "All.swift": """
            /// @lint.context once
            func bootstrap() {}

            /// @lint.context replayable
            func helper() {
                bootstrap()
            }

            func runAll() {
                for _ in 0..<3 {
                    helper()
                }
            }
            """
        ]
        let issues = runRule(files).detectedIssues
        // Exactly one diagnostic: the direct replayable→once edge inside
        // helper's body. The outer loop call to helper produces nothing
        // because helper isn't in the reach map.
        #expect(issues.count == 1)
        let issue = try #require(issues.first)
        #expect(issue.message.contains("'helper'"))
        #expect(issue.message.contains("'bootstrap'"))
        // The diagnostic is the direct one (replayable body), not a
        // transitive chain message.
        #expect(issue.message.contains("transitively") == false)
    }

    @Test
    func annotatedOnceCalleeStillTakesDirectPath() throws {
        // The DIRECT callee at the call site is `@context once` itself.
        // The reach map may also have an entry for `bootstrap` (it
        // trivially reaches itself? — actually no, the inference excludes
        // any `@lint.context`-annotated function from the COLLECTOR), so
        // we get one diagnostic via the direct path, with the
        // `is declared @lint.context once` prose, not the transitive
        // prose.
        let files: [String: String] = [
            "All.swift": """
            /// @lint.context once
            func bootstrap() {}

            func runAll() {
                for _ in 0..<3 {
                    bootstrap()
                }
            }
            """
        ]
        let issues = runRule(files).detectedIssues
        #expect(issues.count == 1)
        let issue = try #require(issues.first)
        // Direct-path prose, not transitive prose.
        #expect(issue.message.contains("is declared `@lint.context once`"))
        #expect(issue.message.contains("transitively") == false)
    }

    // MARK: - Replayable caller + transitive reach

    @Test
    func replayableCallerCallsTransitivelyReachingHelper_fires() throws {
        // Same shape as the loop case but the trigger is the
        // `@context replayable` body, not a loop.
        let files: [String: String] = [
            "All.swift": """
            /// @lint.context once
            func bootstrap() {}

            func helper() { bootstrap() }

            /// @lint.context replayable
            func handle() {
                helper()
            }
            """
        ]
        let issues = runRule(files).detectedIssues
        #expect(issues.count == 1)
        let issue = try #require(issues.first)
        #expect(issue.message.contains("'helper'"))
        #expect(issue.message.contains("transitively reaches"))
        #expect(issue.message.contains("1-hop chain"))
        #expect(issue.message.contains("replayable"))
    }

    // MARK: - Symbol-table-level inspection

    @Test
    func onceReachExposesShortestPathDepth() throws {
        // Direct API check: when there are TWO paths to a once-callee of
        // different lengths, the recorded depth is the SHORTER one.
        // a directly calls bootstrap (depth 1) AND calls b which reaches
        // bootstrap at depth 2 (so a's longest path is 3, shortest is 1).
        // We record 1.
        let source = Parser.parse(source: """
        /// @lint.context once
        func bootstrap() {}

        func b() { bootstrap() }    // reach depth 1
        func a() {                  // reach depth = 1 + min(direct(0), b(1)) = 1
            bootstrap()
            b()
        }
        """)
        var table = EffectSymbolTable()
        table.merge(source: source)
        table.applyOnceReachInference(to: [source])

        let aSig = FunctionSignature(name: "a", argumentLabels: [])
        let bSig = FunctionSignature(name: "b", argumentLabels: [])
        let bootstrapSig = FunctionSignature(name: "bootstrap", argumentLabels: [])

        let aReach = try #require(table.onceReach(for: aSig))
        let bReach = try #require(table.onceReach(for: bSig))

        #expect(aReach.depth == 1, "a calls bootstrap directly — shortest path is 1")
        #expect(bReach.depth == 1, "b calls bootstrap directly")
        // bootstrap is annotated, so the reach inference excludes it
        // from the reach map (annotated decls are authoritative).
        #expect(table.onceReach(for: bootstrapSig) == nil)
    }
}
