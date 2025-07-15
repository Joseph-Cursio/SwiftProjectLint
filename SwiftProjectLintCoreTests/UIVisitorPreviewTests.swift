import Testing
import Foundation
import SwiftSyntax
import SwiftParser
@testable import SwiftProjectLintCore

@Suite("UIVisitorPreviewTests")
struct UIVisitorPreviewTests {
    
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
} 