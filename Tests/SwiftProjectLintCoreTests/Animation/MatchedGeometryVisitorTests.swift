import Testing
@testable import SwiftProjectLintCore
import SwiftSyntax
import SwiftParser

@Suite
struct MatchedGeometryVisitorTests {

    private func makeVisitor() -> MatchedGeometryVisitor {
        let pattern = MatchedGeometryPatternRegistrar().pattern
        return MatchedGeometryVisitor(pattern: pattern)
    }

    private func runVisitor(_ visitor: MatchedGeometryVisitor, source: String) {
        let sourceFile = Parser.parse(source: source)
        visitor.walk(sourceFile)
    }

    @Test
    func testDetectsUndeclaredNamespace() throws {
        let source = """
        import SwiftUI

        struct HeroView: View {
            var body: some View {
                Text("Hero")
                    .matchedGeometryEffect(id: "hero", in: undeclaredNS)
            }
        }
        """

        let visitor = makeVisitor()
        runVisitor(visitor, source: source)

        #expect(visitor.detectedIssues.count == 1)

        let issue = try #require(visitor.detectedIssues.first)
        #expect(issue.ruleName == .matchedGeometryEffectMisuse)
        #expect(issue.severity == .warning)
        #expect(issue.message.contains("undeclaredNS"))
    }

    @Test
    func testNoIssueForDeclaredNamespace() {
        let source = """
        import SwiftUI

        struct HeroView: View {
            @Namespace private var ns

            var body: some View {
                Text("Hero")
                    .matchedGeometryEffect(id: "hero", in: ns)
            }
        }
        """

        let visitor = makeVisitor()
        runVisitor(visitor, source: source)

        #expect(visitor.detectedIssues.isEmpty)
    }

    @Test
    func testDetectsDuplicateId() throws {
        let source = """
        import SwiftUI

        struct DuplicateView: View {
            @Namespace private var ns

            var body: some View {
                VStack {
                    Text("Source")
                        .matchedGeometryEffect(id: "card", in: ns)
                    Text("Destination")
                        .matchedGeometryEffect(id: "card", in: ns)
                }
            }
        }
        """

        let visitor = makeVisitor()
        runVisitor(visitor, source: source)

        #expect(visitor.detectedIssues.count == 1)

        let issue = try #require(visitor.detectedIssues.first)
        #expect(issue.ruleName == .matchedGeometryEffectMisuse)
        #expect(issue.message.contains("card"))
    }

    @Test
    func testNoIssueForDifferentIds() {
        let source = """
        import SwiftUI

        struct UniqueIdsView: View {
            @Namespace private var ns

            var body: some View {
                VStack {
                    Text("Source")
                        .matchedGeometryEffect(id: "source", in: ns)
                    Text("Destination")
                        .matchedGeometryEffect(id: "destination", in: ns)
                }
            }
        }
        """

        let visitor = makeVisitor()
        runVisitor(visitor, source: source)

        #expect(visitor.detectedIssues.isEmpty)
    }
}
