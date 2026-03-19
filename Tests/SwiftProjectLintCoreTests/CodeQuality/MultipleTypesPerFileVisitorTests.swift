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
    func testDetectsTwoStructs() throws {
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
    func testDetectsThreeTypes() {
        let source = """
        struct Alpha {}
        class Beta {}
        enum Gamma {}
        """

        let visitor = makeVisitor()
        runVisitor(visitor, source: source)

        #expect(visitor.detectedIssues.count == 2)
    }

    @Test
    func testDetectsMixedTypeKinds() throws {
        let source = """
        enum Theme {
            case light, dark
        }

        class ThemeManager {
            var current: Theme = .light
        }
        """

        let visitor = makeVisitor()
        runVisitor(visitor, source: source)

        #expect(visitor.detectedIssues.count == 1)

        let issue = try #require(visitor.detectedIssues.first)
        #expect(issue.message.contains("ThemeManager"))
    }

    @Test
    func testDetectsActorWithStruct() throws {
        let source = """
        struct Config {
            let value: Int
        }

        actor NetworkActor {
            func fetch() {}
        }
        """

        let visitor = makeVisitor()
        runVisitor(visitor, source: source)

        #expect(visitor.detectedIssues.count == 1)

        let issue = try #require(visitor.detectedIssues.first)
        #expect(issue.message.contains("NetworkActor"))
    }

    // MARK: - Negative Cases

    @Test
    func testNoIssueForSingleStruct() {
        let source = """
        struct User {
            let name: String
            let email: String
        }
        """

        let visitor = makeVisitor()
        runVisitor(visitor, source: source)

        #expect(visitor.detectedIssues.isEmpty)
    }

    @Test
    func testNoIssueForTypeWithExtension() {
        let source = """
        struct User {
            let name: String
        }

        extension User: Codable {}
        """

        let visitor = makeVisitor()
        runVisitor(visitor, source: source)

        #expect(visitor.detectedIssues.isEmpty)
    }

    @Test
    func testNoIssueForNestedTypes() {
        let source = """
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
        """

        let visitor = makeVisitor()
        runVisitor(visitor, source: source)

        #expect(visitor.detectedIssues.isEmpty)
    }

    @Test
    func testNoIssueForEmptyFile() {
        let source = """
        import Foundation
        """

        let visitor = makeVisitor()
        runVisitor(visitor, source: source)

        #expect(visitor.detectedIssues.isEmpty)
    }

    @Test
    func testNoIssueForSingleEnum() {
        let source = """
        enum Direction {
            case north, south, east, west
        }
        """

        let visitor = makeVisitor()
        runVisitor(visitor, source: source)

        #expect(visitor.detectedIssues.isEmpty)
    }
}
