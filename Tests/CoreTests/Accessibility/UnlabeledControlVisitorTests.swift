@testable import Core
import SwiftParser
@testable import SwiftProjectLintRules
import SwiftSyntax
import Testing

@Suite
struct UnlabeledControlVisitorTests {

    private func makeVisitor() -> UnlabeledControlVisitor {
        UnlabeledControlVisitor(pattern: UnlabeledControl().pattern)
    }

    private func analyze(_ source: String) -> [LintIssue] {
        let visitor = makeVisitor()
        visitor.walk(Parser.parse(source: source))
        return visitor.detectedIssues
    }

    // MARK: - Positive

    @Test
    func detectsSliderWithNoLabel() throws {
        let source = """
        import SwiftUI

        struct V: View {
            @State private var volume = 0.5
            var body: some View {
                Slider(value: $volume, in: 0...1)
            }
        }
        """

        let issues = analyze(source)
        #expect(issues.count == 1)

        let issue = try #require(issues.first)
        #expect(issue.ruleName == .unlabeledControl)
        #expect(issue.severity == .warning)
        #expect(issue.message.contains("Slider"))
    }

    @Test
    func detectsDeterminateProgressViewWithNoLabel() {
        let source = """
        import SwiftUI

        struct V: View {
            let progress: Double
            var body: some View {
                ProgressView(value: progress, total: 1.0)
            }
        }
        """

        #expect(analyze(source).count == 1)
    }

    // MARK: - Negative

    @Test("No issue when a label exists or the control is named elsewhere", arguments: [
        // Trailing-closure label
        """
        import SwiftUI

        struct V: View {
            @State private var volume = 0.5
            var body: some View {
                Slider(value: $volume, in: 0...1) { Text("Volume") }
            }
        }
        """,
        // Compensating modifier
        """
        import SwiftUI

        struct V: View {
            @State private var volume = 0.5
            var body: some View {
                Slider(value: $volume, in: 0...1)
                    .accessibilityLabel("Volume")
            }
        }
        """,
        // Parent merges the children's labels
        """
        import SwiftUI

        struct V: View {
            @State private var volume = 0.5
            var body: some View {
                HStack {
                    Text("Volume")
                    Slider(value: $volume, in: 0...1)
                }
                .accessibilityElement(children: .combine)
            }
        }
        """,
        // Indeterminate spinner — usually decorative, explained by nearby text
        """
        import SwiftUI

        struct V: View {
            var body: some View {
                ProgressView()
            }
        }
        """,
        // A titled ProgressView
        """
        import SwiftUI

        struct V: View {
            let progress: Double
            var body: some View {
                ProgressView("Uploading", value: progress, total: 1.0)
            }
        }
        """,
        // Controls that cannot be written without a label are not this rule's business
        """
        import SwiftUI

        struct V: View {
            @State private var on = false
            var body: some View {
                Toggle("Bold", isOn: $on)
            }
        }
        """
    ])
    func noIssue(source: String) {
        #expect(analyze(source).isEmpty)
    }

    /// `.contain` keeps children as individual elements, so the slider stays unnamed.
    @Test
    func containedGroupStillFlags() {
        let source = """
        import SwiftUI

        struct V: View {
            @State private var volume = 0.5
            var body: some View {
                HStack {
                    Slider(value: $volume, in: 0...1)
                }
                .accessibilityElement(children: .contain)
            }
        }
        """

        #expect(analyze(source).count == 1)
    }
}
