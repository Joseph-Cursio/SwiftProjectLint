import Testing
@testable import SwiftProjectLintCore
import SwiftSyntax
import SwiftParser

@Suite
struct MultipleTypesPerFileVisitorTests {

    private func makeVisitor() -> MultipleTypesPerFileVisitor {
        let pattern = MultipleTypesPerFilePatternRegistrar().pattern
        return MultipleTypesPerFileVisitor(pattern: pattern)
    }

    private func runVisitor(_ visitor: MultipleTypesPerFileVisitor, source: String) {
        let sourceFile = Parser.parse(source: source)
        visitor.walk(sourceFile)
    }

    // MARK: - Positive Cases

    @Test
    func detectsTwoStructs() throws {
        let source = """
        struct User {
            let name: String
        }

        struct UserViewModel {
            let user: User
        }
        """

        let visitor = makeVisitor()
        runVisitor(visitor, source: source)

        #expect(visitor.detectedIssues.count == 1)

        let issue = try #require(visitor.detectedIssues.first)
        #expect(issue.ruleName == .multipleTypesPerFile)
        #expect(issue.severity == .info)
        #expect(issue.message.contains("UserViewModel"))
    }

    @Test
    func detectsThreeTypes() {
        let source = """
        struct Alpha {}
        class Beta {}
        enum Gamma {}
        """

        let visitor = makeVisitor()
        runVisitor(visitor, source: source)

        #expect(visitor.detectedIssues.count == 2)
    }

    @Test("Detects mixed type kinds", arguments: [
        ("""
        enum Theme {
            case light, dark
        }

        class ThemeManager {
            var current: Theme = .light
        }
        """, "ThemeManager"),
        ("""
        struct Config {
            let value: Int
        }

        actor NetworkActor {
            func fetch() {}
        }
        """, "NetworkActor")
    ])
    func detectsMixedTypes(source: String, expectedTypeName: String) throws {
        let visitor = makeVisitor()
        runVisitor(visitor, source: source)

        #expect(visitor.detectedIssues.count == 1)

        let issue = try #require(visitor.detectedIssues.first)
        #expect(issue.message.contains(expectedTypeName))
    }

    // MARK: - Negative Cases

    @Test("No issue for single or nested types", arguments: [
        // Single struct
        """
        struct User {
            let name: String
            let email: String
        }
        """,
        // Type with extension
        """
        struct User {
            let name: String
        }

        extension User: Codable {}
        """,
        // Nested types
        """
        struct TableSection {
            enum Style {
                case plain
                case grouped
            }

            struct Row {
                let title: String
            }

            let style: Style
            let rows: [Row]
        }
        """,
        // Empty file
        """
        import Foundation
        """,
        // Single enum
        """
        enum Direction {
            case north, south, east, west
        }
        """
    ])
    func noIssue(source: String) {
        let visitor = makeVisitor()
        runVisitor(visitor, source: source)

        #expect(visitor.detectedIssues.isEmpty)
    }
}
