import Testing
@testable import Core
@testable import SwiftProjectLintRules
import SwiftSyntax
import SwiftParser

@Suite
struct ViewBuilderComplexityVisitorTests {

    private func makeVisitor() -> ViewBuilderComplexityVisitor {
        let pattern = ViewBuilderComplexity().pattern
        return ViewBuilderComplexityVisitor(pattern: pattern)
    }

    private func runVisitor(_ visitor: ViewBuilderComplexityVisitor, source: String) {
        let sourceFile = Parser.parse(source: source)
        visitor.walk(sourceFile)
    }

    @Test
    func complexViewBuilderFunctionFlags() {
        // Generate a @ViewBuilder function with 35 lines
        var lines = [
            "import SwiftUI",
            "",
            "struct MyView: View {",
            "    @ViewBuilder",
            "    func content() -> some View {",
        ]
        for idx in 0..<32 {
            lines.append("        Text(\"Line \\(idx)\")")  // swiftlint:disable:this line_length
        }
        lines.append("    }")
        lines.append("}")
        let source = lines.joined(separator: "\n")

        let visitor = makeVisitor()
        runVisitor(visitor, source: source)

        #expect(visitor.detectedIssues.count == 1)
        #expect(visitor.detectedIssues.first?.ruleName == .viewBuilderComplexity)
    }

    @Test
    func manyStatementsViewBuilderFlags() {
        // 16 statements in a @ViewBuilder function
        var lines = [
            "import SwiftUI",
            "",
            "struct MyView: View {",
            "    @ViewBuilder",
            "    func content() -> some View {",
        ]
        for idx in 0..<16 {
            lines.append("        Text(\"Item \\(idx)\")")  // swiftlint:disable:this line_length
        }
        lines.append("    }")
        lines.append("}")
        let source = lines.joined(separator: "\n")

        let visitor = makeVisitor()
        runVisitor(visitor, source: source)

        #expect(visitor.detectedIssues.count == 1)
    }

    @Test
    func smallViewBuilderClean() {
        let source = """
        import SwiftUI

        struct MyView: View {
            @ViewBuilder
            func content() -> some View {
                Text("Hello")
                Text("World")
                Image(systemName: "star")
            }
        }
        """

        let visitor = makeVisitor()
        runVisitor(visitor, source: source)

        #expect(visitor.detectedIssues.isEmpty)
    }

    @Test
    func regularFunctionNotFlagged() {
        // A regular function (no @ViewBuilder) with many lines should not be flagged
        var lines = [
            "import SwiftUI",
            "",
            "struct MyView: View {",
            "    func doSomething() {",
        ]
        for idx in 0..<35 {
            lines.append("        print(\"Line \\(idx)\")")  // swiftlint:disable:this line_length
        }
        lines.append("    }")
        lines.append("}")
        let source = lines.joined(separator: "\n")

        let visitor = makeVisitor()
        runVisitor(visitor, source: source)

        #expect(visitor.detectedIssues.isEmpty)
    }

    @Test
    func viewBuilderComputedPropertyFlags() {
        var lines = [
            "import SwiftUI",
            "",
            "struct MyView: View {",
            "    @ViewBuilder",
            "    var header: some View {",
        ]
        for idx in 0..<32 {
            lines.append("        Text(\"Header \\(idx)\")")  // swiftlint:disable:this line_length
        }
        lines.append("    }")
        lines.append("}")
        let source = lines.joined(separator: "\n")

        let visitor = makeVisitor()
        runVisitor(visitor, source: source)

        #expect(visitor.detectedIssues.count == 1)
    }

    @Test
    func bodyPropertyNotFlagged() {
        // The standard body property should not be flagged even with @ViewBuilder
        var lines = [
            "import SwiftUI",
            "",
            "struct MyView: View {",
            "    @ViewBuilder",
            "    var body: some View {",
        ]
        for idx in 0..<32 {
            lines.append("        Text(\"Body \\(idx)\")")  // swiftlint:disable:this line_length
        }
        lines.append("    }")
        lines.append("}")
        let source = lines.joined(separator: "\n")

        let visitor = makeVisitor()
        runVisitor(visitor, source: source)

        #expect(visitor.detectedIssues.isEmpty)
    }
}
