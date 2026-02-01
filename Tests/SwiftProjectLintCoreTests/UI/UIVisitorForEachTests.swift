import Testing
import Foundation
import SwiftSyntax
import SwiftParser
@testable import SwiftProjectLintCore

@Suite("UIVisitorForEachTests")
struct UIVisitorForEachTests {
    
    @Test func testDetectsForEachWithoutID() throws {
        let visitor = UIVisitor(patternCategory: PatternCategory.uiPatterns)
        visitor.setFilePath("test.swift")
        visitor.reset()
        
        let source = """
        struct ContentView: View {
            let items = ["A", "B", "C"]
            
            var body: some View {
                ForEach(items) { item in
                    Text(item)
                }
            }
        }
        """
        
        let syntax = Parser.parse(source: source)
        visitor.walk(syntax)
        let issues = visitor.detectedIssues
        
        // Should detect ForEach without ID (preview detection skipped for test files)
        #expect(issues.count == 1)
        
        let messages = issues.map { $0.message }
        #expect(messages.contains("ForEach without explicit ID can cause performance issues"))
        
        // Check that the ForEach issue has the correct severity
        if let forEachIssue = issues.first(where: { $0.message.contains("ForEach without explicit ID") }) {
            #expect(forEachIssue.severity == .warning)
        }
    }
    
    @Test func testDoesNotDetectForEachWithExplicitID() throws {
        let visitor = UIVisitor(patternCategory: PatternCategory.uiPatterns)
        visitor.setFilePath("test.swift")
        visitor.reset()
        
        let source = """
        struct ContentView: View {
            let items = [Item(id: "1"), Item(id: "2")]
            
            var body: some View {
                ForEach(items, id: \\.id) { item in
                    Text(item.id)
                }
            }
        }
        
        struct Item {
            let id: String
        }
        """
        
        let syntax = Parser.parse(source: source)
        visitor.walk(syntax)
        let issues = visitor.detectedIssues
        
        // Should not detect any issues (preview detection skipped for test files)
        #expect(issues.isEmpty)
    }
} 
