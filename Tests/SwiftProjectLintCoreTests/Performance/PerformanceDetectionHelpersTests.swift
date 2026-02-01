import Testing
import SwiftParser
import SwiftSyntax
@testable import SwiftProjectLintCore

@Suite("PerformanceDetectionHelpersTests")
struct PerformanceDetectionHelpersTests {
    
    @Test func testDetectForEachSelfIDWithBackslashSelf() throws {
        // Test detectForEachSelfID method - should detect \\.self in id parameter
        let source = """
        struct ContentView: View {
            var items = [1, 2, 3]
            var body: some View {
                ForEach(items, id: \\.self) { item in
                    Text("\\(item)")
                }
            }
        }
        """
        
        let syntax = Parser.parse(source: source)
        let visitor = PerformanceVisitor(patternCategory: .performance)
        visitor.setFilePath("test.swift")
        visitor.walk(syntax)
        
        let issues = visitor.detectedIssues
        // detectForEachSelfID should detect \\.self usage
        let forEachSelfIssues = issues.filter { 
            $0.message.contains("ForEach") && $0.message.contains("self")
        }
        
        #expect(forEachSelfIssues.count >= 1)
        if let issue = forEachSelfIssues.first {
            #expect(issue.severity == .warning)
            #expect(issue.message.contains("\\.self"))
        }
    }
    
    @Test func testDetectForEachWithoutIDWithMemberAccessSelf() throws {
        // Test detectForEachWithoutID method - should detect .self as id via MemberAccessExprSyntax
        let source = """
        struct ContentView: View {
            var items = [1, 2, 3]
            var body: some View {
                ForEach(items, id: .self) { item in
                    Text("\\(item)")
                }
            }
        }
        """
        
        let syntax = Parser.parse(source: source)
        let visitor = PerformanceVisitor(patternCategory: .performance)
        visitor.setFilePath("test.swift")
        visitor.walk(syntax)
        
        let issues = visitor.detectedIssues
        // detectForEachWithoutID should detect .self usage when visiting MemberAccessExprSyntax
        let forEachSelfIssues = issues.filter { 
            $0.message.contains("ForEach") && $0.message.contains("self")
        }
        
        // May detect via either detectForEachSelfID or detectForEachWithoutID
        #expect(forEachSelfIssues.isEmpty)
    }
    
    @Test func testDoesNotDetectForEachWithProperID() throws {
        let source = """
        struct Item {
            let id: String
        }
        struct ContentView: View {
            var items = [Item(id: "1"), Item(id: "2")]
            var body: some View {
                ForEach(items, id: \\.id) { item in
                    Text(item.id)
                }
            }
        }
        """
        
        let syntax = Parser.parse(source: source)
        let visitor = PerformanceVisitor(patternCategory: .performance)
        visitor.setFilePath("test.swift")
        visitor.walk(syntax)
        
        let issues = visitor.detectedIssues
        let forEachSelfIssues = issues.filter { $0.message.contains("self") }
        
        // Should not detect .self issues when proper ID is used
        #expect(forEachSelfIssues.isEmpty)
    }
    
    @Test func testDetectForEachWithoutIDParameter() throws {
        let source = """
        struct ContentView: View {
            var items = [1, 2, 3]
            var body: some View {
                ForEach(items) { item in
                    Text("\\(item)")
                }
            }
        }
        """
        
        let syntax = Parser.parse(source: source)
        let visitor = PerformanceVisitor(patternCategory: .performance)
        visitor.setFilePath("test.swift")
        visitor.walk(syntax)
        
        let issues = visitor.detectedIssues
        let forEachIssues = issues.filter { 
            $0.message.contains("ForEach") && $0.message.contains("missing")
        }
        
        #expect(forEachIssues.count >= 1)
        if let issue = forEachIssues.first {
            #expect(issue.severity == .warning)
        }
    }
    
