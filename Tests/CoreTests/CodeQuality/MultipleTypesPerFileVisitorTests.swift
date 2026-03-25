import Testing
@testable import Core
import SwiftSyntax
import SwiftParser

struct MultipleTypesPerFileVisitorTests {

    private func makeVisitor(filePath: String = "test.swift") -> MultipleTypesPerFileVisitor {
        let pattern = MultipleTypesPerFile().pattern
        let visitor = MultipleTypesPerFileVisitor(pattern: pattern)
        visitor.setFilePath(filePath)
        return visitor
    }

    private func runVisitor(_ visitor: MultipleTypesPerFileVisitor, source: String) {
        let sourceFile = Parser.parse(source: source)
        visitor.walk(sourceFile)
    }

    // MARK: - Positive Cases (unrelated types → flagged)

    @Test
    func detectsTwoUnrelatedStructs() throws {
        let source = """
        struct Logger {
            let level: Int
        }

        struct NetworkClient {
            let url: String
        }
        """

        let visitor = makeVisitor()
        runVisitor(visitor, source: source)

        #expect(visitor.detectedIssues.count == 1)

        let issue = try #require(visitor.detectedIssues.first)
        #expect(issue.ruleName == .multipleTypesPerFile)
        #expect(issue.severity == .info)
        #expect(issue.message.contains("NetworkClient"))
    }

    @Test
    func detectsThreeUnrelatedTypes() {
        let source = """
        struct Alpha {}
        class Beta {}
        enum Gamma {}
        """

        let visitor = makeVisitor()
        runVisitor(visitor, source: source)

        #expect(visitor.detectedIssues.count == 2)
    }

    @Test("Detects unrelated mixed type kinds", arguments: [
        ("""
        enum Direction {
            case north, south
        }

        class NetworkManager {
            func fetch() {}
        }
        """, "NetworkManager"),
        ("""
        struct Logger {
            let level: Int
        }

        actor DatabaseActor {
            func save() {}
        }
        """, "DatabaseActor"),
    ])
    func detectsUnrelatedMixedTypes(source: String, expectedTypeName: String) throws {
        let visitor = makeVisitor()
        runVisitor(visitor, source: source)

        #expect(visitor.detectedIssues.count == 1)

        let issue = try #require(visitor.detectedIssues.first)
        #expect(issue.message.contains(expectedTypeName))
    }

    // MARK: - Negative Cases (single, nested, extensions)

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
        """,
    ])
    func noIssue(source: String) {
        let visitor = makeVisitor()
        runVisitor(visitor, source: source)

        #expect(visitor.detectedIssues.isEmpty)
    }

    // MARK: - Tightly Coupled Types (shared prefix → not flagged)

    @Test
    func skipsErrorEnumWithSharedPrefix() {
        let source = """
        class WorkspaceManager {
            func load() {}
        }

        enum WorkspaceError: Error {
            case notFound
        }
        """

        let visitor = makeVisitor(filePath: "WorkspaceManager.swift")
        runVisitor(visitor, source: source)

        #expect(visitor.detectedIssues.isEmpty)
    }

    @Test
    func skipsSupportingTypesWithSharedPrefix() {
        let source = """
        struct Rule {
            let identifier: String
        }

        enum RuleCategory {
            case lint, style
        }

        struct RuleParameter {
            let name: String
        }
        """

        let visitor = makeVisitor(filePath: "Rule.swift")
        runVisitor(visitor, source: source)

        #expect(visitor.detectedIssues.isEmpty)
    }

    @Test
    func skipsViewSubcomponentsWithSharedPrefix() {
        let source = """
        struct HealthScoreBadge: View {
            var body: some View { Text("A") }
        }

        struct HealthScoreRing: View {
            var body: some View { Text("Ring") }
        }

        struct HealthScoreIndicator: View {
            var body: some View { Text("Indicator") }
        }
        """

        let visitor = makeVisitor(filePath: "HealthScoreBadge.swift")
        runVisitor(visitor, source: source)

        #expect(visitor.detectedIssues.isEmpty)
    }

    @Test
    func skipsTypeMatchingFileNameStem() {
        let source = """
        struct ViolationInspectorOptions {
            let showResolved: Bool
        }

        enum ViolationSortOption {
            case date, severity
        }
        """

        let visitor = makeVisitor(filePath: "ViolationInspectorViewModel+Options.swift")
        runVisitor(visitor, source: source)

        #expect(visitor.detectedIssues.isEmpty)
    }

    @Test
    func flagsUnrelatedTypeEvenWithCoupledOnes() throws {
        let source = """
        class ConfigImportService {
            func importConfig() {}
        }

        enum ConfigImportError: Error {
            case invalid
        }

        struct UnrelatedLogger {
            let level: Int
        }
        """

        let visitor = makeVisitor(filePath: "ConfigImportService.swift")
        runVisitor(visitor, source: source)

        #expect(visitor.detectedIssues.count == 1)
        let issue = try #require(visitor.detectedIssues.first)
        #expect(issue.message.contains("UnrelatedLogger"))
    }
}
