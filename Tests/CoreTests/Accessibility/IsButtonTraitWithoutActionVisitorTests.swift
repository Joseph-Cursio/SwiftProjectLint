@testable import Core
import SwiftParser
@testable import SwiftProjectLintRules
import SwiftSyntax
import Testing

@Suite
struct IsButtonTraitWithoutActionVisitorTests {

    private func makeVisitor() -> IsButtonTraitWithoutActionVisitor {
        let pattern = IsButtonTraitWithoutAction().pattern
        return IsButtonTraitWithoutActionVisitor(pattern: pattern)
    }

    private func runVisitor(_ visitor: IsButtonTraitWithoutActionVisitor, source: String) {
        let sourceFile = Parser.parse(source: source)
        visitor.walk(sourceFile)
    }

    // MARK: - Positive Cases

    @Test
    func detectsButtonTraitWithNoAction() throws {
        let source = """
        import SwiftUI

        struct MyView: View {
            var body: some View {
                HStack {
                    Text("Mars")
                    Image(systemName: "heart")
                }
                .accessibilityElement(children: .ignore)
                .accessibilityAddTraits(.isButton)
            }
        }
        """

        let visitor = makeVisitor()
        runVisitor(visitor, source: source)

        #expect(visitor.detectedIssues.count == 1)

        let issue = try #require(visitor.detectedIssues.first)
        #expect(issue.ruleName == .isButtonTraitWithoutAction)
        #expect(issue.severity == .warning)
        #expect(issue.message.contains("activate gesture"))
    }

    @Test
    func detectsButtonTraitInsideTraitArray() {
        let source = """
        import SwiftUI

        struct MyView: View {
            var body: some View {
                VStack {
                    Text("Mars")
                }
                .accessibilityAddTraits([.isButton, .isSelected])
            }
        }
        """

        let visitor = makeVisitor()
        runVisitor(visitor, source: source)

        #expect(visitor.detectedIssues.count == 1)
    }

    /// The chain is collected as a whole, so an action applied *before* the trait
    /// still counts. This case has no action at all and must still be flagged even
    /// though the trait comes first.
    @Test
    func detectsWhenTraitPrecedesOtherModifiers() {
        let source = """
        import SwiftUI

        struct MyView: View {
            var body: some View {
                VStack {
                    Text("Mars")
                }
                .accessibilityAddTraits(.isButton)
                .padding()
                .background(Color.red)
            }
        }
        """

        let visitor = makeVisitor()
        runVisitor(visitor, source: source)

        #expect(visitor.detectedIssues.count == 1)
    }

    // MARK: - Negative Cases

    @Test("No issue when the element is activatable", arguments: [
        // Explicit accessibility action
        """
        import SwiftUI

        struct MyView: View {
            var body: some View {
                HStack { Text("Mars") }
                    .accessibilityAddTraits(.isButton)
                    .accessibilityAction { tapped() }
            }
        }
        """,
        // Action applied before the trait — order must not matter
        """
        import SwiftUI

        struct MyView: View {
            var body: some View {
                HStack { Text("Mars") }
                    .accessibilityAction { tapped() }
                    .accessibilityAddTraits(.isButton)
            }
        }
        """,
        // A tap gesture the activate gesture can reach
        """
        import SwiftUI

        struct MyView: View {
            var body: some View {
                HStack { Text("Mars") }
                    .accessibilityAddTraits(.isButton)
                    .onTapGesture { tapped() }
            }
        }
        """,
        // Already a Button — the trait is redundant, not broken
        """
        import SwiftUI

        struct MyView: View {
            var body: some View {
                Button("Mars") { tapped() }
                    .accessibilityAddTraits(.isButton)
            }
        }
        """,
        // NavigationLink carries its own activation
        """
        import SwiftUI

        struct MyView: View {
            var body: some View {
                NavigationLink("Mars", destination: DetailView())
                    .accessibilityAddTraits(.isButton)
            }
        }
        """,
        // A different trait entirely
        """
        import SwiftUI

        struct MyView: View {
            var body: some View {
                Text("Mars")
                    .accessibilityAddTraits(.isHeader)
            }
        }
        """,
        // No accessibility traits at all
        """
        import SwiftUI

        struct MyView: View {
            var body: some View {
                HStack { Text("Mars") }
                    .padding()
            }
        }
        """
    ])
    func noIssue(source: String) {
        let visitor = makeVisitor()
        runVisitor(visitor, source: source)

        #expect(visitor.detectedIssues.isEmpty)
    }
}
