@testable import Core
import SwiftParser
@testable import SwiftProjectLintRules
import SwiftSyntax
import Testing

@Suite
struct AnimationWithoutReduceMotionVisitorTests {

    private func makeVisitor() -> AnimationWithoutReduceMotionVisitor {
        let pattern = AnimationWithoutReduceMotion().pattern
        return AnimationWithoutReduceMotionVisitor(pattern: pattern)
    }

    private func runVisitor(_ visitor: AnimationWithoutReduceMotionVisitor, source: String) {
        let sourceFile = Parser.parse(source: source)
        visitor.walk(sourceFile)
    }

    // MARK: - Positive Cases

    @Test
    func detectsAnimatingViewWithNoReduceMotionCheck() throws {
        let source = """
        import SwiftUI

        struct MyView: View {
            @State private var isLoading = false

            var body: some View {
                Text("Loading")
                    .transition(.scale)
                    .animation(.easeInOut, value: isLoading)
            }
        }
        """

        let visitor = makeVisitor()
        runVisitor(visitor, source: source)

        #expect(visitor.detectedIssues.count == 1)

        let issue = try #require(visitor.detectedIssues.first)
        #expect(issue.ruleName == .animationWithoutReduceMotion)
        #expect(issue.severity == .info)
        #expect(issue.message.contains("MyView"))
        #expect(issue.message.contains("accessibilityReduceMotion"))
    }

    @Test
    func detectsWithAnimationCall() {
        let source = """
        import SwiftUI

        struct MyView: View {
            @State private var expanded = false

            var body: some View {
                Button("Toggle") {
                    withAnimation(.spring()) { expanded.toggle() }
                }
            }
        }
        """

        let visitor = makeVisitor()
        runVisitor(visitor, source: source)

        #expect(visitor.detectedIssues.count == 1)
    }

    /// The scan is per-view: a nested view's Reduce Motion check does not excuse
    /// the enclosing view, which animates on its own.
    @Test
    func nestedViewsCheckDoesNotExcuseTheOuterView() throws {
        let source = """
        import SwiftUI

        struct OuterView: View {
            @State private var isLoading = false

            var body: some View {
                Text("Loading")
                    .animation(.easeInOut, value: isLoading)
            }

            struct InnerView: View {
                @Environment(\\.accessibilityReduceMotion) private var reduceMotion

                var body: some View {
                    Text("Inner")
                }
            }
        }
        """

        let visitor = makeVisitor()
        runVisitor(visitor, source: source)

        #expect(visitor.detectedIssues.count == 1)

        let issue = try #require(visitor.detectedIssues.first)
        #expect(issue.message.contains("OuterView"))
    }

    // MARK: - Negative Cases

    @Test("No issue when motion is absent or the preference is consulted", arguments: [
        // Reads the environment value
        """
        import SwiftUI

        struct MyView: View {
            @Environment(\\.accessibilityReduceMotion) private var reduceMotion
            @State private var isLoading = false

            var body: some View {
                Text("Loading")
                    .animation(reduceMotion ? nil : .easeInOut, value: isLoading)
            }
        }
        """,
        // UIKit-era check counts too
        """
        import SwiftUI

        struct MyView: View {
            @State private var isLoading = false

            var body: some View {
                Text("Loading")
                    .animation(UIAccessibility.isReduceMotionEnabled ? nil : .easeInOut,
                               value: isLoading)
            }
        }
        """,
        // .animation(nil, …) disables animation rather than adding it
        """
        import SwiftUI

        struct MyView: View {
            @State private var isLoading = false

            var body: some View {
                Text("Loading")
                    .animation(nil, value: isLoading)
            }
        }
        """,
        // A transition that moves nothing
        """
        import SwiftUI

        struct MyView: View {
            var body: some View {
                Text("Hello")
                    .transition(.opacity)
            }
        }
        """,
        // .identity likewise
        """
        import SwiftUI

        struct MyView: View {
            var body: some View {
                Text("Hello")
                    .transition(.identity)
            }
        }
        """,
        // Not a SwiftUI view
        """
        import Foundation

        struct AnimationSettings {
            func apply() {
                withAnimation(.spring()) { }
            }
        }
        """,
        // No animation at all
        """
        import SwiftUI

        struct MyView: View {
            var body: some View {
                Text("Hello")
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
