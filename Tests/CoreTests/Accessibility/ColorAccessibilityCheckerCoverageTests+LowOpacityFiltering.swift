import Foundation
import SwiftParser
import SwiftProjectLintModels
import SwiftProjectLintVisitors
import SwiftSyntax
import Testing

extension ColorAccessibilityCheckerCoverageTests {
    // MARK: - Low Opacity Filtering

    @Test("Color.red.opacity(0.1) is not flagged as background tint")
    func lowOpacityNotFlagged() {
        let visitor = makeAccessibilityVisitor()

        let sourceCode = """
        struct ContentView: View {
            var body: some View {
                Rectangle().background(Color.red.opacity(0.1))
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

    @Test("Color.green.opacity(0.2) is not flagged at threshold boundary")
    func opacityAtThresholdNotFlagged() {
        let visitor = makeAccessibilityVisitor()

        let sourceCode = """
        struct ContentView: View {
            var body: some View {
                Rectangle().fill(Color.green.opacity(0.2))
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

    @Test("Color.red.opacity(0.5) is still flagged above threshold")
    func highOpacityStillFlagged() {
        let visitor = makeAccessibilityVisitor()

        let sourceCode = """
        struct ContentView: View {
            var body: some View {
                Circle().fill(Color.red.opacity(0.5))
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

    @Test("Color.red without opacity is still flagged")
    func fullOpacityStillFlagged() {
        let visitor = makeAccessibilityVisitor()

        let sourceCode = """
        struct ContentView: View {
            var body: some View {
                Capsule().fill(Color.red)
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

    // MARK: - Non-foregroundColor Member Access (no issue expected)

    @Test("non-color member access produces no color issue")
    func nonColorMemberAccessNoIssue() {
        let visitor = makeAccessibilityVisitor()

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
