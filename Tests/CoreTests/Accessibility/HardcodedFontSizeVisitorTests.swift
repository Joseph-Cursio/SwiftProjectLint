import Testing
@testable import SwiftProjectLintCore
import SwiftSyntax
import SwiftParser

@Suite
struct HardcodedFontSizeVisitorTests {

    private func makeVisitor() -> HardcodedFontSizeVisitor {
        let pattern = HardcodedFontSize().pattern
        return HardcodedFontSizeVisitor(pattern: pattern)
    }

    private func runVisitor(_ visitor: HardcodedFontSizeVisitor, source: String) {
        let sourceFile = Parser.parse(source: source)
        visitor.walk(sourceFile)
    }

    // MARK: - Positive Cases

    @Test
    func detectsLiteralIntegerSize() throws {
        let source = """
        import SwiftUI

        struct MyView: View {
            var body: some View {
                Text("Hello")
                    .font(.system(size: 48))
            }
        }
        """

        let visitor = makeVisitor()
        runVisitor(visitor, source: source)

        #expect(visitor.detectedIssues.count == 1)

        let issue = try #require(visitor.detectedIssues.first)
        #expect(issue.ruleName == .hardcodedFontSize)
        #expect(issue.severity == .warning)
        #expect(issue.message.contains("48"))
    }

    @Test
    func detectsLiteralFloatSizeWithExtraParams() throws {
        let source = """
        import SwiftUI

        struct MyView: View {
            var body: some View {
                Text("Hello")
                    .font(.system(size: 14.0, weight: .bold, design: .rounded))
            }
        }
        """

        let visitor = makeVisitor()
        runVisitor(visitor, source: source)

        #expect(visitor.detectedIssues.count == 1)

        let issue = try #require(visitor.detectedIssues.first)
        #expect(issue.ruleName == .hardcodedFontSize)
        #expect(issue.message.contains("14.0"))
    }

    // MARK: - Negative Cases

    @Test("No issue for dynamic or semantic fonts", arguments: [
        // Semantic text style
        """
        import SwiftUI

        struct MyView: View {
            var body: some View {
                Text("Hello")
                    .font(.largeTitle)
            }
        }
        """,
        // Variable size
        """
        import SwiftUI

        struct MyView: View {
            let fontSize: CGFloat = 14

            var body: some View {
                Text("Hello")
                    .font(.system(size: fontSize))
            }
        }
        """,
        // Custom font
        """
        import SwiftUI

        struct MyView: View {
            var body: some View {
                Text("Hello")
                    .font(.custom("Avenir", size: 14))
            }
        }
        """,
        // System text style
        """
        import SwiftUI

        struct MyView: View {
            var body: some View {
                Text("Hello")
                    .font(.system(.body))
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
