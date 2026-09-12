@testable import Core
import SwiftParser
@testable import SwiftProjectLintRules
import SwiftSyntax
import Testing

/// The rule fires where a test would **trap**, not where it merely lacks `#require`.
///
/// Every "positive case" in the previous version of this suite is now a negative one, and that is
/// the point rather than an accident: they asserted that an `#expect`-only test is a finding, which
/// is the correct and normal shape for most tests. The rule fired on almost the entire suite —
/// 1,341 findings on one subject, 47% of a run, against code with no defect (#109).
@Suite
struct TestMissingRequireVisitorTests {

    private func makeVisitor() -> TestMissingRequireVisitor {
        TestMissingRequireVisitor(patternCategory: .codeQuality)
    }

    private func run(_ visitor: TestMissingRequireVisitor, source: String) {
        visitor.walk(Parser.parse(source: source))
        visitor.finalizeAnalysis()
    }

    // MARK: - Positive cases: the test can trap

    /// A force unwrap takes the whole test **process** down, and every other test with it.
    /// `try #require(…)` fails only this one, with a diagnostic.
    @Test
    func detectsForceUnwrap() throws {
        let visitor = makeVisitor()
        run(visitor, source: """
        @Test
        func testSnapshot() throws {
            let snapshot = fetchSnapshots().first!
            #expect(snapshot.id == 1)
        }
        """)
        let issue = try #require(visitor.detectedIssues.first)
        #expect(visitor.detectedIssues.count == 1)
        #expect(issue.ruleName == .testMissingRequire)
        #expect(issue.severity == .info)
        #expect(issue.message.contains("testSnapshot"))
        #expect(issue.message.contains("force unwrap"), "the message must name what it found")
    }

    @Test
    func detectsTryBang() throws {
        let visitor = makeVisitor()
        run(visitor, source: """
        @Test
        func testDecode() {
            let value = try! decode()
            #expect(value == 1)
        }
        """)
        let issue = try #require(visitor.detectedIssues.first)
        #expect(issue.message.contains("try!"))
    }

    /// **`as!` reaches an unfolded tree as `UnresolvedAsExprSyntax`, not `AsExprSyntax`** —
    /// operator folding produces the latter and the linter parses without it. Visiting only
    /// `AsExprSyntax` found force unwraps and `try!` and silently missed every force cast.
    @Test
    func detectsAsBang() throws {
        let visitor = makeVisitor()
        run(visitor, source: """
        @Test
        func testCast() {
            let typed = anything() as! Int
            #expect(typed == 1)
        }
        """)
        let issue = try #require(visitor.detectedIssues.first)
        #expect(issue.message.contains("as!"))
    }

    // MARK: - Negative cases: `#expect` alone is the right shape

    /// The 1,341-finding case. `#expect` records and continues; `#require` throws and halts. A
    /// test whose assertions are independent observations *should* use `#expect` throughout, and
    /// adding `#require` to satisfy a rule would make it worse — a first failure would hide the
    /// rest.
    @Test
    func ignoresExpectOnlyTest() {
        let visitor = makeVisitor()
        run(visitor, source: """
        @Test
        func hasVersion() {
            #expect(CLI.configuration.version.isEmpty == false)
        }
        """)
        #expect(visitor.detectedIssues.isEmpty)
    }

    @Test
    func ignoresTestWithNoAssertionsAtAll() {
        // A test asserting nothing is a defect, but it is `Test Missing Assertion`'s to report.
        let visitor = makeVisitor()
        run(visitor, source: """
        @Test
        func testSetup() {
            let value = createItem()
            print(value)
        }
        """)
        #expect(visitor.detectedIssues.isEmpty)
    }

    @Test
    func ignoresSafeOptionalHandling() {
        let visitor = makeVisitor()
        run(visitor, source: """
        @Test
        func testOptional() throws {
            let value = try? decode()
            #expect(value?.isEmpty == false)
            let cast = anything() as? Int
            #expect(cast == nil)
        }
        """)
        #expect(visitor.detectedIssues.isEmpty)
    }

    /// **Embedded fixture source is text, not code.** A linter's own suite is full of Swift written
    /// inside string literals, and a regex estimate of this rule's reach counted them: 26 apparent
    /// hits in this repository, of which the syntax-based rule reports zero. `print(name!)` inside
    /// a multiline literal is a string.
    @Test
    func ignoresForceUnwrapInsideAStringLiteral() {
        let visitor = makeVisitor()
        run(visitor, source: #"""
        @Test
        func testWritesFixture() throws {
            try """
            func work() {
                let name: String? = nil
                print(name!)
            }
            """.write(to: url, atomically: true, encoding: .utf8)
            #expect(FileManager.default.fileExists(atPath: url.path))
        }
        """#)
        #expect(visitor.detectedIssues.isEmpty)
    }

    /// Already using `#require` is the whole point of the rule, trap or no trap.
    @Test
    func ignoresTestThatAlreadyRequires() {
        let visitor = makeVisitor()
        run(visitor, source: """
        @Test
        func testUnwrap() throws {
            let snapshot = try #require(fetchSnapshots().first)
            #expect(snapshot.id == 1)
        }
        """)
        #expect(visitor.detectedIssues.isEmpty)
    }

    @Test
    func ignoresNonTestFunctions() {
        let visitor = makeVisitor()
        run(visitor, source: """
        func helperFunction() {
            let value = maybe()!
            print(value)
        }
        """)
        #expect(visitor.detectedIssues.isEmpty)
    }

    /// Index subscripting is deliberately out of scope: 448 of 13,200 `@Test` bodies without
    /// `#require` subscript by a literal index — more than all three trapping shapes combined —
    /// and in a test the collection is usually one the test just built, where it cannot trap.
    /// Syntax cannot tell that apart from an unchecked access on a fetched one.
    @Test
    func ignoresIndexSubscript() {
        let visitor = makeVisitor()
        run(visitor, source: """
        @Test
        func testFirst() {
            let items = [1, 2, 3]
            #expect(items[0] == 1)
        }
        """)
        #expect(visitor.detectedIssues.isEmpty)
    }

    // MARK: - Mixed

    @Test
    func flagsOnlyTheTrappingTest() throws {
        let visitor = makeVisitor()
        run(visitor, source: """
        @Test
        func testSafe() {
            #expect(compute() == 42)
        }

        @Test
        func testTrapping() {
            #expect(fetch().first!.id == 1)
        }
        """)
        #expect(visitor.detectedIssues.count == 1)
        let issue = try #require(visitor.detectedIssues.first)
        #expect(issue.message.contains("testTrapping"))
    }
}
