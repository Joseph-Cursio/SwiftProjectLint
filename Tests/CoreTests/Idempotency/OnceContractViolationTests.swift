import Testing
@testable import SwiftProjectLintIdempotencyRules
@testable import SwiftProjectLintVisitors
import SwiftSyntax
import SwiftParser

/// Shared test helpers for the once-contract suites. Each suite below
/// drives the rule through this same harness; the splits exist only to
/// keep individual suites under SwiftLint's 300-line type-body cap.
private func runOnceContractRule(
    _ files: [String: String]
) -> OnceContractViolationVisitor {
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

/// Positive-trigger fixtures: every test here expects the rule to fire.
/// Covers the loop case, the replayable / retry_safe case, the combined
/// case, and cross-file resolution.
@Suite
struct OnceContractViolationTriggerTests {

    private func runRule(_ files: [String: String]) -> OnceContractViolationVisitor {
        runOnceContractRule(files)
    }

    // MARK: - Loop triggers

    @Test
    func onceCallInsideForLoop_fires() throws {
        let files: [String: String] = [
            "All.swift": """
            /// @lint.context once
            func bootstrap() {}

            func runAll(_ items: [Int]) {
                for _ in items {
                    bootstrap()
                }
            }
            """
        ]
        let issues = runRule(files).detectedIssues
        #expect(issues.count == 1)
        let issue = try #require(issues.first)
        #expect(issue.ruleName == .onceContractViolation)
        #expect(issue.message.contains("'bootstrap'"))
        #expect(issue.message.contains("inside a loop"))
    }

    @Test
    func onceCallInsideWhileLoop_fires() throws {
        let files: [String: String] = [
            "All.swift": """
            /// @lint.context once
            func bootstrap() {}

            func runAll() {
                var keepGoing = true
                while keepGoing {
                    bootstrap()
                    keepGoing = false
                }
            }
            """
        ]
        let issues = runRule(files).detectedIssues
        #expect(issues.count == 1)
        let issue = try #require(issues.first)
        #expect(issue.message.contains("inside a loop"))
    }

    @Test
    func onceCallInsideRepeatLoop_fires() throws {
        let files: [String: String] = [
            "All.swift": """
            /// @lint.context once
            func bootstrap() {}

            func runAll() {
                var done = false
                repeat {
                    bootstrap()
                    done = true
                } while !done
            }
            """
        ]
        let issues = runRule(files).detectedIssues
        #expect(issues.count == 1)
        let issue = try #require(issues.first)
        #expect(issue.message.contains("inside a loop"))
    }

    @Test
    func onceCallInForLoopIterationSource_doesNotFire() {
        // The iteration source of a `for` loop evaluates once per loop
        // entry, not per iteration. Calls there are NOT in-loop.
        let files: [String: String] = [
            "All.swift": """
            /// @lint.context once
            func bootstrap() -> [Int] { [] }

            func runAll() {
                for _ in bootstrap() {
                    print("hi")
                }
            }
            """
        ]
        // `bootstrap()` runs exactly once (the source of the for-in).
        // No diagnostic.
        #expect(runRule(files).detectedIssues.isEmpty)
    }

    @Test
    func onceCallInWhileCondition_doesNotFire() {
        // Mirror of the for-loop case: `while bootstrap() { }` runs the
        // condition more than once IF the loop iterates, but our policy
        // treats the condition expression itself as not-in-loop because
        // it's the loop control, not the body. This intentionally
        // matches the conservative direction — we'd rather miss a
        // pathological `while bootstrap()` than false-positive on a
        // legitimate one-shot `while shouldRetry()` style.
        let files: [String: String] = [
            "All.swift": """
            /// @lint.context once
            func bootstrap() -> Bool { false }

            func runAll() {
                while bootstrap() {
                    print("hi")
                }
            }
            """
        ]
        #expect(runRule(files).detectedIssues.isEmpty)
    }

    @Test
    func onceCallNestedInsideTwoLoops_firesOnce() throws {
        // Single call site → single diagnostic, regardless of nesting depth.
        let files: [String: String] = [
            "All.swift": """
            /// @lint.context once
            func bootstrap() {}

            func runAll(_ outer: [Int], _ inner: [Int]) {
                for _ in outer {
                    for _ in inner {
                        bootstrap()
                    }
                }
            }
            """
        ]
        let issues = runRule(files).detectedIssues
        #expect(issues.count == 1)
        let issue = try #require(issues.first)
        #expect(issue.message.contains("inside a loop"))
    }

    // MARK: - Replayable-context triggers

    @Test
    func onceCallFromReplayableBody_fires() throws {
        let files: [String: String] = [
            "All.swift": """
            /// @lint.context once
            func bootstrap() {}

            /// @lint.context replayable
            func handle() {
                bootstrap()
            }
            """
        ]
        let issues = runRule(files).detectedIssues
        #expect(issues.count == 1)
        let issue = try #require(issues.first)
        #expect(issue.ruleName == .onceContractViolation)
        #expect(issue.message.contains("'bootstrap'"))
        #expect(issue.message.contains("replayable"))
    }

    @Test
    func onceCallFromRetrySafeBody_fires() throws {
        let files: [String: String] = [
            "All.swift": """
            /// @lint.context once
            func bootstrap() {}

            /// @lint.context retry_safe
            func handle() {
                bootstrap()
            }
            """
        ]
        let issues = runRule(files).detectedIssues
        #expect(issues.count == 1)
        let issue = try #require(issues.first)
        #expect(issue.message.contains("retry_safe"))
    }

    // MARK: - Combined trigger

    @Test
    func onceCallInLoopWithinReplayable_singleDiagnostic() throws {
        let files: [String: String] = [
            "All.swift": """
            /// @lint.context once
            func bootstrap() {}

            /// @lint.context replayable
            func handle(_ items: [Int]) {
                for _ in items {
                    bootstrap()
                }
            }
            """
        ]
        let issues = runRule(files).detectedIssues
        // One call site → one diagnostic, mentioning both triggers.
        #expect(issues.count == 1)
        let issue = try #require(issues.first)
        #expect(issue.message.contains("inside a loop"))
        #expect(issue.message.contains("replayable"))
        #expect(issue.message.contains("compounds"))
    }

    // MARK: - Cross-file resolution

    @Test
    func crossFile_calleeAndCallerInDifferentFiles() throws {
        let files: [String: String] = [
            "Callee.swift": """
            /// @lint.context once
            func bootstrap() {}
            """,
            "Caller.swift": """
            func runAll(_ items: [Int]) {
                for _ in items {
                    bootstrap()
                }
            }
            """
        ]
        let issues = runRule(files).detectedIssues
        #expect(issues.count == 1)
        let issue = try #require(issues.first)
        #expect(issue.filePath == "Caller.swift")
    }
}

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
        var table = EffectSymbolTable()
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
            """
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
            """
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
            """
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
            """
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
            """
        ]
        let issues = runRule(files).detectedIssues
        #expect(issues.count == 1)
        let issue = try #require(issues.first)
        #expect(issue.message.contains("'helper'"))
        #expect(issue.message.contains("transitively reaches"))
        #expect(issue.message.contains("1-hop chain"))
    }
}
