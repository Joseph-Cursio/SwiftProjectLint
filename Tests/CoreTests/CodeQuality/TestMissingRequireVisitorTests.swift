import Testing
import SwiftSyntax
import SwiftParser
@testable import Core
@testable import SwiftProjectLintRules

@Suite
struct TestMissingRequireVisitorTests {

    private func makeVisitor() -> TestMissingRequireVisitor {
        TestMissingRequireVisitor(patternCategory: .codeQuality)
    }

    private func run(_ visitor: TestMissingRequireVisitor, source: String) {
        visitor.walk(Parser.parse(source: source))
    }

    // MARK: - Positive Cases (should trigger)

    @Test
    func detectsTestWithOnlyExpect() throws {
        let visitor = makeVisitor()
        run(visitor, source: """
        @Test
        func testSomething() {
            let result = compute()
            #expect(result == 42)
        }
        """)
        let issue = try #require(visitor.detectedIssues.first)
        #expect(visitor.detectedIssues.count == 1)
        #expect(issue.ruleName == .testMissingRequire)
        #expect(issue.severity == .info)
        #expect(issue.message.contains("testSomething"))
    }

    @Test
    func detectsTestWithNoAssertions() throws {
        let visitor = makeVisitor()
        run(visitor, source: """
        @Test
        func testSetup() {
            let value = createItem()
            print(value)
        }
        """)
        let issue = try #require(visitor.detectedIssues.first)
        #expect(issue.ruleName == .testMissingRequire)
    }

    @Test
    func detectsTestWithStringArgument() throws {
        let visitor = makeVisitor()
        run(visitor, source: """
        @Test("My descriptive test name")
        func testDescriptive() {
            #expect(true)
        }
        """)
        let issue = try #require(visitor.detectedIssues.first)
        #expect(issue.message.contains("testDescriptive"))
    }

    @Test
    func detectsMultipleTestsWithoutRequire() {
        let visitor = makeVisitor()
        run(visitor, source: """
        @Test
        func testAlpha() {
            #expect(1 == 1)
        }

        @Test
        func testBravo() {
            #expect(2 == 2)
        }
        """)
        #expect(visitor.detectedIssues.count == 2)
    }

    // MARK: - Negative Cases (should not trigger)

    @Test
    func ignoresTestWithRequire() {
        let visitor = makeVisitor()
        run(visitor, source: """
        @Test
        func testWithPrecondition() throws {
            let item = try #require(optionalItem)
            #expect(item.name == "expected")
        }
        """)
        #expect(visitor.detectedIssues.isEmpty)
    }

    @Test
    func ignoresTestWithRequireOnly() {
        let visitor = makeVisitor()
        run(visitor, source: """
        @Test
        func testUnwrap() throws {
            let val = try #require(fetchValue())
        }
        """)
        #expect(visitor.detectedIssues.isEmpty)
    }

    @Test
    func ignoresTestWithNestedRequire() {
        let visitor = makeVisitor()
        run(visitor, source: """
        @Test
        func testNested() throws {
            let items = [1, 2, 3]
            for item in items {
                let result = try #require(process(item))
                #expect(result > 0)
            }
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

        private func anotherHelper() -> Int {
            return 42
        }
        """)
        #expect(visitor.detectedIssues.isEmpty)
    }

    @Test
    func ignoresRegularFunctionsWithTestInName() {
        let visitor = makeVisitor()
        run(visitor, source: """
        func testLikeName() {
            print("not a real test")
        }
        """)
        #expect(visitor.detectedIssues.isEmpty)
    }

    // MARK: - Mixed Cases

    @Test
    func onlyFlagsTestsWithoutRequire() throws {
        let visitor = makeVisitor()
        run(visitor, source: """
        @Test
        func testWithRequire() throws {
            let val = try #require(optional)
            #expect(val == 1)
        }

        @Test
        func testWithoutRequire() {
            #expect(true)
        }
        """)
        #expect(visitor.detectedIssues.count == 1)
        let issue = try #require(visitor.detectedIssues.first)
        #expect(issue.message.contains("testWithoutRequire"))
    }
}
