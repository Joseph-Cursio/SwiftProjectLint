import Testing
import Foundation
import SwiftSyntax
import SwiftParser
@testable import SwiftProjectLintCore

/// Tests for PerformanceVisitor detection of expensive operations in view body
@Suite
struct ExpensiveOperationTests {

    // MARK: - Helper Methods

    private func createVisitor() -> PerformanceVisitor {
        return PerformanceVisitor(patternCategory: .performance)
    }

    private func analyzeSource(
        _ source: String,
        filePath: String = "TestView.swift"
    ) -> [LintIssue] {
        let visitor = createVisitor()
        let syntax = Parser.parse(source: source)
        let converter = SourceLocationConverter(fileName: filePath, tree: syntax)
        visitor.setSourceLocationConverter(converter)
        visitor.setFilePath(filePath)
        visitor.walk(syntax)
        return visitor.detectedIssues
    }

    // MARK: - Expensive Operations in View Body Tests
    // Note: The visitor detects direct function calls (e.g., sorted(items))
    // not method calls (items.sorted())

    @Test func testDetectsSortedInViewBody() throws {
        let source = """
        struct TestView: View {
            @State private var items = [3, 1, 2]

            var body: some View {
                VStack {
                    ForEach(sorted(items), id: \\.self) { item in
                        Text("\\(item)")
                    }
                }
            }
        }
        """

        let issues = analyzeSource(source)
        let sortedIssues = issues.filter { $0.message.contains("sorted") }

        #expect(sortedIssues.count >= 1)
        if let issue = sortedIssues.first {
            #expect(issue.severity == .warning)
            #expect(issue.message.contains("Expensive operation"))
        }
    }

    @Test func testDetectsFilterInViewBody() throws {
        let source = """
        struct TestView: View {
            @State private var items = [1, 2, 3, 4, 5]

            var body: some View {
                VStack {
                    ForEach(filter(items) { $0 > 2 }, id: \\.self) { item in
                        Text("\\(item)")
                    }
                }
            }
        }
        """

        let issues = analyzeSource(source)
        let filterIssues = issues.filter { $0.message.contains("filter") }

        #expect(filterIssues.count >= 1)
    }

    @Test func testDetectsMapInViewBody() throws {
        let source = """
        struct TestView: View {
            @State private var items = [1, 2, 3]

            var body: some View {
                VStack {
                    ForEach(map(items) { $0 * 2 }, id: \\.self) { item in
                        Text("\\(item)")
                    }
                }
            }
        }
        """

        let issues = analyzeSource(source)
        let mapIssues = issues.filter { $0.message.contains("map") }

        #expect(mapIssues.count >= 1)
    }

    @Test func testDetectsReduceInViewBody() throws {
        let source = """
        struct TestView: View {
            @State private var numbers = [1, 2, 3]

            var body: some View {
                Text("Total: \\(reduce(numbers, 0, +))")
            }
        }
        """

        let issues = analyzeSource(source)
        let reduceIssues = issues.filter { $0.message.contains("reduce") }

        #expect(reduceIssues.count >= 1)
    }

    @Test func testDetectsFlatMapInViewBody() throws {
        let source = """
        struct TestView: View {
            @State private var items = [[1, 2], [3, 4]]

            var body: some View {
                VStack {
                    ForEach(flatMap(items) { $0 }, id: \\.self) { item in
                        Text("\\(item)")
                    }
                }
            }
        }
        """

        let issues = analyzeSource(source)
        let flatMapIssues = issues.filter { $0.message.contains("flatMap") }

        #expect(flatMapIssues.count >= 1)
    }

    @Test func testDetectsCompactMapInViewBody() throws {
        let source = """
        struct TestView: View {
            @State private var items: [String?] = ["a", nil, "b"]

            var body: some View {
                VStack {
                    ForEach(compactMap(items) { $0 }, id: \\.self) { item in
                        Text(item)
                    }
                }
            }
        }
        """

        let issues = analyzeSource(source)
        let compactMapIssues = issues.filter { $0.message.contains("compactMap") }

        #expect(compactMapIssues.count >= 1)
    }

    @Test func testNoExpensiveOperationOutsideViewBody() throws {
        // sorted() outside of View body should not be flagged
        let source = """
        struct DataModel {
            var items = [1, 2, 3]

            func getSorted() -> [Int] {
                return sorted(items)
            }
        }
        """

        let issues = analyzeSource(source)
        let sortedIssues = issues.filter { $0.message.contains("sorted") }

        #expect(sortedIssues.isEmpty)
    }

    @Test func testIgnoresNonSwiftUIStruct() throws {
        let source = """
        struct DataModel {
            var items = [1, 2, 3]

            func getData() -> [Int] {
                return items
            }
        }
        """

        let issues = analyzeSource(source)

        // Non-SwiftUI struct should not trigger any performance issues
        #expect(issues.isEmpty)
    }
}
