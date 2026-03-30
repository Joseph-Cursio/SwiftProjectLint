import Testing
import Foundation
import SwiftParser
import SwiftSyntax
@testable import Core
@testable import SwiftProjectLintRules

struct ViewRelationshipNavigationTests {
    
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
        #expect(relationships.count == 1)
        let relationship = try #require(relationships.first)
        #expect(relationship.childView == "DetailView")
        #expect(relationship.relationshipType == .navigationDestination)
        #expect(relationship.parentView == "ContentView")
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
        #expect(relationships.count == 1)
        let relationship = try #require(relationships.first)
        #expect(relationship.childView == "SheetView")
        #expect(relationship.relationshipType == .sheet)
        #expect(relationship.parentView == "ContentView")
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
        #expect(relationships.count == 1)
        let relationship = try #require(relationships.first)
        #expect(relationship.childView == "FullScreenView")
        #expect(relationship.relationshipType == .fullScreenCover)
        #expect(relationship.parentView == "ContentView")
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
        #expect(relationships.count == 1)
        let relationship = try #require(relationships.first)
        #expect(relationship.childView == "PopoverView")
        #expect(relationship.relationshipType == .popover)
        #expect(relationship.parentView == "ContentView")
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
        #expect(relationships.count == 3, "Expected 3 relationships, got \(relationships.count)")
        
        let directChild = try #require(relationships.first { $0.relationshipType == .directChild })
        #expect(directChild.childView == "RoundView")
        let navigation = try #require(relationships.first { $0.relationshipType == .navigationDestination })
        #expect(navigation.childView == "DetailView")
        let sheet = try #require(relationships.first { $0.relationshipType == .sheet })
        #expect(sheet.childView == "SheetView")
    }
    
    @Test func testSimpleSheetDetection() throws {
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
        let sheet = try #require(relationships.first { $0.relationshipType == .sheet })
        #expect(sheet.childView == "SheetView")
    }
} 
