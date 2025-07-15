import Testing
import Foundation
import SwiftParser
import SwiftSyntax
@testable import SwiftProjectLintCore

@Suite("ViewRelationshipAlertTests")
struct ViewRelationshipAlertTests {
    
    // MARK: - Debug Logging Helper
    
    @MainActor private func writeDebugLog(_ message: String, testName: String) {
        let logMessage = "[\(testName)] \(message)\n"
        
        // Try multiple locations that should be writable, prioritizing the debug subdirectory
        let debugDirectory = DebugLogger.debugDirectory()
        let possiblePaths = [
            debugDirectory + "/ViewRelationshipAlertTests_debug.log",
            NSTemporaryDirectory() + "ViewRelationshipAlertTests_debug.log",
            "/tmp/ViewRelationshipAlertTests_debug.log"
        ]
        
        for logPath in possiblePaths {
            if let data = logMessage.data(using: .utf8) {
                do {
                    if FileManager.default.fileExists(atPath: logPath) {
                        if let fileHandle = FileHandle(forWritingAtPath: logPath) {
                            fileHandle.seekToEndOfFile()
                            fileHandle.write(data)
                            fileHandle.closeFile()
                            return // Success
                        }
                    } else {
                        try data.write(to: URL(fileURLWithPath: logPath))
                        return // Success
                    }
                } catch {
                    // Continue to next path
                    continue
                }
            }
        }
        
        // Debug logging removed for production
    }
    
    private func logRelationships(_ relationships: [ViewRelationship], testName: String) {
        // Debug logging removed for production
    }

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

    @Test func testAlertDetection() async throws {
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
        logRelationships(relationships, testName: "testAlertDetection")
        
        #expect(relationships.count == 1)
        
        // Button is a system view, so it should NOT be detected as directChild
        // Only AlertView should be detected as alert
        let alertRelationship = relationships.first { $0.childView == "AlertView" && $0.relationshipType == .alert }
        #expect(alertRelationship != nil)
        #expect(alertRelationship?.parentView == "ContentView")
    }
    
    @Test func testSimpleAlertDetection() async throws {
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
        logRelationships(relationships, testName: "testSimpleAlertDetection")
        
        #expect(relationships.count == 1)
        
        // Text is a system view, so it should NOT be detected as directChild
        // Only AlertView should be detected as alert
        let alertRelationship = relationships.first { $0.childView == "AlertView" && $0.relationshipType == .alert }
        #expect(alertRelationship != nil)
    }
} 