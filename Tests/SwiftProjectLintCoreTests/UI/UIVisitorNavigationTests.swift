import Testing
import Foundation
import SwiftSyntax
import SwiftParser
@testable import SwiftProjectLintCore

@Suite("UIVisitorNavigationTests")
struct UIVisitorNavigationTests {
    
    @Test func testDetectsNestedNavigationView() throws {
        let visitor = UIVisitor(patternCategory: PatternCategory.uiPatterns)
        visitor.setFilePath("test.swift")
        visitor.reset()
        
        let source = """
        struct ContentView: View {
            var body: some View {
                NavigationView {
                    VStack {
                        NavigationView {
                            Text("Nested Navigation")
                        }
                    }
                }
            }
        }
        """
        
        print("🔍 Testing nested navigation detection...")
        let syntax = Parser.parse(source: source)
        visitor.walk(syntax)
        let issues = visitor.detectedIssues
        
        print("🔍 Detected issues: \(issues.count)")
        for (index, issue) in issues.enumerated() {
            print("  Issue \(index + 1): \(String(describing: issue.message))")
        }
        
        // Should detect nested NavigationView (preview detection skipped for test files)
        #expect(issues.count == 1, "Expected 1 issue, but got \(issues.count)")
        
        let messages = issues.map { $0.message }
        #expect(messages.contains("Nested NavigationView detected, this can cause issues"))
        
        // Check that the nested navigation issue has the correct severity
        if let nestedIssue = issues.first(where: { $0.message.contains("Nested NavigationView") }) {
            #expect(nestedIssue.severity == .warning)
        }
    }
    
    @Test func testDoesNotDetectSingleNavigationView() throws {
        let visitor = UIVisitor(patternCategory: PatternCategory.uiPatterns)
        visitor.setFilePath("test.swift")
        visitor.reset()
        
        let source = """
        struct ContentView: View {
            var body: some View {
                NavigationView {
                    Text("Single Navigation")
                }
            }
        }
        """
        
        let syntax = Parser.parse(source: source)
        visitor.walk(syntax)
        let issues = visitor.detectedIssues
        
        // Should not detect any issues (preview detection skipped for test files)
        #expect(issues.isEmpty)
    }
    
    @Test func testDetectsModernNavigationAlternatives() throws {
        let visitor = UIVisitor(patternCategory: PatternCategory.uiPatterns)
        visitor.setFilePath("test.swift")
        visitor.reset()
        
        let source = """
        struct ContentView: View {
            var body: some View {
                NavigationStack {
                    Text("Modern Navigation")
                }
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
