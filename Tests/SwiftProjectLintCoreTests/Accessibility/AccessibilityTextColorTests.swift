import Testing
import Foundation
import SwiftSyntax
import SwiftParser
@testable import SwiftProjectLintCore

@Suite("AccessibilityTextColorTests")
@MainActor
class AccessibilityTextColorTests {
    
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
    
    // MARK: - Text Accessibility Tests
    
    @Test func testLongTextMissingAccessibility() {
        setUp()
        defer { tearDown() }
        
        // Given
        let sourceCode = """
        struct ContentView: View {
            var body: some View {
                Text("This is a very long text that should have accessibility features for better screen reader support and user experience")
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
        #expect(visitor.detectedIssues.count == 1)
        let issue = visitor.detectedIssues.first!
        #expect(issue.severity == .info)
        #expect(issue.message.contains("Long text content may benefit from accessibility features"))
        #expect(issue.suggestion?.contains("accessibilityLabel") == true)
    }
    
    @Test func testShortTextNoAccessibilityWarning() {
        setUp()
        defer { tearDown() }
        
        // Given
        let sourceCode = """
        struct ContentView: View {
            var body: some View {
                Text("Hello")
            }
        }
        """
        
        // When
        let sourceFile = Parser.parse(source: sourceCode)
        visitor.walk(sourceFile)
        
        // Then
        #expect(visitor.detectedIssues.isEmpty)
    }
    
    @Test func testTextWithAccessibilityFeatures() {
        setUp()
        defer { tearDown() }
        
        // Given
        let sourceCode = """
        struct ContentView: View {
            var body: some View {
                Text("This is a very long text that should have accessibility features")
                    .accessibilityLabel("Important information")
                    .accessibilityHint("Contains important details about the current state")
            }
        }
        """
        
        // When
        let sourceFile = Parser.parse(source: sourceCode)
        visitor.walk(sourceFile)
        
        // Then
        #expect(visitor.detectedIssues.isEmpty)
    }
    
    // MARK: - Color Accessibility Tests
    
    @Test func testInaccessibleColorUsage() {
        setUp()
        defer { tearDown() }
        
        // Given
        let sourceCode = """
        struct ContentView: View {
            var body: some View {
                Text("Status")
                    .foregroundColor(.red)
            }
        }
        """
        
        // When
        let sourceFile = Parser.parse(source: sourceCode)
        visitor.walk(sourceFile)
        
        // Then
        #expect(visitor.detectedIssues.count == 1)
        
        let issue = visitor.detectedIssues.first!
        #expect(issue.severity == .info)
        #expect(issue.message.contains("Consider accessibility when using color-based information"))
        #expect(issue.suggestion?.contains("color is not the only way") == true)
    }
    
    @Test func testMultipleColorUsage() {
        setUp()
        defer { tearDown() }
        
        // Given
        let sourceCode = """
        struct ContentView: View {
            var body: some View {
                VStack {
                    Text("Success")
                        .foregroundColor(.green)
                    Text("Warning")
                        .foregroundColor(.yellow)
                    Text("Error")
                        .foregroundColor(.red)
                }
            }
        }
        """
        
        // When
        let sourceFile = Parser.parse(source: sourceCode)
        visitor.walk(sourceFile)
        
        // Then
        #expect(visitor.detectedIssues.count == 3)
        
        let colorIssues = visitor.detectedIssues.filter { $0.message.contains("color-based information") }
        #expect(colorIssues.count == 3)
    }
} 
