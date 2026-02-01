import Testing
import Foundation
import SwiftSyntax
import SwiftParser
@testable import SwiftProjectLintCore

@Suite("AccessibilityComplexViewTests")
@MainActor
class AccessibilityComplexViewTests {
    
    // MARK: - Test Instance Variables
    
    var visitor: AccessibilityVisitor!
    
    func setUp() {
        // Initialize shared registry if not already done
        TestRegistryManager.initializeSharedRegistry()
        visitor = AccessibilityVisitor(viewMode: .sourceAccurate)
    }
    
    func tearDown() {
        visitor = nil
    }
    
    // MARK: - Complex View Tests
    
    @Test func testComplexViewWithMultipleAccessibilityIssues() {
        setUp()
        defer { tearDown() }
        
        // Given
        let sourceCode = """
        struct ContentView: View {
            var body: some View {
                VStack {
                    Button {
                        // action
                    } label: {
                        Image("settings")
                    }
                    
                    Button {
                        // action
                    } label: {
                        Text("Submit a very long form with many fields and complex validation")
                    }
                    
                    Image("logo")
                        .resizable()
                        .frame(width: 200, height: 100)
                    
                    Text("Status: Active")
                        .foregroundColor(.green)
                }
            }
        }
        """
        
        // When
        let sourceFile = Parser.parse(source: sourceCode)
        visitor.walk(sourceFile)
        DebugLogger.log("Detected issues count: \(visitor.detectedIssues.count)")
        for (index, issue) in visitor.detectedIssues.enumerated() {
            DebugLogger.log("Issue \(index): \(issue.message)")
        }
        // Then
        #expect(visitor.detectedIssues.count == 5)
        
        let buttonWithImageIssues = visitor.detectedIssues.filter { $0.message.contains("Button with image missing accessibility label") }
        #expect(buttonWithImageIssues.count == 1)
        
        let buttonWithTextIssues = visitor.detectedIssues.filter { $0.message.contains("Consider adding accessibility hint") }
        #expect(buttonWithTextIssues.count == 1)
        
        let imageIssues = visitor.detectedIssues.filter { $0.message.contains("Image missing accessibility label") }
        #expect(imageIssues.count == 1)
        
        let textIssues = visitor.detectedIssues.filter { $0.message.contains("Long text content may benefit") }
        #expect(textIssues.count == 1)
        
        let colorIssues = visitor.detectedIssues.filter { $0.message.contains("color-based information") }
        #expect(colorIssues.count == 1)
    }
    
    // MARK: - Edge Cases
    
    @Test func testEmptyView() {
        setUp()
        defer { tearDown() }
        
        // Given
        let sourceCode = """
        struct ContentView: View {
            var body: some View {
                EmptyView()
            }
        }
        """
        
        // When
        let sourceFile = Parser.parse(source: sourceCode)
        visitor.walk(sourceFile)
        
        // Then
        #expect(visitor.detectedIssues.isEmpty)
    }
    
    @Test func testViewWithNoAccessibilityIssues() {
        setUp()
        defer { tearDown() }
        
        // Given
        let sourceCode = """
        struct ContentView: View {
            var body: some View {
                VStack {
                    Button("Click me") {
                        // action
                    }
                    .accessibilityHint("Performs the main action")
                    
                    Image("icon")
                        .accessibilityLabel("Application icon")
                    
                    Text("Short text")
                }
            }
        }
        """
        
        // When
        let sourceFile = Parser.parse(source: sourceCode)
        visitor.walk(sourceFile)
        
        // Then
        #expect(visitor.detectedIssues.isEmpty)
    }
} 
