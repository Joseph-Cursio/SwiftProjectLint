import SwiftParser
import SwiftProjectLintModels
@testable import SwiftProjectLintRules
import SwiftProjectLintVisitors
import SwiftSyntax
import Testing

struct PerformanceVisitorTests {

    func makeVisitor(
        for rule: RuleIdentifier = .excessiveSpringAnimations
    ) throws -> AnimationPerformanceVisitor {
        let patterns = AnimationPerformance().patterns
        let pattern = try #require(patterns.first { $0.name == rule })
        return AnimationPerformanceVisitor(pattern: pattern)
    }

    func runVisitor(_ visitor: AnimationPerformanceVisitor, source: String) {
        let sourceFile = Parser.parse(source: source)
        visitor.walk(sourceFile)
    }

    // MARK: - Excessive Spring Animations

    @Test
    func detectsExcessiveSpringAnimations() throws {
        let source = """
        import SwiftUI

        struct AnimatedView: View {
            @State private var a = false
            @State private var b = false
            @State private var c = false
            @State private var d = false

            var body: some View {
                VStack {
                    Text("1").animation(.spring(), value: a)
                    Text("2").animation(.spring(), value: b)
                    Text("3").animation(.spring(), value: c)
                    Text("4").animation(.spring(), value: d)
                }
            }
        }
        """

        let visitor = try makeVisitor()
        runVisitor(visitor, source: source)

        #expect(visitor.detectedIssues.count == 1)

        let issue = try #require(visitor.detectedIssues.first)
        #expect(issue.ruleName == .excessiveSpringAnimations)
        #expect(issue.severity == .warning)
        #expect(issue.message.contains("AnimatedView"))
        #expect(issue.message.contains("4"))
    }

    @Test
    func allowsThreeOrFewerSpringAnimations() throws {
        let source = """
        import SwiftUI

        struct ModerateView: View {
            @State private var a = false
            @State private var b = false
            @State private var c = false

            var body: some View {
                VStack {
                    Text("1").animation(.spring(), value: a)
                    Text("2").animation(.spring(), value: b)
                    Text("3").animation(.spring(), value: c)
                }
            }
        }
        """

        let visitor = try makeVisitor()
        runVisitor(visitor, source: source)

        #expect(visitor.detectedIssues.isEmpty)
    }

    @Test
    func countResetsPerStruct() throws {
        let source = """
        import SwiftUI

        struct ViewA: View {
            @State private var a = false
            @State private var b = false

            var body: some View {
                VStack {
                    Text("1").animation(.spring(), value: a)
                    Text("2").animation(.spring(), value: b)
                }
            }
        }

        struct ViewB: View {
            @State private var c = false
            @State private var d = false

            var body: some View {
                VStack {
                    Text("3").animation(.spring(), value: c)
                    Text("4").animation(.spring(), value: d)
                }
            }
        }
        """

        let visitor = try makeVisitor()
        runVisitor(visitor, source: source)

        #expect(visitor.detectedIssues.isEmpty)
    }

    @Test
    func detectsSpringWithParameters() throws {
        let source = """
        import SwiftUI

        struct ParameterizedView: View {
            @State private var a = false
            @State private var b = false
            @State private var c = false
            @State private var d = false

            var body: some View {
                VStack {
                    Text("1").animation(.spring(response: 0.5, dampingFraction: 0.8), value: a)
                    Text("2").animation(.spring(response: 0.3, dampingFraction: 0.6), value: b)
                    Text("3").animation(.spring(duration: 0.4, bounce: 0.2), value: c)
                    Text("4").animation(.spring(), value: d)
                }
            }
        }
        """

        let visitor = try makeVisitor()
        runVisitor(visitor, source: source)

        #expect(visitor.detectedIssues.count == 1)

        let issue = try #require(visitor.detectedIssues.first)
        #expect(issue.ruleName == .excessiveSpringAnimations)
    }

    @Test
    func ignoresNonSpringAnimations() throws {
        let source = """
        import SwiftUI

        struct EaseView: View {
            @State private var a = false
            @State private var b = false
            @State private var c = false
            @State private var d = false

            var body: some View {
                VStack {
                    Text("1").animation(.easeIn, value: a)
                    Text("2").animation(.easeOut, value: b)
                    Text("3").animation(.linear, value: c)
                    Text("4").animation(.default, value: d)
                }
            }
        }
        """

        let visitor = try makeVisitor()
        runVisitor(visitor, source: source)

        #expect(visitor.detectedIssues.isEmpty)
    }
}
