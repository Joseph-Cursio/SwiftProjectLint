import Testing
@testable import SwiftProjectLintCore
import SwiftSyntax
import SwiftParser

@Suite
struct HardcodedFontSizeVisitorTests {

    private func makeVisitor() -> HardcodedFontSizeVisitor {
        let pattern = HardcodedFontSizePatternRegistrar().pattern
        return HardcodedFontSizeVisitor(pattern: pattern)
    }

    private func runVisitor(_ visitor: HardcodedFontSizeVisitor, source: String) {
        let sourceFile = Parser.parse(source: source)
        visitor.walk(sourceFile)
    }

    @Test
    func testDetectsLiteralIntegerSize() throws {
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
    func testDetectsLiteralFloatSizeWithExtraParams() throws {
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

    @Test
    func testNoIssueForSemanticTextStyle() {
        let source = """
        import SwiftUI

        struct MyView: View {
            var body: some View {
                Text("Hello")
                    .font(.largeTitle)
            }
        }
        """

        let visitor = makeVisitor()
        runVisitor(visitor, source: source)

        #expect(visitor.detectedIssues.isEmpty)
    }

    @Test
    func testNoIssueForVariableSize() {
        let source = """
        import SwiftUI

        struct MyView: View {
            let fontSize: CGFloat = 14

            var body: some View {
                Text("Hello")
                    .font(.system(size: fontSize))
            }
        }
        """

        let visitor = makeVisitor()
        runVisitor(visitor, source: source)

        #expect(visitor.detectedIssues.isEmpty)
    }

    @Test
    func testNoIssueForCustomFont() {
        let source = """
        import SwiftUI

        struct MyView: View {
            var body: some View {
                Text("Hello")
                    .font(.custom("Avenir", size: 14))
            }
        }
        """

        let visitor = makeVisitor()
        runVisitor(visitor, source: source)

        #expect(visitor.detectedIssues.isEmpty)
    }

    @Test
    func testNoIssueForSystemTextStyle() {
        let source = """
        import SwiftUI

        struct MyView: View {
            var body: some View {
                Text("Hello")
                    .font(.system(.body))
            }
        }
        """

        let visitor = makeVisitor()
        runVisitor(visitor, source: source)

        #expect(visitor.detectedIssues.isEmpty)
    }
}
