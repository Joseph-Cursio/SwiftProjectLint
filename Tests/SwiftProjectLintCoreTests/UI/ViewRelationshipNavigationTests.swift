import Testing
import Foundation
import SwiftParser
import SwiftSyntax
@testable import SwiftProjectLintCore

@Suite("ViewRelationshipNavigationTests")
struct ViewRelationshipNavigationTests {
    
    // MARK: - Debug Logging Helper
    
    @MainActor private func writeDebugLog(_ message: String, testName: String) {
        let logMessage = "[\(testName)] \(message)\n"
        
        // Try multiple locations that should be writable, prioritizing the debug subdirectory
        let debugDirectory = DebugLogger.debugDirectory()
        let possiblePaths = [
            debugDirectory + "/ViewRelationshipNavigationTests_debug.log",
            NSTemporaryDirectory() + "ViewRelationshipNavigationTests_debug.log",
            "/tmp/ViewRelationshipNavigationTests_debug.log"
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

    // MARK: - Navigation & Presentation Tests

    @Test func testNavigationLinkDetection() throws {
        let sourceCode = """
        struct ContentView: View {
            var body: some View {
                NavigationLink(destination: DetailView()) {
                    Text("Go to Detail")
                }
            }
        }
        """
        
        let relationships = extractRelationships(from: sourceCode, parentView: "ContentView")
        logRelationships(relationships, testName: "testNavigationLinkDetection")
        
        #expect(relationships.count == 1)
        #expect(relationships[0].childView == "DetailView")
        #expect(relationships[0].relationshipType == .navigationDestination)
        #expect(relationships[0].parentView == "ContentView")
    }
    
    @Test func testSheetPresentationDetection() throws {
        let sourceCode = """
        struct ContentView: View {
            @State private var showingSheet = false
            
            var body: some View {
                Button("Show Sheet") {
                    showingSheet = true
                }
                .sheet(isPresented: $showingSheet) {
                    SheetView()
                }
            }
        }
        """
        
        let relationships = extractRelationships(from: sourceCode, parentView: "ContentView")
        logRelationships(relationships, testName: "testSheetPresentationDetection")
        
        #expect(relationships.count == 1)
        #expect(relationships[0].childView == "SheetView")
        #expect(relationships[0].relationshipType == .sheet)
        #expect(relationships[0].parentView == "ContentView")
    }
    
    @Test func testFullScreenCoverDetection() throws {
        let sourceCode = """
        struct ContentView: View {
            @State private var showingFullScreen = false
            
            var body: some View {
                Button("Show Full Screen") {
                    showingFullScreen = true
                }
                .fullScreenCover(isPresented: $showingFullScreen) {
                    FullScreenView()
                }
            }
        }
        """
        
        let relationships = extractRelationships(from: sourceCode, parentView: "ContentView")
        logRelationships(relationships, testName: "testFullScreenCoverDetection")
        
        #expect(relationships.count == 1)
        #expect(relationships[0].childView == "FullScreenView")
        #expect(relationships[0].relationshipType == .fullScreenCover)
        #expect(relationships[0].parentView == "ContentView")
    }
    
    @Test func testPopoverDetection() throws {
        let sourceCode = """
        struct ContentView: View {
            @State private var showingPopover = false
            
            var body: some View {
                Button("Show Popover") {
                    showingPopover = true
                }
                .popover(isPresented: $showingPopover) {
                    PopoverView()
                }
            }
        }
        """
        
        let relationships = extractRelationships(from: sourceCode, parentView: "ContentView")
        logRelationships(relationships, testName: "testPopoverDetection")
        
        #expect(relationships.count == 1)
        #expect(relationships[0].childView == "PopoverView")
        #expect(relationships[0].relationshipType == .popover)
        #expect(relationships[0].parentView == "ContentView")
    }
    
    @Test func testMultipleRelationships() throws {
        let sourceCode = """
        struct ContentView: View {
            @State private var showingSheet = false
            
            var body: some View {
                VStack {
                    RoundView()
                    NavigationLink(destination: DetailView()) {
                        Text("Go to Detail")
                    }
                    Button("Show Sheet") {
                        showingSheet = true
                    }
                }
                .sheet(isPresented: $showingSheet) {
                    SheetView()
                }
            }
        }
        """
        
        let relationships = extractRelationships(from: sourceCode, parentView: "ContentView")
        logRelationships(relationships, testName: "testMultipleRelationships")
        
        // Debug output removed for production
        
        #expect(relationships.count == 3, "Expected 3 relationships, got \(relationships.count)")
        
        let directChild = relationships.first { $0.relationshipType == .directChild }
        let navigation = relationships.first { $0.relationshipType == .navigationDestination }
        let sheet = relationships.first { $0.relationshipType == .sheet }
        
        #expect(directChild != nil, "Expected directChild relationship")
        #expect(directChild?.childView == "RoundView", "Expected RoundView as directChild")
        #expect(navigation != nil, "Expected navigationDestination relationship")
        #expect(navigation?.childView == "DetailView", "Expected DetailView as navigationDestination")
        #expect(sheet != nil, "Expected sheet relationship")
        #expect(sheet?.childView == "SheetView", "Expected SheetView as sheet")
    }
    
    @Test func testSimpleSheetDebug() throws {
        let sourceCode = """
        struct ContentView: View {
            var body: some View {
                VStack {
                    RoundView()
                }
                .sheet(isPresented: .constant(true)) {
                    SheetView()
                }
            }
        }
        """
        
        let relationships = extractRelationships(from: sourceCode, parentView: "ContentView")
        
        // Debug output removed for production
        
        // Don't assert anything, just see what we get
        #expect(true)
    }
} 