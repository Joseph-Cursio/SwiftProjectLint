@testable import Core
import Foundation
import SwiftParser
@testable import SwiftProjectLintRules
import SwiftSyntax
import Testing

@Suite
struct ControlMissingAccessibilityLabelVisitorTests {

    private func analyze(_ source: String, filePath: String = "TestFile.swift") -> [LintIssue] {
        let visitor = ControlMissingAccessibilityLabelVisitor(patternCategory: .accessibility)
        let syntax = Parser.parse(source: source)
        let converter = SourceLocationConverter(fileName: filePath, tree: syntax)
        visitor.setSourceLocationConverter(converter)
        visitor.setFilePath(filePath)
        visitor.walk(syntax)
        return visitor.detectedIssues.filter { $0.ruleName == .controlMissingAccessibilityLabel }
    }

    // MARK: - Positive

    @Test func testFlagsEmptyLabelToggle() throws {
        let source = """
        struct V: View {
            @State private var on = false
            var body: some View {
                Toggle("", isOn: $on).labelsHidden()
            }
        }
        """
        let issues = analyze(source)
        let issue = try #require(issues.first)
        #expect(issues.count == 1)
        #expect(issue.severity == .warning)
        #expect(issue.message.contains("Toggle"))
    }

    @Test func testFlagsEmptyLabelButton() {
        let source = """
        struct V: View {
            var body: some View { Button("", action: save) }
        }
        """
        #expect(analyze(source).count == 1)
    }

    // MARK: - Negative (no false positives)

    @Test func testNonEmptyLabelNotFlagged() {
        let source = """
        struct V: View {
            @State private var on = false
            var body: some View { Toggle("Bold", isOn: $on) }
        }
        """
        #expect(analyze(source).isEmpty)
    }

    @Test func testEmptyLabelWithAccessibilityLabelNotFlagged() {
        let source = """
        struct V: View {
            @State private var on = false
            var body: some View {
                Toggle("", isOn: $on)
                    .labelsHidden()
                    .accessibilityLabel("Enable rule")
            }
        }
        """
        #expect(analyze(source).isEmpty)
    }

    @Test func testNonEmptyExpressionLabelNotFlagged() {
        // The fixed RuleSelectionDialog form: label from a property, not "".
        let source = """
        struct V: View {
            let name: String
            @State private var on = false
            var body: some View { Toggle(name, isOn: $on).labelsHidden() }
        }
        """
        #expect(analyze(source).isEmpty)
    }

    @Test func testIconOnlyButtonNotFlaggedHere() {
        // Closure-label (icon-only) form has no string label arg — owned by the
        // Icon-Only Button Missing Label rule, not this one.
        let source = """
        struct V: View {
            var body: some View {
                Button(action: save) { Image(systemName: "gear") }
            }
        }
        """
        #expect(analyze(source).isEmpty)
    }
}
