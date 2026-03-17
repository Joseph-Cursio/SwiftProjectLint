import Testing
import Foundation
import SwiftSyntax
import SwiftParser
@testable import SwiftProjectLintCore

@Suite("ColorAccessibilityChecker Coverage Tests")
@MainActor
struct ColorAccessibilityCheckerCoverageTests {

    // MARK: - Test Helper Methods

    private func createVisitor() -> AccessibilityVisitor {
        TestRegistryManager.initializeSharedRegistry()
        return AccessibilityVisitor(patternCategory: .accessibility)
    }

    // MARK: - Direct Color Usage (Color.xxx pattern)

    @Test("detects direct Color.red usage as accessibility concern")
    func detectsDirectColorUsage() throws {
        let visitor = createVisitor()

        let sourceCode = """
        struct StatusView: View {
            var body: some View {
                Circle()
                    .fill(Color.red)
            }
        }
        """

        let sourceFile = Parser.parse(source: sourceCode)
        visitor.walk(sourceFile)

        let colorIssues = visitor.detectedIssues.filter {
            $0.message.contains("color-based information")
        }
        #expect(colorIssues.count >= 1)
        let issue = try #require(colorIssues.first)
        #expect(issue.severity == .info)
        #expect(issue.suggestion?.contains("color is not the only way") == true)
    }

    @Test("detects Color.blue direct usage")
    func detectsColorBlueUsage() throws {
        let visitor = createVisitor()

        let sourceCode = """
        struct BadgeView: View {
            var body: some View {
                Rectangle()
                    .fill(Color.blue)
            }
        }
        """

        let sourceFile = Parser.parse(source: sourceCode)
        visitor.walk(sourceFile)

        let colorIssues = visitor.detectedIssues.filter {
            $0.message.contains("color-based information")
        }
        #expect(colorIssues.count >= 1)
    }

    @Test("detects Color.green direct usage")
    func detectsColorGreenUsage() {
        let visitor = createVisitor()

        let sourceCode = """
        struct IndicatorView: View {
            var body: some View {
                Circle()
                    .fill(Color.green)
            }
        }
        """

        let sourceFile = Parser.parse(source: sourceCode)
        visitor.walk(sourceFile)

        let colorIssues = visitor.detectedIssues.filter {
            $0.message.contains("color-based information")
        }
        #expect(colorIssues.count >= 1)
    }

    // MARK: - foregroundColor with Accessibility Modifiers (early return paths)

    @Test("foregroundColor with accessibilityLabel produces no issue")
    func foregroundColorWithAccessibilityLabel() {
        let visitor = createVisitor()

        let sourceCode = """
        struct ContentView: View {
            var body: some View {
                Text("Error")
                    .foregroundColor(.red)
                    .accessibilityLabel("Error status indicator")
            }
        }
        """

        let sourceFile = Parser.parse(source: sourceCode)
        visitor.walk(sourceFile)

        let colorIssues = visitor.detectedIssues.filter {
            $0.message.contains("color-based information")
        }
        #expect(colorIssues.isEmpty)
    }

    @Test("foregroundColor with accessibilityHint produces no issue")
    func foregroundColorWithAccessibilityHint() {
        let visitor = createVisitor()

        let sourceCode = """
        struct ContentView: View {
            var body: some View {
                Text("Warning")
                    .foregroundColor(.yellow)
                    .accessibilityHint("Indicates a warning state")
            }
        }
        """

        let sourceFile = Parser.parse(source: sourceCode)
        visitor.walk(sourceFile)

        let colorIssues = visitor.detectedIssues.filter {
            $0.message.contains("color-based information")
        }
        #expect(colorIssues.isEmpty)
    }

    @Test("foregroundColor with accessibilityValue produces no issue")
    func foregroundColorWithAccessibilityValue() {
        let visitor = createVisitor()

        let sourceCode = """
        struct ContentView: View {
            var body: some View {
                Text("Progress")
                    .foregroundColor(.green)
                    .accessibilityValue("Complete")
            }
        }
        """

        let sourceFile = Parser.parse(source: sourceCode)
        visitor.walk(sourceFile)

        let colorIssues = visitor.detectedIssues.filter {
            $0.message.contains("color-based information")
        }
        #expect(colorIssues.isEmpty)
    }

    // MARK: - Non-foregroundColor Member Access (no issue expected)

    @Test("non-color member access produces no color issue")
    func nonColorMemberAccessNoIssue() {
        let visitor = createVisitor()

        let sourceCode = """
        struct ContentView: View {
            var body: some View {
                Text("Hello")
                    .font(.headline)
                    .padding()
            }
        }
        """

        let sourceFile = Parser.parse(source: sourceCode)
        visitor.walk(sourceFile)

        let colorIssues = visitor.detectedIssues.filter {
            $0.message.contains("color-based information")
        }
        #expect(colorIssues.isEmpty)
    }
}
