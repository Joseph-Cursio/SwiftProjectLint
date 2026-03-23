import Testing
import Foundation
import SwiftParser
import SwiftSyntax
@testable import Core

struct ViewRelationshipBasicDetectionTests {

    // MARK: - Test Helper Methods

    private func extractRelationships(from sourceCode: String, parentView: String) -> [ViewRelationship] {
        let sourceFile = Parser.parse(source: sourceCode)
        
        let sourceLocationConverter = SourceLocationConverter(fileName: "test.swift", tree: sourceFile)
        let visitor = ViewRelationshipVisitor(
            parentView: parentView,
            filePath: "test.swift",
            sourceContents: sourceCode,
            sourceLocationConverter: sourceLocationConverter
        )
        visitor.walk(sourceFile)
        return visitor.relationships
    }

    // MARK: - Basic Detection Tests

    @Test func testVerySimpleDetection() throws {
        let sourceCode = """
        struct ContentView: View {
            var body: some View {
                Text("Hello")
            }
        }
        """
        
        let relationships = extractRelationships(from: sourceCode, parentView: "ContentView")
        
        // Text is a system view, so it should NOT be detected as a direct child
        #expect(relationships.isEmpty)
    }
    
    @Test func testBasicDetection() throws {
        let sourceCode = """
        struct ContentView: View {
            var body: some View {
                VStack {
                    Text("Hello")
                    Button("Click me") {
                        // action
                    }
                }
            }
        }
        """
        
        let relationships = extractRelationships(from: sourceCode, parentView: "ContentView")
        
        // Text and Button are system views, so they should NOT be detected as direct children
        #expect(relationships.isEmpty)
    }
    
    @Test func testDirectChildViewDetection() throws {
        let sourceCode = """
        struct ContentView: View {
            var body: some View {
                VStack {
                    RoundView()
                    Text("Hello")
                }
            }
        }
        """
        
        let relationships = extractRelationships(from: sourceCode, parentView: "ContentView")

        // Only RoundView (custom view) should be detected as direct child
        // Text is a system view and should be ignored
        #expect(relationships.count == 1, "Expected 1 relationship, got \(relationships.count)")
        #expect(relationships[0].childView == "RoundView")
        #expect(relationships[0].relationshipType == .directChild)
        #expect(relationships[0].parentView == "ContentView")
    }
    
    @Test func testLineNumberCalculation() throws {
        let sourceCode = """
        struct ContentView: View {
            var body: some View {
                CustomView("Hello")
            }
        }
        """
        
        let relationships = extractRelationships(from: sourceCode, parentView: "ContentView")
        
        #expect(relationships.count == 1)
        #expect(relationships[0].lineNumber == 3) // CustomView("Hello") is on line 3
    }
} 
