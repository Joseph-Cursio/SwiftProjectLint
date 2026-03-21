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

    // MARK: - Detailed Positive Case

    @Test
    func detectsLowercasedContains() throws {
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

    // MARK: - Parameterized Positive Cases

    @Test("Detects case-converted contains variant", arguments: [
        (
            """
            let matches = names.filter { $0.uppercased().contains(search) }
            """,
            "uppercased"
        )
    ] as [(String, String)])
    func detectsVariant(source: String, expected: String) throws {
        let visitor = makeVisitor()
        runVisitor(visitor, source: source)
        #expect(visitor.detectedIssues.count == 1)
        let issue = try #require(visitor.detectedIssues.first)
        #expect(issue.message.contains(expected))
    }

    // Unique: multi-instance in filter closure, specific count validation
    @Test
    func detectsInFilterClosure() throws {
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

        #expect(visitor.detectedIssues.count == 1)
    }

    // MARK: - Negative Cases

    @Test("No issue for valid contains usage", arguments: [
        // Plain contains
        """
        let hasItem = items.contains("hello")
        """,
        // localizedStandardContains
        """
        let results = items.filter { $0.localizedStandardContains(query) }
        """,
        // lowercased without contains
        """
        let lower = name.lowercased()
        print(lower)
        """,
        // contains on collection
        """
        let numbers = [1, 2, 3]
        let hasTwo = numbers.contains(2)
        """,
        // contains(where:) on collection
        """
        let hasMatch = items.contains(where: { $0.isActive })
        """
    ])
    func noIssue(source: String) {
        let visitor = makeVisitor()
        runVisitor(visitor, source: source)
        #expect(visitor.detectedIssues.isEmpty)
    }
}
