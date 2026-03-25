import Testing
@testable import Core
import SwiftSyntax
import SwiftParser

@Suite
struct HardcodedAnimationValuesVisitorTests {

    private func makeVisitor() -> HardcodedAnimationValuesVisitor {
        let pattern = HardcodedAnimationValues().pattern
        return HardcodedAnimationValuesVisitor(pattern: pattern)
    }

    private func runVisitor(_ visitor: HardcodedAnimationValuesVisitor, source: String) {
        let sourceFile = Parser.parse(source: source)
        visitor.walk(sourceFile)
    }

    @Test
    func testDetectsDurationLiteral() throws {
        let source = """
        import SwiftUI

        struct SlowEaseView: View {
            @State private var isVisible = false

            var body: some View {
                Text("Hello")
                    .opacity(isVisible ? 1 : 0)
                    .animation(.easeIn(duration: 0.5), value: isVisible)
            }
        }
        """

        let visitor = makeVisitor()
        runVisitor(visitor, source: source)

        #expect(visitor.detectedIssues.count == 1)

        let issue = try #require(visitor.detectedIssues.first)
        #expect(issue.ruleName == .hardcodedAnimationValues)
        #expect(issue.severity == .info)
        #expect(issue.message.contains("0.5"))
        #expect(issue.message.contains("duration"))
    }

    // swiftprojectlint:disable Test Missing Require
    @Test
    func testDetectsSpringParameters() throws {
        let source = """
        import SwiftUI

        struct SpringView: View {
            @State private var isVisible = false

            var body: some View {
                Text("Hello")
                    .scaleEffect(isVisible ? 1 : 0)
                    .animation(.spring(response: 0.3, dampingFraction: 0.8), value: isVisible)
            }
        }
        """

        let visitor = makeVisitor()
        runVisitor(visitor, source: source)

        #expect(visitor.detectedIssues.count == 2)
        #expect(visitor.detectedIssues.allSatisfy { $0.ruleName == .hardcodedAnimationValues })
        let messages = visitor.detectedIssues.map(\.message)
        #expect(messages.contains(where: { $0.contains("response") }))
        #expect(messages.contains(where: { $0.contains("dampingFraction") }))
    }

    // swiftprojectlint:disable Test Missing Require
    @Test
    func testNoIssueForAnimationWithNoParameters() {
        let source = """
        import SwiftUI

        struct DefaultSpringView: View {
            @State private var isVisible = false

            var body: some View {
                Text("Hello")
                    .animation(.spring(), value: isVisible)
            }
        }
        """

        let visitor = makeVisitor()
        runVisitor(visitor, source: source)

        #expect(visitor.detectedIssues.isEmpty)
    }

    // swiftprojectlint:disable Test Missing Require
    @Test
    func testNoIssueForNamedConstant() {
        let source = """
        import SwiftUI

        let animationDuration: Double = 0.3

        struct ConstantDurationView: View {
            @State private var isVisible = false

            var body: some View {
                Text("Hello")
                    .animation(.easeIn(duration: animationDuration), value: isVisible)
            }
        }
        """

        let visitor = makeVisitor()
        runVisitor(visitor, source: source)

        #expect(visitor.detectedIssues.isEmpty)
    }
}
