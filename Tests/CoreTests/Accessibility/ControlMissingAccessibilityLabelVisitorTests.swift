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

    @Test func testFlagsEmptyStringTitleOnNewControls() {
        // Slider, Stepper and Picker all take a title as their first positional argument.
        let sources = [
            #"struct V: View { var body: some View { Picker("", selection: $c) { Text("A") } } }"#,
            #"struct V: View { var body: some View { Stepper("", value: $n) } }"#
        ]
        for source in sources {
            #expect(analyze(source).count == 1, "expected one issue for: \(source)")
        }
    }

    @Test func testFlagsEmptyLabelClosure() throws {
        let source = """
        struct V: View {
            @State private var on = false
            var body: some View {
                Toggle(isOn: $on) { }
            }
        }
        """
        let issues = analyze(source)
        let issue = try #require(issues.first)
        #expect(issues.count == 1)
        #expect(issue.message.contains("empty label closure"))
    }

    @Test func testFlagsEmptyViewLabelClosure() {
        // `EmptyView()` renders nothing, so it is an empty label in every sense that matters.
        let source = """
        struct V: View {
            @State private var volume = 0.5
            var body: some View {
                Slider(value: $volume, in: 0...1) { EmptyView() }
            }
        }
        """
        #expect(analyze(source).count == 1)
    }

    // MARK: - Negative (no false positives)

    @Test func testPickerContentClosureNotTreatedAsLabel() {
        // A Picker's trailing closure is its option content, not its label. A titled
        // Picker with options is correct and must not be flagged.
        let source = """
        struct V: View {
            @State private var choice = 0
            var body: some View {
                Picker("Theme", selection: $choice) {
                    Text("Light").tag(0)
                    Text("Dark").tag(1)
                }
            }
        }
        """
        #expect(analyze(source).isEmpty)
    }

    @Test func testAbsentLabelNotFlaggedHere() {
        // A missing label is a different shape from an empty one, and is not this
        // rule's concern.
        let source = """
        struct V: View {
            @State private var volume = 0.5
            var body: some View { Slider(value: $volume, in: 0...1) }
        }
        """
        #expect(analyze(source).isEmpty)
    }

    @Test func testEmptyLabelInsideCombiningGroupNotFlagged() {
        // The parent merges its children's labels, so the control is named by the group.
        let source = """
        struct V: View {
            @State private var on = false
            var body: some View {
                HStack {
                    Text("Bold")
                    Toggle("", isOn: $on).labelsHidden()
                }
                .accessibilityElement(children: .combine)
            }
        }
        """
        #expect(analyze(source).isEmpty)
    }

    @Test func testEmptyLabelInsideIgnoringGroupNotFlagged() {
        let source = """
        struct V: View {
            @State private var on = false
            var body: some View {
                HStack {
                    Text("Bold")
                    Toggle("", isOn: $on).labelsHidden()
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("Bold")
            }
        }
        """
        #expect(analyze(source).isEmpty)
    }

    @Test func testContainedGroupStillFlags() {
        // `.contain` keeps children as individual elements, so an unlabeled child
        // stays unlabeled — this must still be flagged.
        let source = """
        struct V: View {
            @State private var on = false
            var body: some View {
                HStack {
                    Toggle("", isOn: $on).labelsHidden()
                }
                .accessibilityElement(children: .contain)
            }
        }
        """
        #expect(analyze(source).count == 1)
    }

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
