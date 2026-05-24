@testable import Core
import Foundation
import SwiftParser
@testable import SwiftProjectLintRules
import SwiftSyntax
import Testing

@Suite
struct OnTapGestureInsteadOfButtonTests {

    // MARK: - Helper

    private func analyzeSource(
        _ source: String,
        filePath: String = "TestFile.swift"
    ) -> [LintIssue] {
        let visitor = OnTapGestureInsteadOfButtonVisitor(patternCategory: .accessibility)
        let syntax = Parser.parse(source: source)
        let converter = SourceLocationConverter(fileName: filePath, tree: syntax)
        visitor.setSourceLocationConverter(converter)
        visitor.setFilePath(filePath)
        visitor.walk(syntax)
        return visitor.detectedIssues
    }

    private func filteredIssues(_ source: String) -> [LintIssue] {
        analyzeSource(source).filter { $0.ruleName == .onTapGestureInsteadOfButton }
    }

    // MARK: - Positive: flags simple onTapGesture

    @Test func testFlagsSimpleOnTapGesture() throws {
        let source = """
        struct MyView: View {
            var body: some View {
                Text("Tap me")
                    .onTapGesture { doSomething() }
            }
        }
        """
        let issues = filteredIssues(source)
        let issue = try #require(issues.first)
        #expect(issues.count == 1)
        #expect(issue.severity == .warning)
        #expect(issue.message.contains("Button"))
    }

    @Test func testFlagsOnTapGestureOnImage() {
        let source = """
        struct MyView: View {
            var body: some View {
                Image(systemName: "trash")
                    .onTapGesture { deleteItem() }
            }
        }
        """
        let issues = filteredIssues(source)
        #expect(issues.count == 1)
    }

    @Test func testFlagsMultipleOnTapGestures() {
        let source = """
        struct MyView: View {
            var body: some View {
                VStack {
                    Text("One").onTapGesture { one() }
                    Text("Two").onTapGesture { two() }
                }
            }
        }
        """
        let issues = filteredIssues(source)
        #expect(issues.count == 2)
    }

    @Test func testFlagsCountOneAsSimpleTap() {
        let source = """
        struct MyView: View {
            var body: some View {
                Text("Tap").onTapGesture(count: 1) { tapped() }
            }
        }
        """
        let issues = filteredIssues(source)
        #expect(issues.count == 1)
    }

    // MARK: - Negative: should NOT flag

    @Test func testAllowsDoubleTap() {
        let source = """
        struct MyView: View {
            var body: some View {
                Text("Double tap")
                    .onTapGesture(count: 2) { doubleTapped() }
            }
        }
        """
        let issues = filteredIssues(source)
        #expect(issues.isEmpty)
    }

    @Test func testAllowsTripleTap() {
        let source = """
        struct MyView: View {
            var body: some View {
                Text("Triple tap")
                    .onTapGesture(count: 3) { tripleTapped() }
            }
        }
        """
        let issues = filteredIssues(source)
        #expect(issues.isEmpty)
    }

    @Test func testAllowsLocationAwareClosure() {
        let source = """
        struct MyView: View {
            var body: some View {
                Text("Tap here")
                    .onTapGesture { location in
                        handleTap(at: location)
                    }
            }
        }
        """
        let issues = filteredIssues(source)
        #expect(issues.isEmpty)
    }

    @Test func testAllowsCoordinateSpaceArgument() {
        let source = """
        struct MyView: View {
            var body: some View {
                Text("Tap")
                    .onTapGesture(coordinateSpace: .local) { location in
                        handle(location)
                    }
            }
        }
        """
        let issues = filteredIssues(source)
        #expect(issues.isEmpty)
    }

    @Test func testNoIssueForButton() {
        let source = """
        struct MyView: View {
            var body: some View {
                Button("Tap me") { doSomething() }
            }
        }
        """
        let issues = filteredIssues(source)
        #expect(issues.isEmpty)
    }

    // MARK: - Accessibility check for allowed gestures

    private func accessibilityIssues(_ source: String) -> [LintIssue] {
        analyzeSource(source).filter { $0.ruleName == .onTapGestureMissingAccessibility }
    }

    @Test func testDoubleTapWithoutAccessibilityFlagsInfo() {
        let source = """
        struct MyView: View {
            var body: some View {
                Canvas { ctx, size in }
                    .onTapGesture(count: 2) { resetZoom() }
            }
        }
        """
        let issues = accessibilityIssues(source)
        #expect(issues.count == 1)
        #expect(issues.first?.severity == .info)
        #expect(issues.first?.message.contains("VoiceOver") == true)
    }

    @Test func testDoubleTapWithAccessibilityTraitsNoIssue() {
        let source = """
        struct MyView: View {
            var body: some View {
                Canvas { ctx, size in }
                    .onTapGesture(count: 2) { resetZoom() }
                    .accessibilityAddTraits(.isButton)
            }
        }
        """
        let issues = accessibilityIssues(source)
        #expect(issues.isEmpty)
    }

    @Test func testDoubleTapWithAccessibilityLabelNoIssue() {
        let source = """
        struct MyView: View {
            var body: some View {
                Canvas { ctx, size in }
                    .onTapGesture(count: 2) { resetZoom() }
                    .accessibilityLabel("Reset zoom")
            }
        }
        """
        let issues = accessibilityIssues(source)
        #expect(issues.isEmpty)
    }

    @Test func testTripleTapWithoutAccessibilityFlags() {
        let source = """
        struct MyView: View {
            var body: some View {
                Text("Tap me")
                    .onTapGesture(count: 3) { tripleTapped() }
            }
        }
        """
        let issues = accessibilityIssues(source)
        #expect(issues.count == 1)
    }

    @Test func testLocationAwareWithoutAccessibilityFlags() {
        let source = """
        struct MyView: View {
            var body: some View {
                Text("Tap here")
                    .onTapGesture { location in
                        handleTap(at: location)
                    }
            }
        }
        """
        let issues = accessibilityIssues(source)
        #expect(issues.count == 1)
    }

    @Test func testSimpleTapDoesNotFireAccessibilityRule() {
        let source = """
        struct MyView: View {
            var body: some View {
                Text("Tap").onTapGesture { tapped() }
            }
        }
        """
        let issues = accessibilityIssues(source)
        #expect(issues.isEmpty)
    }

    // MARK: - Other gestures

    @Test func testNoIssueForOtherGestures() {
        let source = """
        struct MyView: View {
            var body: some View {
                Text("Drag me")
                    .onLongPressGesture { longPressed() }
            }
        }
        """
        let issues = filteredIssues(source)
        #expect(issues.isEmpty)
    }
}
