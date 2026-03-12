import Testing
@testable import SwiftProjectLintCore
import SwiftSyntax
import SwiftParser

@Suite
struct AnimationVisitorTests {

    private func makeVisitor() -> DeprecatedAnimationVisitor {
        let pattern = DeprecatedAnimationPatternRegistrar().pattern
        return DeprecatedAnimationVisitor(pattern: pattern)
    }

    @Test
    func deprecatedAnimationModifierDetection() throws {
        let sourceCode = """
        import SwiftUI

        struct MyView: View {
            @State private var isAnimating = false

            var body: some View {
                Text("Hello, World!")
                    .animation(.default)
                    .padding()
            }
        }
        """

        let visitor = makeVisitor()
        let sourceFile = Parser.parse(source: sourceCode)
        visitor.walk(sourceFile)
        let issues = visitor.detectedIssues

        #expect(issues.count == 1)
        #expect(issues.first?.ruleName == .deprecatedAnimation)
    }

    @Test
    func modernAnimationModifierDoesNotTriggerIssue() throws {
        let sourceCode = """
        import SwiftUI

        struct MyView: View {
            @State private var isAnimating = false

            var body: some View {
                Text("Hello, World!")
                    .animation(.default, value: isAnimating)
                    .padding()
            }
        }
        """

        let visitor = makeVisitor()
        let sourceFile = Parser.parse(source: sourceCode)
        visitor.walk(sourceFile)
        let issues = visitor.detectedIssues

        #expect(issues.isEmpty)
    }
}