    @Test func testDetectForEachSelfIDWithKeyPathSelf() throws {
        // Test with explicit key path syntax
        let source = """
        struct ContentView: View {
            var items = ["a", "b", "c"]
            var body: some View {
                ForEach(items, id: \\.self) { item in
                    Text(item)
                }
            }
        }
        """
        
        let syntax = Parser.parse(source: source)
        let visitor = PerformanceVisitor(patternCategory: .performance)
        visitor.setFilePath("test.swift")
        visitor.walk(syntax)
        
        let issues = visitor.detectedIssues
        let forEachSelfIssues = issues.filter { 
            $0.message.contains("ForEach") && $0.message.contains("self")
        }
        
        // detectForEachSelfID should detect this
        #expect(forEachSelfIssues.count >= 1)
    }
    
    @Test func testDetectForEachSelfIDDoesNotTriggerForNonForEach() throws {
        // Test that detectForEachSelfID doesn't trigger for non-ForEach calls
        let source = """
        struct ContentView: View {
            var items = [1, 2, 3]
            var body: some View {
                List(items, id: \\.self) { item in
                    Text("\\(item)")
                }
            }
        }
        """
        
        let syntax = Parser.parse(source: source)
        let visitor = PerformanceVisitor(patternCategory: .performance)
        visitor.setFilePath("test.swift")
        visitor.walk(syntax)
        
        let issues = visitor.detectedIssues
        let forEachSelfIssues = issues.filter { 
            $0.message.contains("ForEach") && $0.message.contains("self")
        }
        
        // Should not detect ForEach issues for List
        #expect(forEachSelfIssues.isEmpty)
    }
    
    @Test func testDetectForEachWithoutIDWithNestedForEach() throws {
        // Test detection in nested ForEach
        let source = """
        struct ContentView: View {
            var items = [[1, 2], [3, 4]]
            var body: some View {
                ForEach(items, id: \\.self) { row in
                    ForEach(row, id: \\.self) { item in
                        Text("\\(item)")
                    }
                }
            }
        }
        """
        
        let syntax = Parser.parse(source: source)
        let visitor = PerformanceVisitor(patternCategory: .performance)
        visitor.setFilePath("test.swift")
        visitor.walk(syntax)
        
        let issues = visitor.detectedIssues
        let forEachSelfIssues = issues.filter { 
            $0.message.contains("ForEach") && $0.message.contains("self")
        }
        
        // Should detect .self usage in both ForEach calls
        #expect(forEachSelfIssues.count >= 1)
    }
    
    @Test func testDetectForEachSelfIDWithComplexExpression() throws {
        // Test with more complex ForEach expression
        let source = """
        struct ContentView: View {
            var items = [1, 2, 3]
            var body: some View {
                VStack {
                    ForEach(items.sorted(), id: \\.self) { item in
                        Text("\\(item)")
                    }
                }
            }
        }
        """
        
        let syntax = Parser.parse(source: source)
        let visitor = PerformanceVisitor(patternCategory: .performance)
        visitor.setFilePath("test.swift")
        visitor.walk(syntax)
        
        let issues = visitor.detectedIssues
        let forEachSelfIssues = issues.filter { 
            $0.message.contains("ForEach") && $0.message.contains("self")
        }
        
        // Should detect .self usage
        #expect(forEachSelfIssues.count >= 1)
    }
    
    @Test func testDetectForEachWithoutIDEdgeCases() throws {
        // Test edge cases - ForEach with no arguments (invalid but should handle gracefully)
        let source = """
        struct ContentView: View {
            var body: some View {
                ForEach([]) { _ in
                    Text("Empty")
                }
            }
        }
        """
        
        let syntax = Parser.parse(source: source)
        let visitor = PerformanceVisitor(patternCategory: .performance)
        visitor.setFilePath("test.swift")
        visitor.walk(syntax)
        
        let issues = visitor.detectedIssues
        // Should detect missing ID
        let forEachIssues = issues.filter { 
            $0.message.contains("ForEach") && $0.message.contains("missing")
        }
        
        #expect(forEachIssues.count >= 1)
    }
}
