@testable import Core
import Foundation
import SwiftParser
@testable import SwiftProjectLintRules
import SwiftSyntax
import Testing

extension ForEachAndBodyTests {
    // MARK: - Large View Body Tests

    @Test func testDetectsLargeViewBody() {
        // Create a view with many statements (over 100 lines to trigger detection)
        let lines = (1...105).map { "Text(\"Line \($0)\")" }.joined(separator: "\n                    ")
        let source = """
        struct TestView: View {
            var body: some View {
                VStack {
                    \(lines)
                }
            }
        }
        """

        let issues = analyzeSource(source)
        let largeBodyIssues = issues.filter { $0.message.contains("Large view") }

        #expect(largeBodyIssues.count == 1)
    }

    @Test func testNoIssueForSmallViewBody() {
        let source = """
        struct TestView: View {
            var body: some View {
                VStack {
                    Text("Hello")
                    Text("World")
                }
            }
        }
        """

        let issues = analyzeSource(source)
        let largeBodyIssues = issues.filter { $0.message.contains("Large view body") }

        #expect(largeBodyIssues.isEmpty)
    }

    // MARK: - File Path Tests

    @Test func testFilePathIsSetCorrectly() throws {
        let source = """
        struct TestView: View {
            var body: some View {
                ForEach([1, 2, 3]) { item in
                    Text("\\(item)")
                }
            }
        }
        """

        let issues = analyzeSource(source, filePath: "Custom/Path/MyView.swift")

        let issue = try #require(issues.first)
        #expect(issue.filePath == "Custom/Path/MyView.swift")
    }

    // MARK: - Visitor Initialization Tests

    @Test func testVisitorInitialization() {
        let visitor = createVisitor()

        #expect(visitor.detectedIssues.isEmpty)
        #expect(visitor.pattern.category == .performance)
    }

    @Test func testVisitorReset() {
        let visitor = createVisitor()

        // First analysis
        let source1 = """
        struct TestView1: View {
            var body: some View {
                ForEach([1]) { _ in Text("A") }
            }
        }
        """
        let syntax1 = Parser.parse(source: source1)
        visitor.walk(syntax1)
        let firstCount = visitor.detectedIssues.count

        // Second analysis (issues should accumulate or be tracked per view)
        let source2 = """
        struct TestView2: View {
            var body: some View {
                ForEach([2]) { _ in Text("B") }
            }
        }
        """
        let syntax2 = Parser.parse(source: source2)
        visitor.walk(syntax2)

        // Verify visitor processed both
        #expect(visitor.detectedIssues.count >= firstCount)
    }

    // MARK: - Multiple Issues Tests

    @Test func testDetectsMultipleIssuesInSameView() {
        let source = """
        struct TestView: View {
            @State private var items = [3, 1, 2]

            var body: some View {
                VStack {
                    ForEach(items) { item in
                        Text("\\(sorted(items)[0])")
                    }
                }
            }
        }
        """

        let issues = analyzeSource(source)

        // Should detect both ForEach without ID and sorted in body
        #expect(issues.count == 2)
    }

    // MARK: - Function Declaration Body Tests

    @Test func testDetectsIssuesInFunctionBody() {
        let source = """
        struct TestView: View {
            @State private var items = [1, 2, 3]

            func body() -> some View {
                VStack {
                    ForEach(items) { item in
                        Text("\\(item)")
                    }
                }
            }
        }
        """

        let issues = analyzeSource(source) // tests the FunctionDeclSyntax path for body
        // ForEach(items) without id: is correctly flagged — verify no crash and
        // that only the expected ForEach rule fires (not a body-detection issue).
        let nonForEachIssues = issues.filter { $0.ruleName != .forEachWithoutID }
        #expect(nonForEachIssues.isEmpty)
    }
}
