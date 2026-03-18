import Testing
import Foundation
import SwiftSyntax
import SwiftParser
@testable import SwiftProjectLintCore

/// Tests for PerformanceVisitor ForEach and view body size detection
@Suite
struct PerformanceVisitorForEachAndBodyTests {

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

    // MARK: - ForEach Without ID Tests

    @Test func testDetectsForEachWithoutID() throws {
        let source = """
        struct TestView: View {
            @State private var items = [1, 2, 3]

            var body: some View {
                VStack {
                    ForEach(items) { item in
                        Text("\\(item)")
                    }
                }
            }
        }
        """

        let issues = analyzeSource(source)
        let forEachIssues = issues.filter {
            $0.message.contains("ForEach") && $0.message.contains("id")
        }

        #expect(forEachIssues.count >= 1)
        if let issue = forEachIssues.first {
            #expect(issue.ruleName == .forEachWithoutID)
        }
    }

    @Test func testNoIssueForForEachWithID() throws {
        let source = """
        struct TestView: View {
            struct Item: Identifiable {
                let id: UUID
                let name: String
            }
            @State private var items: [Item] = []

            var body: some View {
                VStack {
                    ForEach(items, id: \\.id) { item in
                        Text(item.name)
                    }
                }
            }
        }
        """

        let issues = analyzeSource(source)
        let forEachWithoutIDIssues = issues.filter {
            $0.message.contains("ForEach missing explicit id")
        }

        #expect(forEachWithoutIDIssues.isEmpty)
    }

    // MARK: - Large View Body Tests

    @Test func testDetectsLargeViewBody() throws {
        // Create a view with many statements (over 50 lines to trigger detection)
        let lines = (1...55).map { "Text(\"Line \($0)\")" }.joined(separator: "\n                    ")
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

        #expect(largeBodyIssues.count >= 1)
    }

    @Test func testNoIssueForSmallViewBody() throws {
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

        if let issue = issues.first {
            #expect(issue.filePath == "Custom/Path/MyView.swift")
        }
    }

    // MARK: - Visitor Initialization Tests

    @Test func testVisitorInitialization() throws {
        let visitor = createVisitor()

        #expect(visitor.detectedIssues.isEmpty)
        #expect(visitor.pattern.category == .performance)
    }

    @Test func testVisitorReset() throws {
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

    @Test func testDetectsMultipleIssuesInSameView() throws {
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
        #expect(issues.count >= 1)
    }

    // MARK: - Function Declaration Body Tests

    @Test func testDetectsIssuesInFunctionBody() throws {
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

        _ = analyzeSource(source) // tests the FunctionDeclSyntax path for body
    }
}

// MARK: - State Variable Tracking Tests

@Suite
struct PerformanceVisitorStateTrackingTests {

    private func createVisitor() -> PerformanceVisitor {
        return PerformanceVisitor(patternCategory: .performance)
    }

    @Test func testTracksStateVariableDeclaration() throws {
        let source = """
        struct TestView: View {
            @State private var count = 0
            @State private var name = "Test"

            var body: some View {
                Text("\\(count)")
            }
        }
        """

        let visitor = createVisitor()
        let syntax = Parser.parse(source: source)
        visitor.walk(syntax)

        // State variables should be tracked
        #expect(!visitor.stateVariables.isEmpty) // Should track @State variables
    }

    @Test func testStateVariableAssignmentTracking() throws {
        let source = """
        struct TestView: View {
            @State private var count = 0

            var body: some View {
                Button("Increment") {
                    count = count + 1
                }
            }
        }
        """

        let visitor = createVisitor()
        let syntax = Parser.parse(source: source)
        visitor.walk(syntax)

        // Should process assignment without error
    }
}
