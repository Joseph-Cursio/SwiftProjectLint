import SwiftParser
@testable import SwiftProjectLintIdempotencyRules
import SwiftProjectLintModels
@testable import SwiftProjectLintVisitors
import SwiftSyntax
import Testing

/// Shared test helpers for the once-contract suites. Each suite below
/// drives the rule through this same harness; the splits exist only to
/// keep individual suites under SwiftLint's 300-line type-body cap.
func runOnceContractRule(
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
struct OnceContractViolationTests {

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
            """,
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
            """,
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
            """,
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
            """,
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
            """,
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
            """,
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
            """,
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
            """,
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
            """,
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
            """,
        ]
        let issues = runRule(files).detectedIssues
        #expect(issues.count == 1)
        let issue = try #require(issues.first)
        #expect(issue.filePath == "Caller.swift")
    }
}
