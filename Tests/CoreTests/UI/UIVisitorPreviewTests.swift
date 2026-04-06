import Testing
import Foundation
import SwiftSyntax
import SwiftParser
@testable import Core
@testable import SwiftProjectLintRules

struct UIVisitorPreviewTests {

    @Test func testDetectsMissingPreview() throws {
        let visitor = UIVisitor(patternCategory: PatternCategory.uiPatterns)
        visitor.setFilePath("test.swift")
        visitor.reset()

        // Body needs 3+ statements to trigger (trivial views are suppressed)
        let source = """
        struct ContentView: View {
            var body: some View {
                VStack {
                    Text("Hello World")
                    Text("Subtitle")
                }
                .padding()
                .background(Color.white)
            }
        }
        """

        // Set a non-test file path to enable missing preview detection
        visitor.setFilePath("ContentView.swift")

        let syntax = Parser.parse(source: source)
        visitor.walk(syntax)
        let issues = visitor.detectedIssues

        let issue = try #require(issues.first)
        #expect(issue.message == "View 'ContentView' missing preview provider")
        #expect(issue.severity == .info)
    }

    @Test func testDoesNotDetectWhenPreviewExists() throws {
        let visitor = UIVisitor(patternCategory: PatternCategory.uiPatterns)
        visitor.setFilePath("test.swift")
        visitor.reset()

        let source = """
        struct ContentView: View {
            var body: some View {
                Text("Hello World")
            }
        }

        #Preview {
            ContentView()
        }
        """

        let syntax = Parser.parse(source: source)
        visitor.walk(syntax)
        let issues = visitor.detectedIssues

        // Should not detect any issues when preview exists
        #expect(issues.isEmpty)
    }

    @Test func testSubcomponentViewsNotFlaggedForMissingPreview() throws {
        let visitor = UIVisitor(patternCategory: PatternCategory.uiPatterns)
        visitor.setFilePath("HealthScoreBadge.swift")
        visitor.reset()

        // Primary view has 3+ body lines; subcomponents are trivial
        let source = """
        struct HealthScoreBadge: View {
            var body: some View {
                VStack {
                    Text("Score")
                    HealthScoreRing()
                    HealthScoreIndicator()
                }
                .padding()
            }
        }

        struct HealthScoreRing: View {
            var body: some View { Text("Ring") }
        }

        struct HealthScoreIndicator: View {
            var body: some View { Text("Indicator") }
        }
        """

        let syntax = Parser.parse(source: source)
        visitor.walk(syntax)
        let previewIssues = visitor.detectedIssues.filter { $0.ruleName == .missingPreview }

        // Only the primary view (HealthScoreBadge) should be flagged
        #expect(previewIssues.count == 1)
        #expect(previewIssues.first?.message.contains("HealthScoreBadge") == true)
    }

    @Test func testDetectsPreviewStruct() throws {
        let visitor = UIVisitor(patternCategory: PatternCategory.uiPatterns)
        visitor.setFilePath("test.swift")
        visitor.reset()

        let source = """
        struct ContentView: View {
            var body: some View {
                Text("Hello World")
            }
        }

        struct ContentView_Previews: PreviewProvider {
            static var previews: some View {
                ContentView()
            }
        }
        """

        let syntax = Parser.parse(source: source)
        visitor.walk(syntax)
        let issues = visitor.detectedIssues

        // Should not detect any issues when preview struct exists
        #expect(issues.isEmpty)
    }

    // MARK: - Tiered severity

    @Test func testPublicViewGetsWarningSeverity() throws {
        let visitor = UIVisitor(patternCategory: PatternCategory.uiPatterns)
        visitor.setFilePath("PublicView.swift")
        visitor.reset()

        let source = """
        public struct PublicView: View {
            public var body: some View {
                VStack {
                    Text("Hello")
                    Text("World")
                    Text("Public")
                }
            }
        }
        """

        let syntax = Parser.parse(source: source)
        visitor.walk(syntax)
        let previewIssues = visitor.detectedIssues.filter { $0.ruleName == .missingPreview }
        #expect(previewIssues.count == 1)
        #expect(previewIssues.first?.severity == .warning)
    }

    // MARK: - Suppression

    @Test func testPrivateViewSuppressed() {
        let visitor = UIVisitor(patternCategory: PatternCategory.uiPatterns)
        visitor.setFilePath("MyView.swift")
        visitor.reset()

        let source = """
        private struct HelperView: View {
            var body: some View {
                VStack {
                    Text("A")
                    Text("B")
                    Text("C")
                }
            }
        }
        """

        let syntax = Parser.parse(source: source)
        visitor.walk(syntax)
        let previewIssues = visitor.detectedIssues.filter { $0.ruleName == .missingPreview }
        #expect(previewIssues.isEmpty)
    }

    @Test func testTrivialViewSuppressed() {
        let visitor = UIVisitor(patternCategory: PatternCategory.uiPatterns)
        visitor.setFilePath("Simple.swift")
        visitor.reset()

        let source = """
        struct SimpleWrapper: View {
            var body: some View {
                Text("Hello")
            }
        }
        """

        let syntax = Parser.parse(source: source)
        visitor.walk(syntax)
        let previewIssues = visitor.detectedIssues.filter { $0.ruleName == .missingPreview }
        #expect(previewIssues.isEmpty)
    }
}
