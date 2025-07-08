import Testing
import Foundation
import SwiftSyntax
import SwiftParser
@testable import SwiftProjectLintCore

struct UIVisitorTests {
    
    // MARK: - Navigation Tests
    
    @Test func testDetectsNestedNavigationView() async throws {
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
    
    @Test func testDoesNotDetectSingleNavigationView() async throws {
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
        #expect(issues.count == 0)
    }
    
    @Test func testDetectsModernNavigationAlternatives() async throws {
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
        #expect(issues.count == 0)
    }
    
    // MARK: - Preview Tests
    
    @Test func testDetectsMissingPreview() async throws {
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
        
        #expect(issues.count == 1)
        #expect(issues.first?.message == "View 'ContentView' missing preview provider")
        #expect(issues.first?.severity == .info)
    }
    
    @Test func testDoesNotDetectWhenPreviewExists() async throws {
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
        #expect(issues.count == 0)
    }
    
    @Test func testDetectsPreviewStruct() async throws {
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
        #expect(issues.count == 0)
    }
    
    // MARK: - Styling Tests
    
    @Test func testDetectsInconsistentTextStyling() async throws {
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
    
    @Test func testDoesNotDetectSingleStylingModifier() async throws {
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
        #expect(issues.count == 0)
    }
    
    // MARK: - ForEach Tests
    
    @Test func testDetectsForEachWithoutID() async throws {
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
    
    @Test func testDoesNotDetectForEachWithExplicitID() async throws {
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
        #expect(issues.count == 0)
    }
    
    // MARK: - Error Handling Tests
    
    @Test func testDetectsBasicErrorHandling() async throws {
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
    
    @Test func testDoesNotDetectProperErrorHandling() async throws {
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
        #expect(issues.count == 0)
    }
    
    // MARK: - Complex Scenario Tests
    
    @Test func testComplexViewWithMultipleIssues() async throws {
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
    
    @Test func testResetClearsState() async throws {
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
        
        #expect(visitor.detectedIssues.count == 0)
    }
} 

