import Testing
import SwiftSyntax
import SwiftParser
@testable import Core

@Suite
struct TestMissingAssertionVisitorTests {

    private func makeVisitor() -> TestMissingAssertionVisitor {
        TestMissingAssertionVisitor(patternCategory: .codeQuality)
    }

    private func run(_ visitor: TestMissingAssertionVisitor, source: String) {
        visitor.walk(Parser.parse(source: source))
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

    // swiftprojectlint:disable Test Missing Require
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

    // swiftprojectlint:disable Test Missing Require
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

    // swiftprojectlint:disable Test Missing Require
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

    // swiftprojectlint:disable Test Missing Require
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

    // swiftprojectlint:disable Test Missing Require
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

    // swiftprojectlint:disable Test Missing Require
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
}
