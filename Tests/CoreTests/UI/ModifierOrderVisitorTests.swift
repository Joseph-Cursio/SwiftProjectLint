import Testing
@testable import Core
@testable import SwiftProjectLintRules
import SwiftSyntax
import SwiftParser

@Suite
struct ModifierOrderVisitorTests {

    private func makeVisitor() -> ModifierOrderVisitor {
        let pattern = ModifierOrder().pattern
        return ModifierOrderVisitor(pattern: pattern)
    }

    private func runVisitor(_ visitor: ModifierOrderVisitor, source: String) {
        let sourceFile = Parser.parse(source: source)
        visitor.walk(sourceFile)
    }

    @Test
    func backgroundBeforeClipShapeFlags() {
        let source = """
        import SwiftUI

        struct MyView: View {
            var body: some View {
                Text("Hello")
                    .background(Color.red)
                    .clipShape(RoundedRectangle(cornerRadius: 10))
            }
        }
        """

        let visitor = makeVisitor()
        runVisitor(visitor, source: source)

        #expect(visitor.detectedIssues.count == 1)
        #expect(visitor.detectedIssues.first?.ruleName == .modifierOrderIssue)
        let message = visitor.detectedIssues.first?.message ?? ""
        #expect(message.contains("background"))
        #expect(message.contains("clipShape"))
    }

    @Test
    func clipShapeBeforeBackgroundClean() {
        let source = """
        import SwiftUI

        struct MyView: View {
            var body: some View {
                Text("Hello")
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                    .background(Color.red)
            }
        }
        """

        let visitor = makeVisitor()
        runVisitor(visitor, source: source)

        #expect(visitor.detectedIssues.isEmpty)
    }

    @Test
    func shadowBeforeCornerRadiusFlags() {
        let source = """
        import SwiftUI

        struct MyView: View {
            var body: some View {
                Text("Hello")
                    .shadow(radius: 5)
                    .cornerRadius(10)
            }
        }
        """

        let visitor = makeVisitor()
        runVisitor(visitor, source: source)

        #expect(visitor.detectedIssues.count == 1)
    }

    @Test
    func cornerRadiusBeforeShadowClean() {
        let source = """
        import SwiftUI

        struct MyView: View {
            var body: some View {
                Text("Hello")
                    .cornerRadius(10)
                    .shadow(radius: 5)
            }
        }
        """

        let visitor = makeVisitor()
        runVisitor(visitor, source: source)

        #expect(visitor.detectedIssues.isEmpty)
    }

    @Test
    func borderBeforeClipShapeFlags() {
        let source = """
        import SwiftUI

        struct MyView: View {
            var body: some View {
                Text("Hello")
                    .border(Color.blue)
                    .clipShape(Circle())
            }
        }
        """

        let visitor = makeVisitor()
        runVisitor(visitor, source: source)

        #expect(visitor.detectedIssues.count == 1)
    }

    @Test
    func noRelevantModifiersClean() {
        let source = """
        import SwiftUI

        struct MyView: View {
            var body: some View {
                Text("Hello")
                    .padding()
                    .font(.title)
                    .foregroundColor(.blue)
            }
        }
        """

        let visitor = makeVisitor()
        runVisitor(visitor, source: source)

        #expect(visitor.detectedIssues.isEmpty)
    }

    @Test
    func backgroundBeforeCornerRadiusFlags() {
        let source = """
        import SwiftUI

        struct MyView: View {
            var body: some View {
                Text("Hello")
                    .background(Color.green)
                    .cornerRadius(8)
            }
        }
        """

        let visitor = makeVisitor()
        runVisitor(visitor, source: source)

        #expect(visitor.detectedIssues.count == 1)
    }

    @Test
    func mixedChainOnlyFlagsBadPairs() {
        let source = """
        import SwiftUI

        struct MyView: View {
            var body: some View {
                Text("Hello")
                    .padding()
                    .background(Color.red)
                    .font(.title)
                    .clipShape(RoundedRectangle(cornerRadius: 10))
            }
        }
        """

        let visitor = makeVisitor()
        runVisitor(visitor, source: source)

        #expect(visitor.detectedIssues.count == 1)
    }
}
