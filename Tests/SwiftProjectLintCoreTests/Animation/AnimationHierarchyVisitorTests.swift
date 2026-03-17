import Testing
@testable import SwiftProjectLintCore
import SwiftSyntax
import SwiftParser

struct AnimationHierarchyVisitorTests {

    private func makeVisitor(for rule: RuleIdentifier) throws -> AnimationHierarchyVisitor {
        let patterns = AnimationHierarchyPatternRegistrar().patterns
        let pattern = try #require(patterns.first { $0.name == rule })
        return AnimationHierarchyVisitor(pattern: pattern)
    }

    private func runVisitor(_ visitor: AnimationHierarchyVisitor, source: String) {
        let sourceFile = Parser.parse(source: source)
        visitor.walk(sourceFile)
    }

    // MARK: - Conflicting Animations

    @Test
    func testDetectsConflictingAnimationsSameValue() throws {
        let source = """
        import SwiftUI

        struct ConflictView: View {
            @State private var isVisible = false

            var body: some View {
                Text("Hello")
                    .animation(.easeIn, value: isVisible)
                    .animation(.spring(), value: isVisible)
            }
        }
        """

        let visitor = try makeVisitor(for: .conflictingAnimations)
        runVisitor(visitor, source: source)

        #expect(visitor.detectedIssues.count == 1)

        let issue = try #require(visitor.detectedIssues.first)
        #expect(issue.ruleName == .conflictingAnimations)
        #expect(issue.severity == .warning)
        #expect(issue.message.contains("isVisible"))
    }

    @Test
    func testNoIssueForDifferentValues() throws {
        let source = """
        import SwiftUI

        struct NoConflictView: View {
            @State private var isVisible = false
            @State private var isExpanded = false

            var body: some View {
                Text("Hello")
                    .animation(.easeIn, value: isVisible)
                    .animation(.spring(), value: isExpanded)
            }
        }
        """

        let visitor = try makeVisitor(for: .conflictingAnimations)
        runVisitor(visitor, source: source)

        #expect(visitor.detectedIssues.isEmpty)
    }

    @Test
    func testNoIssueForDeprecatedSingleArgAnimation() throws {
        let source = """
        import SwiftUI

        struct DeprecatedView: View {
            var body: some View {
                Text("Hello")
                    .animation(.easeIn)
            }
        }
        """

        let visitor = try makeVisitor(for: .conflictingAnimations)
        runVisitor(visitor, source: source)

        #expect(visitor.detectedIssues.isEmpty)
    }

    // MARK: - Default Animation Curve

    @Test
    func testDetectsDefaultAnimationCurve() throws {
        let source = """
        import SwiftUI

        struct DefaultCurveView: View {
            @State private var isVisible = false

            var body: some View {
                Text("Hello")
                    .opacity(isVisible ? 1 : 0)
                    .animation(.default, value: isVisible)
            }
        }
        """

        let visitor = try makeVisitor(for: .defaultAnimationCurve)
        runVisitor(visitor, source: source)

        #expect(visitor.detectedIssues.count == 1)

        let issue = try #require(visitor.detectedIssues.first)
        #expect(issue.ruleName == .defaultAnimationCurve)
        #expect(issue.severity == .info)
    }

    @Test
    func testNoIssueForExplicitCurve() throws {
        let source = """
        import SwiftUI

        struct ExplicitCurveView: View {
            @State private var isVisible = false

            var body: some View {
                Text("Hello")
                    .opacity(isVisible ? 1 : 0)
                    .animation(.easeInOut, value: isVisible)
            }
        }
        """

        let visitor = try makeVisitor(for: .defaultAnimationCurve)
        runVisitor(visitor, source: source)

        #expect(visitor.detectedIssues.isEmpty)
    }
}
