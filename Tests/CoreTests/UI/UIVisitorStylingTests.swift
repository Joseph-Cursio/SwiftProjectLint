@testable import Core
import Foundation
import SwiftParser
@testable import SwiftProjectLintRules
import SwiftSyntax
import Testing

struct UIVisitorStylingTests {

    @Test func testDetectsInconsistentTextStyling() {
        let visitor = UIVisitor(patternCategory: PatternCategory.uiPatterns)
        visitor.setFilePath("Tests/SourceFile.swift")
        visitor.reset()

        let source = """
        struct ContentView: View {
            var body: some View {
                Text("Hello World")
                    .font(.title)
                    .foregroundColor(.blue)
                    .bold()
                    .shadow(radius: 2)
            }
        }
        """

        let syntax = Parser.parse(source: source)
        visitor.walk(syntax)
        let issues = visitor.detectedIssues

        // Should detect inconsistent styling with 4 styling modifiers
        #expect(issues.count == 1)

        let messages = issues.map { $0.message }
        #expect(messages.contains("Consider using consistent text styling"))

        // Check that the styling issue has the correct severity
        if let stylingIssue = issues.first(where: { $0.message.contains("consistent text styling") }) {
            #expect(stylingIssue.severity == .info)
        }
    }

    @Test func testDoesNotDetectTwoOrThreeStylingModifiers() {
        let visitor = UIVisitor(patternCategory: PatternCategory.uiPatterns)
        visitor.setFilePath("Tests/SourceFile.swift")
        visitor.reset()

        let source = """
        struct ContentView: View {
            var body: some View {
                Text("Hello World")
                    .font(.title)
                    .foregroundColor(.blue)
                    .bold()
            }
        }
        """

        let syntax = Parser.parse(source: source)
        visitor.walk(syntax)
        let issues = visitor.detectedIssues

        // 3 styling modifiers should not trigger — threshold is 4
        #expect(issues.isEmpty)
    }

    @Test func testDoesNotDetectSingleStylingModifier() {
        let visitor = UIVisitor(patternCategory: PatternCategory.uiPatterns)
        visitor.setFilePath("Tests/SourceFile.swift")
        visitor.reset()

        let source = """
        struct ContentView: View {
            var body: some View {
                Text("Hello World")
                    .font(.title)
            }
        }
        """

        let syntax = Parser.parse(source: source)
        visitor.walk(syntax)
        let issues = visitor.detectedIssues

        // Should not detect any issues (preview detection skipped for test files)
        #expect(issues.isEmpty)
    }
}
