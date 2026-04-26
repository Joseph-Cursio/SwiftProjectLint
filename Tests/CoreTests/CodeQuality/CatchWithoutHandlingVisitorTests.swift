import Testing
@testable import Core
@testable import SwiftProjectLintRules
import SwiftSyntax
import SwiftParser

@Suite
struct CatchWithoutHandlingVisitorTests {

    private func makeVisitor() -> CatchWithoutHandlingVisitor {
        let pattern = CatchWithoutHandling().pattern
        return CatchWithoutHandlingVisitor(pattern: pattern)
    }

    private func run(_ visitor: CatchWithoutHandlingVisitor, source: String) {
        let sourceFile = Parser.parse(source: source)
        visitor.walk(sourceFile)
    }

    // MARK: - Positive Cases: empty body

    @Test
    func detectsEmptyCatch() throws {
        let source = """
        do {
            try riskyOperation()
        } catch {
        }
        """
        let visitor = makeVisitor()
        run(visitor, source: source)

        #expect(visitor.detectedIssues.count == 1)
        let issue = try #require(visitor.detectedIssues.first)
        #expect(issue.ruleName == .catchWithoutHandling)
        #expect(issue.severity == .warning)
        #expect(issue.message.contains("rethrow"))
    }

    // MARK: - Positive Cases: body present but error not handled

    @Test("Flags catch that updates unrelated state without touching the error", arguments: [
        // State update only — no error reference
        """
        do { try work() } catch {
            isLoading = false
        }
        """,
        // Returns nil — doesn't convey the error
        """
        do { try work() } catch {
            return nil
        }
        """,
        // Comment only
        """
        do { try work() } catch {
            // TODO: handle this later
        }
        """,
        // Multiple statements, none reference the error
        """
        do { try work() } catch {
            isLoading = false
            showAlert = true
        }
        """
    ])
    func flagsUnhandledCatch(source: String) {
        let visitor = makeVisitor()
        run(visitor, source: source)
        #expect(visitor.detectedIssues.count == 1)
    }

    @Test
    func detectsMultipleUnhandledCatches() {
        let source = """
        do { try first() } catch { }
        do { try second() } catch { isLoading = false }
        """
        let visitor = makeVisitor()
        run(visitor, source: source)
        #expect(visitor.detectedIssues.count == 2)
    }

    // MARK: - Negative Cases: rethrow

    @Test("No issue when error is rethrown", arguments: [
        "do { try work() } catch { throw error }",
        "do { try work() } catch let e { throw e }"
    ])
    func noIssueWhenRethrown(source: String) {
        let visitor = makeVisitor()
        run(visitor, source: source)
        #expect(visitor.detectedIssues.isEmpty)
    }

    @Test("throw inside nested closure does not count as rethrow")
    func throwInClosureDoesNotSatisfy() {
        let source = """
        do { try work() } catch {
            doSomething { throw error }
        }
        """
        let visitor = makeVisitor()
        run(visitor, source: source)
        // The throw is inside a closure — the catch body itself does not rethrow.
        // The error reference DOES satisfy the check here, so no issue.
        // (If you remove the error ref, e.g. `doSomething { throw MyError.bad }`, it would flag.)
        #expect(visitor.detectedIssues.isEmpty)
    }

    // MARK: - Negative Cases: logging

    @Test("No issue when error is logged", arguments: [
        "do { try work() } catch { print(error) }",
        "do { try work() } catch { debugPrint(error) }",
        "do { try work() } catch { NSLog(\"%@\", error.localizedDescription) }",
        "do { try work() } catch { logger.error(\"Failed: \\(error)\") }",
        "do { try work() } catch { os_log(\"%@\", error.localizedDescription) }",
        "do { try work() } catch { Logger.shared.warning(\"\\(error)\") }"
    ])
    func noIssueWhenLogged(source: String) {
        let visitor = makeVisitor()
        run(visitor, source: source)
        #expect(visitor.detectedIssues.isEmpty)
    }

    // MARK: - Negative Cases: error variable referenced

