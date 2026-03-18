import Testing
import Foundation
import SwiftParser
import SwiftSyntax
@testable import SwiftProjectLintCore

struct ViewRelationshipBasicDetectionTests {
    
    // MARK: - Debug Logging Helper
    
    @MainActor private func writeDebugLog(_ message: String, testName: String) {
        let logMessage = "[\(testName)] \(message)\n"
        
        // Try multiple locations that should be writable, prioritizing the debug subdirectory
        let debugDirectory = DebugLogger.debugDirectory()
        let possiblePaths = [
            debugDirectory + "/ViewRelationshipBasicDetectionTests_debug.log",
            NSTemporaryDirectory() + "ViewRelationshipBasicDetectionTests_debug.log",
            "/tmp/ViewRelationshipBasicDetectionTests_debug.log"
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
        logRelationships(relationships, testName: "testDirectChildViewDetection")
        
        // Debug output removed for production
        
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
