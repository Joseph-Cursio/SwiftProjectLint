import Testing
@testable import Core
@testable import SwiftProjectLintRules
import SwiftParser

@Suite
struct RetroactiveConformanceVisitorTests {

    private func makeVisitor() -> RetroactiveConformanceVisitor {
        RetroactiveConformanceVisitor(pattern: RetroactiveConformance().pattern)
    }

    private func run(_ visitor: RetroactiveConformanceVisitor, source: String) {
        visitor.walk(Parser.parse(source: source))
    }

    // MARK: - Detection

    @Test
    func detectsStdlibTypeToStdlibProtocol() throws {
        // Both Array and Identifiable are framework types
        let source = """
        extension Array: @retroactive Identifiable {
            public var id: Int { count }
        }
        """
        let visitor = makeVisitor()
        run(visitor, source: source)

        #expect(visitor.detectedIssues.count == 1)
        let issue = try #require(visitor.detectedIssues.first)
        #expect(issue.ruleName == .retroactiveConformance)
        #expect(issue.severity == .warning)
        #expect(issue.message.contains("Array"))
        #expect(issue.message.contains("Identifiable"))
    }

    @Test
    func detectsURLToCustomStringConvertible() {
        let source = """
        extension URL: @retroactive CustomStringConvertible {
            public var description: String { absoluteString }
        }
        """
        let visitor = makeVisitor()
        run(visitor, source: source)
        #expect(visitor.detectedIssues.count == 1)
    }

    @Test
    func detectsDateToHashable() {
        let source = """
        extension Date: @retroactive Hashable {
            public func hash(into hasher: inout Hasher) {
                hasher.combine(timeIntervalSinceReferenceDate)
            }
        }
        """
        let visitor = makeVisitor()
        run(visitor, source: source)
        #expect(visitor.detectedIssues.count == 1)
    }

    // MARK: - No issues

    @Test
    func noIssueForOwnTypeToFrameworkProtocol() {
        // Own type (not in highRiskFrameworkTypes) conforming to a framework protocol
        let source = """
        extension MyCustomModel: @retroactive Identifiable {
            public var id: UUID { uuid }
        }
        """
        let visitor = makeVisitor()
        run(visitor, source: source)
        #expect(visitor.detectedIssues.isEmpty)
    }

    @Test
    func noIssueForFrameworkTypeToOwnProtocol() {
        // Framework type conforming to a user-defined protocol
        let source = """
        extension String: @retroactive Displayable {
            public func display() -> String { self }
        }
        """
        let visitor = makeVisitor()
        run(visitor, source: source)
        // "Displayable" is not in highRiskFrameworkTypes so should not be flagged
        #expect(visitor.detectedIssues.isEmpty)
    }

    @Test
    func noIssueForExtensionWithoutRetroactive() {
        // Regular conformance without @retroactive
        let source = """
        extension Array: Identifiable {
            public var id: Int { count }
        }
        """
        let visitor = makeVisitor()
        run(visitor, source: source)
        #expect(visitor.detectedIssues.isEmpty)
    }

    @Test
    func noIssueForExtensionWithoutConformance() {
        // Extension adding methods, no conformance
        let source = """
        extension Array {
            func second() -> Element? { count > 1 ? self[1] : nil }
        }
        """
        let visitor = makeVisitor()
        run(visitor, source: source)
        #expect(visitor.detectedIssues.isEmpty)
    }
}