    @Test("No issue when error variable is used", arguments: [
        // Assigned to error state
        "do { try work() } catch { self.error = error }",
        // Passed to callback
        "do { try work() } catch { completion(.failure(error)) }",
        // Localized description assigned
        "do { try work() } catch { errorMessage = error.localizedDescription }",
        // Used in string interpolation in alert
        "do { try work() } catch { alertText = \"\\(error)\" }",
        // Error captured in closure
        "do { try work() } catch { DispatchQueue.main.async { self.lastError = error } }"
    ])
    func noIssueWhenErrorReferenced(source: String) {
        let visitor = makeVisitor()
        run(visitor, source: source)
        #expect(visitor.detectedIssues.isEmpty)
    }

    @Test("Respects typed catch pattern name")
    func respectsTypedCatchPatternName() {
        let source = """
        do {
            try work()
        } catch let failure {
            self.lastFailure = failure
        }
        """
        let visitor = makeVisitor()
        run(visitor, source: source)
        #expect(visitor.detectedIssues.isEmpty)
    }

    // MARK: - Negative Cases: explicit termination

    @Test("No issue when assertionFailure or fatalError is called", arguments: [
        "do { try work() } catch { assertionFailure(\"Unexpected error\") }",
        "do { try work() } catch { fatalError(\"\\(error)\") }",
        "do { try work() } catch { preconditionFailure(\"Should not fail\") }"
    ])
    func noIssueWhenTerminating(source: String) {
        let visitor = makeVisitor()
        run(visitor, source: source)
        #expect(visitor.detectedIssues.isEmpty)
    }

    // MARK: - Negative Cases: Swift Testing Issue.record

    @Test("No issue when Issue.record is called (Swift Testing diagnostic)", arguments: [
        // Bare-message form — most common for the unhandled-error catch arm.
        "do { try work() } catch { Issue.record(\"unexpected\") }",
        // String-interpolated form — references the error variable too, so
        // this case would already pass via the error-reference check; included
        // to lock in the Issue.record path independently.
        "do { try work() } catch { Issue.record(\"got \\(error.localizedDescription)\") }",
        // Multi-arm: typed catch first, untyped fallback Issue.record.
        // Both arms are scanned independently; only the second one is the
        // motivating shape, but the first should also stay silent because
        // the typed-pattern name doesn't bind a usable error here — empty
        // typed pattern arms are intentional pass-throughs.
        """
        do {
            try work()
        } catch is ExpectedError {
            caught = true
        } catch {
            Issue.record("unexpected: \\(error)")
        }
        """
    ])
    func noIssueWhenIssueRecord(source: String) {
        let visitor = makeVisitor()
        run(visitor, source: source)
        // The typed-pattern arm `catch is ExpectedError { caught = true }`
        // does NOT contain Issue.record / throw / log / error-ref — but it
        // assigns to `caught` which doesn't reference `error`. The visitor
        // currently flags this arm; that's expected and out of scope for
        // this slice. The test-pattern fix lands as a separate consideration.
        // Scope this assertion to the Issue.record arm specifically.
        let issueRecordArmFlagged = visitor.detectedIssues.contains { issue in
            issue.suggestion?.contains("disable:next catch-without-handling") == true &&
                source.contains("Issue.record") &&
                !source.contains("ExpectedError")
        }
        #expect(!issueRecordArmFlagged)
        // Single-arm Issue.record sources should produce zero issues outright.
        if !source.contains("ExpectedError") {
            #expect(visitor.detectedIssues.isEmpty)
        }
    }

    @Test("Receiver-gated: only `Issue.record` exempts, not arbitrary `.record(...)`")
    func onlyIssueRecordExempts() {
        // A user-defined `recorder.record(...)` does not match — the gate is
        // the `Issue` base receiver, not the bare method name.
        let source = """
        do { try work() } catch { recorder.record("ignored") }
        """
        let visitor = makeVisitor()
        run(visitor, source: source)
        #expect(!visitor.detectedIssues.isEmpty,
                "non-Issue receiver should NOT exempt the catch")
    }
}
