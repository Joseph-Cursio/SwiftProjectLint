@testable import Core
import SwiftParser
@testable import SwiftProjectLintRules
import SwiftSyntax
import Testing

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

    // MARK: - background / clipShape

    @Test
    func backgroundBeforeClipShapeIsCorrectOrder_notFlagged() {
        // `.background().clipShape()` clips the composited view, so the
        // background IS clipped. This is the idiomatic order — no warning.
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

        #expect(visitor.detectedIssues.isEmpty)
    }

    @Test
    func clipShapeBeforeBackground_flagged() {
        // `.clipShape().background()` draws the background behind the clipped
        // view at its rectangular bounds — the background is left unclipped.
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

        #expect(visitor.detectedIssues.count == 1)
        #expect(visitor.detectedIssues.first?.ruleName == .modifierOrderIssue)
        let message = visitor.detectedIssues.first?.message ?? ""
        #expect(message.contains("clipShape"))
        #expect(message.contains("background"))
    }

    @Test
    func backgroundBeforeCornerRadiusIsCorrectOrder_notFlagged() {
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

        #expect(visitor.detectedIssues.isEmpty)
    }

    @Test
    func cornerRadiusBeforeBackground_flagged() {
        let source = """
        import SwiftUI

        struct MyView: View {
            var body: some View {
                Text("Hello")
                    .cornerRadius(8)
                    .background(Color.green)
            }
        }
        """

        let visitor = makeVisitor()
        runVisitor(visitor, source: source)

        #expect(visitor.detectedIssues.count == 1)
    }

    // MARK: - shadow / clip (unchanged: shadow must come after the clip)

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
    func shadowBeforeClipShapeFlags() {
        let source = """
        import SwiftUI

        struct MyView: View {
            var body: some View {
                Text("Hello")
                    .shadow(radius: 5)
                    .clipShape(Circle())
            }
        }
        """

        let visitor = makeVisitor()
        runVisitor(visitor, source: source)

        #expect(visitor.detectedIssues.count == 1)
    }

    @Test
    func clipBeforeShadowIsCorrectOrder_notFlagged() {
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

    // MARK: - border ordering is no longer flagged (rule removed)

    @Test
    func borderOrderingNotFlagged() {
        // `.border` always draws a rectangle regardless of clip order, so
        // neither ordering reliably "follows the shape" — the rule was dropped.
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

        #expect(visitor.detectedIssues.isEmpty)
    }

    // MARK: - misc

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
    func mixedChainOnlyFlagsBadPairs() {
        // clip appears before background among unrelated modifiers → 1 flag.
        let source = """
        import SwiftUI

        struct MyView: View {
            var body: some View {
                Text("Hello")
                    .padding()
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                    .font(.title)
                    .background(Color.red)
            }
        }
        """

        let visitor = makeVisitor()
        runVisitor(visitor, source: source)

        #expect(visitor.detectedIssues.count == 1)
    }
}
