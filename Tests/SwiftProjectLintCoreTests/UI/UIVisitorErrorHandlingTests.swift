import Testing
import Foundation
import SwiftSyntax
import SwiftParser
@testable import SwiftProjectLintCore

@Suite("UIVisitorErrorHandlingTests")
struct UIVisitorErrorHandlingTests {
    
    @Test func testDetectsBasicErrorHandling() throws {
        let visitor = UIVisitor(patternCategory: PatternCategory.uiPatterns)
        visitor.setFilePath("test.swift")
        visitor.reset()
        
        let source = """
        struct ContentView: View {
            @State var error: String?
            
            var body: some View {
                if let error = error {
                    Text("Error: \\(error)")
                } else {
                    Text("Success")
                }
            }
        }
        """
        
        let syntax = Parser.parse(source: source)
        visitor.walk(syntax)
        let issues = visitor.detectedIssues
        
        // Should detect basic error handling (preview detection skipped for test files)
        #expect(issues.count == 1)
        
        let messages = issues.map { $0.message }
        #expect(messages.contains("Consider using proper error handling UI patterns"))
        
        // Check that the error handling issue has the correct severity
        if let errorIssue = issues.first(where: { $0.message.contains("proper error handling") }) {
            #expect(errorIssue.severity == .info)
        }
    }
    
    @Test func testDoesNotDetectProperErrorHandling() throws {
        let visitor = UIVisitor(patternCategory: PatternCategory.uiPatterns)
        visitor.setFilePath("test.swift")
        visitor.reset()
        
        let source = """
        struct ContentView: View {
            @State var error: String?
            @State var showAlert = false
            
            var body: some View {
                Text("Content")
                    .alert("Error", isPresented: $showAlert) {
                        Button("OK") { }
                    } message: {
                        if let error = error {
                            Text(error)
                        }
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
    
    @Test func testComplexViewWithMultipleIssues() throws {
        let visitor = UIVisitor(patternCategory: PatternCategory.uiPatterns)
        visitor.setFilePath("test.swift")
        visitor.reset()
        
        let source = """
        struct ComplexView: View {
            @State var error: String?
            let items = ["A", "B", "C"]
            
            var body: some View {
                NavigationView {
                    VStack {
                        NavigationView {
                            ForEach(items, id: \\.self) { item in
                                Text(item)
                                    .font(.title)
                                    .foregroundColor(.blue)
                            }
                        }
                        
                        if let error = error {
                            Text("Error: \\(error)")
                        }
                    }
                }
            }
        }
        """
        
        let syntax = Parser.parse(source: source)
        visitor.walk(syntax)
        let issues = visitor.detectedIssues
        
        // Should detect:
        // 1. Nested NavigationView
        // 2. Inconsistent text styling
        // 3. Basic error handling
        // (ForEach has explicit ID: \\.self, so it should NOT be detected)
        // (Preview detection skipped for test files)
        #expect(issues.count == 3)
        
        let messages = issues.map { $0.message }
        #expect(messages.contains("Nested NavigationView detected, this can cause issues"))
        #expect(messages.contains("Consider using consistent text styling"))
        #expect(messages.contains("Consider using proper error handling UI patterns"))
    }
    
    @Test func testResetClearsState() throws {
        let visitor = UIVisitor(patternCategory: PatternCategory.uiPatterns)
        visitor.setFilePath("test.swift")
        visitor.reset()
        
        let source = """
        struct TestView: View {
            var body: some View {
                NavigationView {
                    NavigationView {
                        Text("Nested")
                    }
                }
            }
        }
        """
        
        let syntax = Parser.parse(source: source)
        visitor.walk(syntax)
        
        // Should detect nested NavigationView (preview detection skipped for test files)
        #expect(visitor.detectedIssues.count == 1)
        
        visitor.reset()
        
        #expect(visitor.detectedIssues.isEmpty)
    }
} 