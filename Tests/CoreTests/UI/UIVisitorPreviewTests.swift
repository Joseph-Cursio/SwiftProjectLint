import Testing
import Foundation
import SwiftSyntax
import SwiftParser
@testable import Core

struct UIVisitorPreviewTests {
    
    @Test func testDetectsMissingPreview() throws {
        let visitor = UIVisitor(patternCategory: PatternCategory.uiPatterns)
        visitor.setFilePath("test.swift")
        visitor.reset()
        
        let source = """
        struct ContentView: View {
            var body: some View {
                Text("Hello World")
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
    
    // swiftprojectlint:disable Test Missing Require
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
    
    // swiftprojectlint:disable Test Missing Require
    @Test func testSubcomponentViewsNotFlaggedForMissingPreview() throws {
        let visitor = UIVisitor(patternCategory: PatternCategory.uiPatterns)
        visitor.setFilePath("HealthScoreBadge.swift")
        visitor.reset()

        let source = """
        struct HealthScoreBadge: View {
            var body: some View { Text("A") }
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

        // Only the primary view (HealthScoreBadge) should be flagged, not subcomponents
        #expect(previewIssues.count == 1)
        #expect(previewIssues.first?.message.contains("HealthScoreBadge") == true)
    }

    // swiftprojectlint:disable Test Missing Require
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
} 
