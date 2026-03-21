import Testing
@testable import SwiftProjectLintCore
import SwiftSyntax
import SwiftParser

@Suite
struct LowercasedContainsVisitorTests {

    private func makeVisitor() -> LowercasedContainsVisitor {
        let pattern = LowercasedContainsPatternRegistrar().pattern
        return LowercasedContainsVisitor(pattern: pattern)
    }

    private func runVisitor(_ visitor: LowercasedContainsVisitor, source: String) {
        let sourceFile = Parser.parse(source: source)
        visitor.walk(sourceFile)
    }

    // MARK: - Positive Cases

    @Test
    func testDetectsLowercasedContains() throws {
        let source = """
        let results = items.filter { $0.name.lowercased().contains(query) }
        """

        let visitor = makeVisitor()
        runVisitor(visitor, source: source)

        #expect(visitor.detectedIssues.count == 1)

        let issue = try #require(visitor.detectedIssues.first)
        #expect(issue.ruleName == .lowercasedContains)
        #expect(issue.severity == .warning)
        #expect(issue.message.contains("lowercased"))
    }

    @Test
    func testDetectsUppercasedContains() throws {
        let source = """
        let matches = names.filter { $0.uppercased().contains(search) }
        """

        let visitor = makeVisitor()
        runVisitor(visitor, source: source)

        #expect(visitor.detectedIssues.count == 1)

        let issue = try #require(visitor.detectedIssues.first)
        #expect(issue.ruleName == .lowercasedContains)
        #expect(issue.message.contains("uppercased"))
    }

    @Test
    func testDetectsInFilterClosure() throws {
        let source = """
        struct SearchView: View {
            @State private var query = ""
            let items: [String]

            var filtered: [String] {
                items.filter { item in
                    item.lowercased().contains(query.lowercased())
                }
            }
        }
        """

        let visitor = makeVisitor()
        runVisitor(visitor, source: source)

        // Two instances: item.lowercased().contains(...) and query.lowercased() is not flagged
        // but the outer .contains() call on item.lowercased() is flagged once
        #expect(visitor.detectedIssues.count == 1)
    }

    // MARK: - Negative Cases

    @Test
    func testNoIssueForPlainContains() {
        let source = """
        let hasItem = items.contains("hello")
        """

        let visitor = makeVisitor()
        runVisitor(visitor, source: source)

        #expect(visitor.detectedIssues.isEmpty)
    }

    @Test
    func testNoIssueForLocalizedStandardContains() {
        let source = """
        let results = items.filter { $0.localizedStandardContains(query) }
        """

        let visitor = makeVisitor()
        runVisitor(visitor, source: source)

        #expect(visitor.detectedIssues.isEmpty)
    }

    @Test
    func testNoIssueForLowercasedWithoutContains() {
        let source = """
        let lower = name.lowercased()
        print(lower)
        """

        let visitor = makeVisitor()
        runVisitor(visitor, source: source)

        #expect(visitor.detectedIssues.isEmpty)
    }

    @Test
    func testNoIssueForContainsOnCollection() {
        let source = """
        let numbers = [1, 2, 3]
        let hasTwo = numbers.contains(2)
        """

        let visitor = makeVisitor()
        runVisitor(visitor, source: source)

        #expect(visitor.detectedIssues.isEmpty)
    }

    @Test
    func testNoIssueForContainsWhereOnCollection() {
        let source = """
        let hasMatch = items.contains(where: { $0.isActive })
        """

        let visitor = makeVisitor()
        runVisitor(visitor, source: source)

        #expect(visitor.detectedIssues.isEmpty)
    }
}
