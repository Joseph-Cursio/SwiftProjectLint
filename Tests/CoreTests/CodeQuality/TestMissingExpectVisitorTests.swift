import Testing
import SwiftSyntax
import SwiftParser
@testable import Core

@Suite
struct TestMissingExpectVisitorTests {

    private func makeVisitor() -> TestMissingExpectVisitor {
        TestMissingExpectVisitor(patternCategory: .codeQuality)
    }

    private func run(_ visitor: TestMissingExpectVisitor, source: String) {
        visitor.walk(Parser.parse(source: source))
    }

    // MARK: - Positive Cases (should trigger)

    @Test
    func detectsTestWithOnlyRequire() throws {
        let visitor = makeVisitor()
        run(visitor, source: """
        @Test
        func testUnwrapOnly() throws {
            let val = try #require(fetchValue())
        }
        """)
        let issue = try #require(visitor.detectedIssues.first)
        #expect(visitor.detectedIssues.count == 1)
        #expect(issue.ruleName == .testMissingExpect)
        #expect(issue.severity == .info)
        #expect(issue.message.contains("testUnwrapOnly"))
    }

    @Test
    func detectsTestWithNoMacros() throws {
        let visitor = makeVisitor()
        run(visitor, source: """
        @Test
        func testNothing() {
            let result = compute()
            print(result)
        }
        """)
        let issue = try #require(visitor.detectedIssues.first)
        #expect(issue.ruleName == .testMissingExpect)
    }

    @Test
    func detectsTestWithDescriptiveName() throws {
        let visitor = makeVisitor()
        run(visitor, source: """
        @Test("Validates preconditions only")
        func testPreconditionsOnly() throws {
            let item = try #require(createItem())
            let child = try #require(item.children.first)
        }
        """)
        let issue = try #require(visitor.detectedIssues.first)
        #expect(issue.message.contains("testPreconditionsOnly"))
    }

    @Test
    func detectsMultipleTestsWithoutExpect() {
        let visitor = makeVisitor()
        run(visitor, source: """
        @Test
        func testAlpha() throws {
            let _ = try #require(optional)
        }

        @Test
        func testBravo() {
            print("no macros at all")
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
        func helperFunction() throws {
            let _ = try #require(something)
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
            for val in [1, 2, 3] {
                #expect(val > 0)
            }
        }
        """)
        #expect(visitor.detectedIssues.isEmpty)
    }

    // MARK: - Mixed Cases

    @Test
    func onlyFlagsTestsWithoutExpect() throws {
        let visitor = makeVisitor()
        run(visitor, source: """
        @Test
        func testWithExpect() {
            #expect(true)
        }

        @Test
        func testWithoutExpect() throws {
            let _ = try #require(value)
        }
        """)
        #expect(visitor.detectedIssues.count == 1)
        let issue = try #require(visitor.detectedIssues.first)
        #expect(issue.message.contains("testWithoutExpect"))
    }
}
