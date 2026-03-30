import Testing
import Foundation
import SwiftSyntax
import SwiftParser
@testable import Core
@testable import SwiftProjectLintRules

@Suite("ColorAccessibilityChecker Coverage Tests")
struct ColorAccessibilityCheckerCoverageTests {

    // MARK: - Test Helper Methods

    private func makeAccessibilityVisitor() -> AccessibilityVisitor {
        TestRegistryManager.initializeSharedRegistry()
        return AccessibilityVisitor(patternCategory: .accessibility)
    }

    // MARK: - Direct Color Usage (Color.xxx pattern)

    @Test("detects direct Color.red usage as accessibility concern")
    func detectsDirectColorUsage() throws {
        let visitor = makeAccessibilityVisitor()

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
        let visitor = makeAccessibilityVisitor()

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
        let visitor = makeAccessibilityVisitor()

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
        let visitor = makeAccessibilityVisitor()

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
        let visitor = makeAccessibilityVisitor()

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
        let visitor = makeAccessibilityVisitor()

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

    // MARK: - Non-Informational Color Filtering

    @Test("Color.clear is not flagged")
    func colorClearNotFlagged() {
        let visitor = makeAccessibilityVisitor()

        let sourceCode = """
        struct ContentView: View {
            var body: some View {
                Rectangle().fill(Color.clear)
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

    @Test("Color.gray is not flagged")
    func colorGrayNotFlagged() {
        let visitor = makeAccessibilityVisitor()

        let sourceCode = """
        struct ContentView: View {
            var body: some View {
                Rectangle().fill(Color.gray)
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

    @Test("Color.accentColor is not flagged")
    func colorAccentColorNotFlagged() {
        let visitor = makeAccessibilityVisitor()

        let sourceCode = """
        struct ContentView: View {
            var body: some View {
                Circle().fill(Color.accentColor)
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

    @Test("Color.secondary is not flagged")
    func colorSecondaryNotFlagged() {
        let visitor = makeAccessibilityVisitor()

        let sourceCode = """
        struct ContentView: View {
            var body: some View {
                Text("Hi").foregroundStyle(Color.secondary)
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
