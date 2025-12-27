import Testing
import Foundation
import SwiftSyntax
import SwiftParser
@testable import SwiftProjectLintCore

@Suite("AccessibilityImageTests")
@MainActor
class AccessibilityImageTests {
    
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
    
    // MARK: - Image Missing Label Tests
    
    @Test func testImageMissingLabel() {
        setUp()
        defer { tearDown() }
        
        // Given
        let sourceCode = """
        struct ContentView: View {
            var body: some View {
                Image("profile")
                    .resizable()
                    .frame(width: 100, height: 100)
            }
        }
        """
        
        // When
        let sourceFile = Parser.parse(source: sourceCode)
        visitor.walk(sourceFile)
        
        // Then
        #expect(visitor.detectedIssues.count == 1)
        
        let issue = visitor.detectedIssues.first!
        #expect(issue.severity == .warning)
        #expect(issue.message.contains("Image missing accessibility label"))
        #expect(issue.suggestion?.contains("accessibilityLabel") == true)
    }
    
    @Test func testImageWithAccessibilityLabel() {
        setUp()
        defer { tearDown() }
        
        // Given
        let sourceCode = """
        struct ContentView: View {
            var body: some View {
                Image("profile")
                    .resizable()
                    .frame(width: 100, height: 100)
                    .accessibilityLabel("User profile picture")
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