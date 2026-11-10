@testable import Core
import SwiftParser
@testable import SwiftProjectLintRules
import SwiftSyntax
import Testing

extension PerformanceVisitorCoverageTests {
    // MARK: - CodeBlockSyntax statement counting in view body (lines 160-163)

    @Test("counts statements in code blocks within view body")
    func countsStatementsInCodeBlocks() {
        let source = """
        struct BlockView: View {
            @State private var flag = false
            var body: some View {
                VStack {
                    if flag {
                        Text("Yes")
                        Text("Also yes")
                        Text("Still yes")
                    }
                    Text("Always")
                }
            }
        }
        """

        let visitor = makeVisitor(source: source)
        // The code block and item list counting paths should be exercised
        // No large body issue expected since < 20 statements
        let largeBodyIssues = visitor.detectedIssues.filter {
            $0.ruleName == .largeViewBody
        }
        #expect(largeBodyIssues.isEmpty)
    }

    // MARK: - No expensive operations outside view body

    @Test("does not flag expensive operations outside view body")
    func noFlagOutsideViewBody() {
        let source = """
        struct SafeView: View {
            let items = [1, 2, 3].sorted()

            var body: some View {
                Text("Hello")
            }
        }
        """

        let visitor = makeVisitor(source: source)
        let expensiveIssues = visitor.detectedIssues.filter {
            $0.ruleName == .expensiveOperationInViewBody
        }
        #expect(expensiveIssues.isEmpty)
    }

    // MARK: - AccessorBlockSyntax coverage (lines 208-210)

    @Test("accessor block inside view body is visited without crash")
    func accessorBlockInViewBody() {
        let source = """
        struct AccessorView: View {
            var body: some View {
                Text("Hello")
            }

            var title: String {
                get { return "Title" }
                set { }
            }
        }
        """

        let visitor = makeVisitor(source: source)
        // The important thing is it doesn't crash; no specific issue expected
        // Exercising the AccessorBlock visit path is the goal
        _ = visitor.detectedIssues
    }
}
