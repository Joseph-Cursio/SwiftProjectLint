import Testing
import Foundation
import SwiftParser
import SwiftSyntax
@testable import SwiftProjectLintCore

struct ViewRelationshipAlertTests {

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

    // MARK: - Alert Tests

    @Test func testAlertDetection() throws {
        let sourceCode = """
        struct ContentView: View {
            @State private var showingAlert = false
            
            var body: some View {
                Button("Show Alert") {
                    showingAlert = true
                }
                .alert("Title", isPresented: $showingAlert) {
                    AlertView()
                }
            }
        }
        """
        
        let relationships = extractRelationships(from: sourceCode, parentView: "ContentView")

        #expect(relationships.count == 1)
        
        // Button is a system view, so it should NOT be detected as directChild
        // Only AlertView should be detected as alert
        let alertRelationship = relationships.first { $0.childView == "AlertView" && $0.relationshipType == .alert }
        #expect(alertRelationship != nil)
        #expect(alertRelationship?.parentView == "ContentView")
    }
    
    @Test func testSimpleAlertDetection() throws {
        let sourceCode = """
        struct ContentView: View {
            @State private var showingAlert = false
            
            var body: some View {
                Text("Hello")
                .alert("Title", isPresented: $showingAlert) {
                    AlertView()
                }
            }
        }
        """
        
        let relationships = extractRelationships(from: sourceCode, parentView: "ContentView")

        #expect(relationships.count == 1)
        
        // Text is a system view, so it should NOT be detected as directChild
        // Only AlertView should be detected as alert
        let alertRelationship = relationships.first { $0.childView == "AlertView" && $0.relationshipType == .alert }
        #expect(alertRelationship != nil)
    }
} 
