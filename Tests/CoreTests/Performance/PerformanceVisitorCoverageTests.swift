import Testing
import SwiftSyntax
import SwiftParser
@testable import Core

/// Coverage tests for uncovered paths in PerformanceVisitor.swift:
/// - body computed property with getter accessing large view body (line 56, 61-73)
/// - helper method/property size check (lines 89-91)
/// - expensive operations in view body (lines 105-112)
/// - MemberAccessExprSyntax tracking in body (line 148)
/// - CodeBlockSyntax / CodeBlockItemListSyntax counting (lines 160-163)
/// - visitPost large body detection for VariableDeclSyntax (lines 180-188)
/// - visitPost large body detection for FunctionDeclSyntax (lines 194-203)
/// - AccessorBlockSyntax visit (lines 208-210)
/// - checkHelperSize (lines 227-228)
@Suite("PerformanceVisitor Coverage Tests")
struct PerformanceVisitorCoverageTests {

    private func makeVisitor(
        source: String,
        filePath: String = "TestView.swift"
    ) -> PerformanceVisitor {
        let syntax = Parser.parse(source: source)
        let visitor = PerformanceVisitor(patternCategory: .performance)
        let converter = SourceLocationConverter(fileName: filePath, tree: syntax)
        visitor.setSourceLocationConverter(converter)
        visitor.setFilePath(filePath)
        visitor.walk(syntax)
        return visitor
    }

    // MARK: - Expensive operations in view body (lines 105-112)

    @Test("detects sorted free function call in view body")
    func detectsSortedInViewBody() throws {
        // The visitor checks for DeclReferenceExprSyntax (free function calls),
        // not method calls like items.sorted(). Using sorted(items) syntax.
        let source = """
        struct ListView: View {
            @State private var items: [String] = []
            var body: some View {
                let result = sorted(items)
                Text(result.description)
            }
        }
        """

        let visitor = makeVisitor(source: source)
        let expensiveIssues = visitor.detectedIssues.filter {
            $0.ruleName == .expensiveOperationInViewBody
        }
        #expect(expensiveIssues.count >= 1)
        if let issue = expensiveIssues.first {
            #expect(issue.message.contains("sorted"))
        }
    }

    @Test("detects reduce free function call in view body")
    func detectsReduceInViewBody() throws {
        let source = """
        struct ReduceView: View {
            var body: some View {
                let total = reduce([1, 2, 3], 0)
                Text("\\(total)")
            }
        }
        """

        let visitor = makeVisitor(source: source)
        let expensiveIssues = visitor.detectedIssues.filter {
            $0.ruleName == .expensiveOperationInViewBody
        }
        #expect(expensiveIssues.count >= 1)
    }

    @Test("detects compactMap free function call in view body")
    func detectsCompactMapInViewBody() throws {
        let source = """
        struct CompactMapView: View {
            var body: some View {
                let items = compactMap([nil, "a", nil])
                Text(items.description)
            }
        }
        """

        let visitor = makeVisitor(source: source)
        let expensiveIssues = visitor.detectedIssues.filter {
            $0.ruleName == .expensiveOperationInViewBody
        }
        #expect(expensiveIssues.count >= 1)
    }

    // MARK: - Large view body via visitPost on VariableDeclSyntax (lines 180-188)

    @Test("detects large view body in computed property via visitPost")
    func largeViewBodyInComputedProperty() throws {
        // Generate a body with more than 20 statements
        var bodyLines = ""
        for idx in 0..<25 {
            bodyLines += "            Text(\"Line \\(idx)\")\n"
        }
        let source = """
        struct LargeView: View {
            var body: some View {
                VStack {
        \(bodyLines)
                }
            }
        }
        """

        let visitor = makeVisitor(source: source)
        let largeBodyIssues = visitor.detectedIssues.filter {
            $0.ruleName == .largeViewBody
        }
        #expect(largeBodyIssues.count >= 1)
    }

    // MARK: - Large view body via visitPost on FunctionDeclSyntax (lines 194-203)

    @Test("detects large view body in func body via visitPost")
    func largeViewBodyInFuncBody() throws {
        var bodyLines = ""
        for idx in 0..<25 {
            bodyLines += "            Text(\"Item \\(idx)\")\n"
        }
        let source = """
        struct LargeFuncView: View {
            func body() -> some View {
                VStack {
        \(bodyLines)
                }
            }
        }
        """

        let visitor = makeVisitor(source: source)
        let largeBodyIssues = visitor.detectedIssues.filter {
            $0.ruleName == .largeViewBody
        }
        #expect(largeBodyIssues.count >= 1)
    }

    // MARK: - Helper size check (lines 89-91, 227-228)

    @Test("detects oversized helper method in View struct")
    func detectsLargeHelperMethod() throws {
        var helperLines = ""
        for idx in 0..<55 {
            helperLines += "        let val\\(idx) = \\(idx)\n"
        }
        let source = """
        struct HelperView: View {
            var body: some View {
                Text("Hello")
            }

            func makeContent() -> some View {
        \(helperLines)
                return Text("done")
            }
        }
        """

        let visitor = makeVisitor(source: source)
        let helperIssues = visitor.detectedIssues.filter {
            $0.ruleName == .largeViewHelper
        }
        #expect(helperIssues.count >= 1)
        if let issue = helperIssues.first {
            #expect(issue.message.contains("makeContent"))
        }
    }

    @Test("detects oversized helper computed property in View struct")
    func detectsLargeHelperComputedProperty() throws {
        var helperLines = ""
        for idx in 0..<55 {
            helperLines += "        let val\\(idx) = \\(idx)\n"
        }
        let source = """
        struct HelperView: View {
            var body: some View {
                Text("Hello")
            }

            var contentSection: some View {
        \(helperLines)
                return Text("done")
            }
        }
        """

        let visitor = makeVisitor(source: source)
        let helperIssues = visitor.detectedIssues.filter {
            $0.ruleName == .largeViewHelper
        }
        #expect(helperIssues.count >= 1)
        if let issue = helperIssues.first {
            #expect(issue.message.contains("contentSection"))
        }
    }

    // MARK: - Body computed property with getter block (lines 56, 61-73)

    @Test("detects large body in getter block of computed property")
    func largeBodyInGetterBlock() throws {
        var bodyLines = ""
        for idx in 0..<25 {
            bodyLines += "                Text(\"Row \\(idx)\")\n"
        }
        let source = """
        struct GetterView: View {
            var body: some View {
                get {
                    VStack {
        \(bodyLines)
                    }
                }
            }
        }
        """

        let visitor = makeVisitor(source: source)
        let largeBodyIssues = visitor.detectedIssues.filter {
            $0.ruleName == .largeViewBody
        }
        // The getter block path should detect large view body
        #expect(largeBodyIssues.count >= 1)
    }

    // MARK: - MemberAccessExprSyntax tracking in view body (line 148)

    @Test("tracks self.stateVar member access in view body")
    func tracksSelfMemberAccessInBody() throws {
        let source = """
        struct TrackingView: View {
            @State private var label: String = "Hello"
            var body: some View {
                Text(self.label)
            }
        }
        """

        let visitor = makeVisitor(source: source)
        let labelInfo = visitor.stateVariables["label"]
        // self.label access should be tracked as used in view body
        #expect(labelInfo?.isUsedInViewBody == true)
    }

    // MARK: - CodeBlockSyntax statement counting in view body (lines 160-163)

    @Test("counts statements in code blocks within view body")
    func countsStatementsInCodeBlocks() throws {
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
    func noFlagOutsideViewBody() throws {
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
    func accessorBlockInViewBody() throws {
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
