@testable import Core
import SwiftParser
@testable import SwiftProjectLintRules
import SwiftSyntax
import Testing

@Suite
struct TestMissingAssertionVisitorTests {

    private func makeVisitor() -> TestMissingAssertionVisitor {
        TestMissingAssertionVisitor(patternCategory: .codeQuality)
    }

    private func run(_ visitor: TestMissingAssertionVisitor, source: String) {
        visitor.walk(Parser.parse(source: source))
        visitor.finalizeAnalysis()
    }

    // MARK: - Positive Cases (should trigger)

    @Test
    func detectsTestWithNoAssertions() throws {
        let visitor = makeVisitor()
        run(visitor, source: """
        @Test
        func testSomething() {
            let result = compute()
            print(result)
        }
        """)
        let issue = try #require(visitor.detectedIssues.first)
        #expect(visitor.detectedIssues.count == 1)
        #expect(issue.ruleName == .testMissingAssertion)
        #expect(issue.severity == .warning)
        #expect(issue.message.contains("testSomething"))
    }

    @Test
    func detectsEmptyTestBody() throws {
        let visitor = makeVisitor()
        run(visitor, source: """
        @Test
        func testEmpty() {
        }
        """)
        let issue = try #require(visitor.detectedIssues.first)
        #expect(issue.ruleName == .testMissingAssertion)
    }

    @Test
    func detectsTestWithOnlySetup() throws {
        let visitor = makeVisitor()
        run(visitor, source: """
        @Test("Does setup only")
        func testSetupOnly() {
            let array = [1, 2, 3]
            let filtered = array.filter { $0 > 1 }
            _ = filtered.count
        }
        """)
        let issue = try #require(visitor.detectedIssues.first)
        #expect(issue.message.contains("testSetupOnly"))
    }

    @Test
    func detectsMultipleAssertionlessTests() {
        let visitor = makeVisitor()
        run(visitor, source: """
        @Test
        func testAlpha() {
            print("no assertion")
        }

        @Test
        func testBravo() {
            let _ = 42
        }
        """)
        #expect(visitor.detectedIssues.count == 2)
    }

    // MARK: - Negative Cases (should not trigger)

    @Test
    func ignoresTestWithExpect() {
        let visitor = makeVisitor()
        run(visitor, source: """
        @Test
        func testWithExpect() {
            #expect(1 == 1)
        }
        """)
        #expect(visitor.detectedIssues.isEmpty)
    }

    @Test
    func ignoresTestWithRequire() {
        let visitor = makeVisitor()
        run(visitor, source: """
        @Test
        func testWithRequire() throws {
            let val = try #require(optionalValue)
        }
        """)
        #expect(visitor.detectedIssues.isEmpty)
    }

    @Test
    func ignoresTestWithBothMacros() {
        let visitor = makeVisitor()
        run(visitor, source: """
        @Test
        func testWithBoth() throws {
            let val = try #require(optionalValue)
            #expect(val == 42)
        }
        """)
        #expect(visitor.detectedIssues.isEmpty)
    }

    @Test
    func ignoresNonTestFunctions() {
        let visitor = makeVisitor()
        run(visitor, source: """
        func helperFunction() {
            let value = compute()
            print(value)
        }
        """)
        #expect(visitor.detectedIssues.isEmpty)
    }

    @Test
    func ignoresTestWithNestedExpect() {
        let visitor = makeVisitor()
        run(visitor, source: """
        @Test
        func testNested() {
            let items = [1, 2, 3]
            for item in items {
                #expect(item > 0)
            }
        }
        """)
        #expect(visitor.detectedIssues.isEmpty)
    }

    // MARK: - Mixed Cases

    @Test
    func onlyFlagsTestsWithoutAssertions() throws {
        let visitor = makeVisitor()
        run(visitor, source: """
        @Test
        func testWithAssertion() {
            #expect(true)
        }

        @Test
        func testWithoutAssertion() {
            print("oops")
        }
        """)
        #expect(visitor.detectedIssues.count == 1)
        let issue = try #require(visitor.detectedIssues.first)
        #expect(issue.message.contains("testWithoutAssertion"))
    }

    // MARK: - Throw-as-assertion (#110)

    /// **A `throws` test whose assertion is the throw.** `try await command.run()` over a real
    /// fixture verifies that the command parses and runs end to end; if it throws, the test fails.
    /// `#expect(true)` beside it would assert strictly less.
    ///
    /// 13 false positives on one subject, all in a CLI integration suite that took its target from
    /// 23.8% to 86.1% coverage.
    @Test
    func ignoresBareTryAsAssertion() {
        let visitor = makeVisitor()
        run(visitor, source: """
        @Test
        func runsClassDiagram() async throws {
            var command = try Cmd.parse(["Models"])
            try await command.run()
        }
        """)
        #expect(visitor.detectedIssues.isEmpty)
    }

    /// The established `_ = try` spelling of the same idea keeps working.
    @Test
    func ignoresDiscardedTryAsAssertion() {
        let visitor = makeVisitor()
        run(visitor, source: """
        @Test
        func findsText() throws {
            _ = try view.inspect().find(text: "hi")
        }
        """)
        #expect(visitor.detectedIssues.isEmpty)
    }

    /// **The line this draws, and why it is not "any `try` in a `throws` test".** Every `try` here
    /// binds a value the test goes on to use — it is setup, and the test asserts nothing. Treating
    /// any `try` as an assertion would have silenced this, which is a true positive.
    @Test
    func stillFlagsATestWhoseEveryTryIsSetup() throws {
        let visitor = makeVisitor()
        run(visitor, source: """
        @Test
        func onlySetsUp() throws {
            let directory = try makeTempDirectory()
            let file = try write(to: directory)
        }
        """)
        let issue = try #require(visitor.detectedIssues.first)
        #expect(visitor.detectedIssues.count == 1)
        #expect(issue.message.contains("onlySetsUp"))
    }

    /// `try?` and `try!` do not propagate a failure, so neither is an assertion. `try!` traps —
    /// which `Test Missing Require` reports, and which is a different finding.
    @Test
    func stillFlagsWhenTheTryCannotPropagate() {
        let visitor = makeVisitor()
        run(visitor, source: """
        @Test
        func swallows() throws {
            try? sideEffect()
        }
        """)
        #expect(visitor.detectedIssues.count == 1)
    }

    /// `#expect(throws:)` is an `#expect`, and was already recognised. Pinned because the issue
    /// asked whether it was, and "already true" is worth a test rather than an assurance.
    @Test
    func ignoresExpectThrows() {
        let visitor = makeVisitor()
        run(visitor, source: """
        @Test
        func expectsThrow() {
            #expect(throws: MyError.self) { try risky() }
        }
        """)
        #expect(visitor.detectedIssues.isEmpty)
    }

    /// A discard that is not a `try` asserts nothing — `_ = issues` with a comment saying
    /// "exercising the code path is the goal" is a real finding in this repository.
    @Test
    func stillFlagsANonThrowingDiscard() {
        let visitor = makeVisitor()
        run(visitor, source: """
        @Test
        func coverageOnly() {
            let issues = walkSource(source, visitor: visitor)
            _ = issues
        }
        """)
        #expect(visitor.detectedIssues.count == 1)
    }
}
