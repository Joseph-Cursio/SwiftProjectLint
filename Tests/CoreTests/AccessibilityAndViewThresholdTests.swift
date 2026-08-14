@testable import Core
import Foundation
import SwiftParser
@testable import SwiftProjectLintRules
import SwiftSyntax
import Testing

/// Three rules recalibrated so they stop firing on shapes that are not the thing they warn
/// about. Each absence is paired with a control on the other side of the line.
@Suite
struct AccessibilityAndViewThresholdTests {

    private func accessibilityIssues(_ source: String) -> [LintIssue] {
        TestRegistryManager.initializeSharedRegistry()
        let visitor = AccessibilityVisitor(patternCategory: .accessibility)
        visitor.walk(Parser.parse(source: source))
        return visitor.detectedIssues
    }

    private func performanceIssues(_ source: String) -> [LintIssue] {
        let visitor = PerformanceVisitor(patternCategory: .performance)
        let syntax = Parser.parse(source: source)
        visitor.setSourceLocationConverter(
            SourceLocationConverter(fileName: "TestFile.swift", tree: syntax)
        )
        visitor.setFilePath("TestFile.swift")
        visitor.walk(syntax)
        return visitor.detectedIssues
    }

    private func viewBody(statements: Int) -> String {
        let lines = (0..<statements)
            .map { "            Text(\"line \($0)\")" }
            .joined(separator: "\n")
        return """
        struct SizedView: View {
            var body: some View {
                VStack {
        \(lines)
                }
            }
        }
        """
    }

    // MARK: - A label on the image rather than the button

    /// `hasAccessibilityModifier` walks *up* the button's own modifier chain, so a label
    /// placed on the image inside the label closure was invisible to it — and naming the
    /// image is an ordinary way to name an icon button.
    @Test("a label inside the button's label closure counts as labelled")
    func labelInsideClosureCounts() {
        let issues = accessibilityIssues("""
        struct IconRow: View {
            var body: some View {
                Button {
                    act()
                } label: {
                    Image(systemName: "star")
                        .accessibilityLabel("Favourite")
                }
            }
        }
        """)

        #expect(issues.contains { $0.ruleName == .iconOnlyButtonMissingLabel } == false)
    }

    /// Control: the same button with no label anywhere is still flagged, so the rule has
    /// not simply gone quiet on icon buttons.
    @Test("control — an icon button with no label anywhere is still flagged")
    func unlabelledIconButtonStillFlagged() {
        let issues = accessibilityIssues("""
        struct IconRow: View {
            var body: some View {
                Button {
                    act()
                } label: {
                    Image(systemName: "star")
                }
            }
        }
        """)

        #expect(issues.contains { $0.ruleName == .iconOnlyButtonMissingLabel })
    }

    // MARK: - Decorative stroke opacity

    /// A hairline border at a third opacity is decoration, not colour carrying information
    /// a colourblind reader would lose.
    @Test("a stroke at 0.3 opacity is treated as decorative")
    func decorativeStrokeIsExempt() {
        let issues = accessibilityIssues("""
        struct CardBorder: View {
            var body: some View {
                RoundedRectangle(cornerRadius: 8)
                    .stroke(Color.red.opacity(0.3), lineWidth: 1)
            }
        }
        """)

        #expect(issues.contains { $0.ruleName == .inaccessibleColorUsage } == false)
    }

    /// Control: above the threshold the colour is doing real work again and still fires,
    /// so the exemption is the opacity and not the `.stroke` shape.
    @Test("control — a stroke at 0.5 opacity still fires")
    func strongerStrokeStillFires() {
        let issues = accessibilityIssues("""
        struct CardBorder: View {
            var body: some View {
                RoundedRectangle(cornerRadius: 8)
                    .stroke(Color.red.opacity(0.5), lineWidth: 1)
            }
        }
        """)

        #expect(issues.contains { $0.ruleName == .inaccessibleColorUsage })
    }

    // MARK: - Large view body threshold

    @Test("a body of 22 statements is no longer called large")
    func mediumBodyIsNotLarge() {
        let issues = performanceIssues(viewBody(statements: 22))

        #expect(issues.contains { $0.ruleName == .largeViewBody } == false)
    }

    /// Control: past the new threshold the rule still fires, so raising it did not switch
    /// the rule off.
    @Test("control — a body of 30 statements is still large")
    func largeBodyStillFires() {
        let issues = performanceIssues(viewBody(statements: 30))

        #expect(issues.contains { $0.ruleName == .largeViewBody })
    }
}
