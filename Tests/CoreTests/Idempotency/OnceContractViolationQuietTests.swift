import SwiftEffectInference
import SwiftParser
@testable import SwiftProjectLintIdempotencyRules
import SwiftProjectLintModels
@testable import SwiftProjectLintVisitors
import SwiftSyntax
import Testing

/// Negative-case fixtures and locked-in Phase-1 limitations: every test
/// here expects the rule to stay silent (or, for the parser smoke test,
/// expects the annotation to be readable but produce no diagnostic on
/// its own).
@Suite
struct OnceContractViolationQuietTests {

    private func runRule(_ files: [String: String]) -> OnceContractViolationVisitor {
        runOnceContractRule(files)
    }

    // MARK: - Annotation parser smoke test
    //
    // The grammar extension is exercised end-to-end by the rule fixtures,
    // but a dedicated parse check protects against silent regression of
    // the `once` token.

    @Test
    func parsesOnceContextAnnotation() {
        let source = Parser.parse(source: """
        /// @lint.context once
        func bootstrap() {}
        """)
        var table = ContextSymbolTable()
        table.merge(source: source)
        let signature = FunctionSignature(name: "bootstrap", argumentLabels: [])
        #expect(table.context(for: signature) == .once)
    }

    // MARK: - Negative cases

    @Test
    func onceCallFromOrdinaryBody_doesNotFire() {
        // No loop, no replayable / retry_safe annotation on the caller.
        // The once-callee's contract isn't violated by a single direct call.
        let files: [String: String] = [
            "All.swift": """
            /// @lint.context once
            func bootstrap() {}

            func main() {
                bootstrap()
            }
            """,
        ]
        #expect(runRule(files).detectedIssues.isEmpty)
    }

    @Test
    func unannotatedCallee_doesNotFire() {
        // Loop is fine when the callee makes no once-claim.
        let files: [String: String] = [
            "All.swift": """
            func bootstrap() {}

            func runAll(_ items: [Int]) {
                for _ in items {
                    bootstrap()
                }
            }
            """,
        ]
        #expect(runRule(files).detectedIssues.isEmpty)
    }

    @Test
    func collisionWithdrawnCallee_doesNotFire() {
        // Two annotated declarations of the same signature with conflicting
        // contexts withdraw the entry. The rule sees nothing for that
        // signature and stays silent.
        let files: [String: String] = [
            "A.swift": """
            /// @lint.context once
            func bootstrap() {}
            """,
            "B.swift": """
            /// @lint.context replayable
            func bootstrap() {}
            """,
            "Caller.swift": """
            func runAll(_ items: [Int]) {
                for _ in items {
                    bootstrap()
                }
            }
            """,
        ]
        #expect(runRule(files).detectedIssues.isEmpty)
    }

    @Test
    func onceCallInsideEscapingTaskClosureInsideLoop_doesNotFire_knownLimitation() {
        // Phase 1 closure-escape policy: stops at `Task { }`, matching the
        // other idempotency visitors. The Task body re-runs whenever the
        // outer loop re-spawns it, so this IS a real bug — but detecting
        // it cleanly requires cross-construct reasoning that the other
        // rules also defer. Locked in as intentional.
        let files: [String: String] = [
            "All.swift": """
            /// @lint.context once
            func bootstrap() {}

            func runAll(_ items: [Int]) {
                for _ in items {
                    Task {
                        bootstrap()
                    }
                }
            }
            """,
        ]
        #expect(
            runRule(files).detectedIssues.isEmpty,
            "Phase 1 stops at escaping closures; loop-spawned Task is a known false-negative"
        )
    }

    @Test
    func transitiveChainCaughtViaOnceReachInference() throws {
        // helper (un-annotated) -> bootstrap (@context once)
        // runAll has a loop calling helper, NOT bootstrap directly.
        //
        // Once-reach inference (Phase 2): helper's body reaches a
        // `@context once` callee at depth 1. runAll's loop calls helper,
        // and the rule fires with `via 1-hop chain` in the diagnostic.
        let files: [String: String] = [
            "All.swift": """
            /// @lint.context once
            func bootstrap() {}

            func helper() {
                bootstrap()
            }

            func runAll(_ items: [Int]) {
                for _ in items {
                    helper()
                }
            }
            """,
        ]
        let issues = runRule(files).detectedIssues
        #expect(issues.count == 1)
        let issue = try #require(issues.first)
        #expect(issue.message.contains("'helper'"))
        #expect(issue.message.contains("transitively reaches"))
        #expect(issue.message.contains("1-hop chain"))
    }
}
