import Testing
import Foundation
import SwiftSyntax
import SwiftParser
@testable import SwiftProjectLintCore

@Suite("UIVisitorStylingTests")
struct UIVisitorStylingTests {
    
    @Test func testDetectsInconsistentTextStyling() throws {
        let visitor = UIVisitor(patternCategory: PatternCategory.uiPatterns)
        visitor.setFilePath("test.swift")
        visitor.reset()
        
        let source = """
        struct ContentView: View {
            var body: some View {
                Text("Hello World")
                    .font(.title)
                    .foregroundColor(.blue)
            }
        }
        """
        
        let syntax = Parser.parse(source: source)
        visitor.walk(syntax)
        let issues = visitor.detectedIssues
        
        // Should detect inconsistent styling (preview detection skipped for test files)
        #expect(issues.count == 1)
        
        let messages = issues.map { $0.message }
        #expect(messages.contains("Consider using consistent text styling"))
        
        // Check that the styling issue has the correct severity
        if let stylingIssue = issues.first(where: { $0.message.contains("consistent text styling") }) {
            #expect(stylingIssue.severity == .info)
        }
    }
    
    @Test func testDoesNotDetectSingleStylingModifier() throws {
        let visitor = UIVisitor(patternCategory: PatternCategory.uiPatterns)
        visitor.setFilePath("test.swift")
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
