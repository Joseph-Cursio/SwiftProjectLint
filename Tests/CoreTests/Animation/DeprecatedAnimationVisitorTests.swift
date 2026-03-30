import Testing
@testable import Core
@testable import SwiftProjectLintRules
import SwiftSyntax
import SwiftParser

@Suite
struct DeprecatedAnimationVisitorTests {

    private func makeVisitor() -> DeprecatedAnimationVisitor {
        let pattern = DeprecatedAnimation().pattern
        return DeprecatedAnimationVisitor(pattern: pattern)
    }

    private func runVisitor(_ visitor: DeprecatedAnimationVisitor, source: String) {
        let sourceFile = Parser.parse(source: source)
        visitor.walk(sourceFile)
    }

    @Test
    func deprecatedAnimationModifier() throws {
        let source = """
        import SwiftUI

        struct MyView: View {
            var body: some View {
                Text("Hello, World!")
                    .animation(.default)
            }
        }
        """

        let visitor = makeVisitor()
        runVisitor(visitor, source: source)

        #expect(visitor.detectedIssues.count == 1)

        let issue = try #require(visitor.detectedIssues.first)
        #expect(issue.ruleName == .deprecatedAnimation)
        #expect(issue.severity == .warning)
    }

    @Test
    func modernAnimationModifier() throws {
        let source = """
        import SwiftUI

        struct MyView: View {
            @State private var didChange = false
            var body: some View {
                Text("Hello, World!")
                    .animation(.default, value: didChange)
            }
        }
        """

        let visitor = makeVisitor()
        runVisitor(visitor, source: source)

        #expect(visitor.detectedIssues.isEmpty)
    }

    @Test
    func bindingAnimationModifier() throws {
        let source = """
        import SwiftUI

        struct MyView: View {
            @State private var didChange = false
            var body: some View {
                let textBinding = Binding(get: { "Hello" }, set: { _ in })
                TextField("Title", text: textBinding.animation())
            }
        }
        """

        let visitor = makeVisitor()
        runVisitor(visitor, source: source)

        #expect(visitor.detectedIssues.isEmpty)
    }
}
