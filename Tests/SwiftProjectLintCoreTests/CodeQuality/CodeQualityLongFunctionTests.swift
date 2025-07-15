import Testing
import Foundation
import SwiftParser
import SwiftSyntax
@testable import SwiftProjectLintCore

@Suite("CodeQualityLongFunctionTests")
struct CodeQualityLongFunctionTests {
    
    var visitor: CodeQualityVisitor!
    
    // MARK: - Test Helper Methods
    
    private mutating func setupVisitor() {
        visitor = CodeQualityVisitor(patternCategory: .codeQuality)
        visitor.setFilePath("TestFile.swift")
    }
    
    private mutating func setupStrictVisitor() {
        visitor = CodeQualityVisitor(patternCategory: .codeQuality, configuration: .strict)
        visitor.setFilePath("TestFile.swift")
    }
    
    private mutating func resetVisitor() {
        visitor = nil
    }

    // MARK: - Long Functions Tests
    
    @Test mutating func testLongFunctionDetection() async throws {
        setupVisitor()
        defer { resetVisitor() }
        
        // Given
        let sourceCode = """
        struct TestView: View {
            func veryLongFunction() {
                let a = "This is a very long function that contains many lines of code and should be broken down into smaller functions for better maintainability and readability. The function is intentionally made long to test the detection mechanism."
                let b = "More code here to make the function longer and trigger the detection threshold."
                let c = "Even more code to ensure we exceed the character limit for function length detection."
                let d = "Additional code to push the function over the 200 character threshold."
                let e = "Final piece of code to make sure the function is long enough to be detected as problematic."
            }
            
            var body: some View {
                Text("Hello")
            }
        }
        """
        
        // When
        let sourceFile = Parser.parse(source: sourceCode)
        visitor.walk(sourceFile)
        
        // Then
        #expect(visitor.detectedIssues.count == 1) // 1 long function only
        
        let longFunctionIssues = visitor.detectedIssues.filter { $0.message.contains("quite long") }
        #expect(longFunctionIssues.count == 1)
    }
    
    @Test mutating func testShortFunctionNoDetection() async throws {
        setupVisitor()
        defer { resetVisitor() }
        
        // Given
        let sourceCode = """
        struct TestView: View {
            func shortFunction() {
                let a = "Short"
            }
            
            var body: some View {
                Text("Hello")
            }
        }
        """
        
        // When
        let sourceFile = Parser.parse(source: sourceCode)
        visitor.walk(sourceFile)
        
        // Then
        #expect(visitor.detectedIssues.count == 0)
    }
    
    @Test mutating func testFunctionLengthDetectionCharacterization() async throws {
        setupVisitor()
        defer { resetVisitor() }
        // ... existing code ...
    }
    
    @Test mutating func testStrictFunctionLengthDetectionCharacterization() async throws {
        setupStrictVisitor()
        defer { resetVisitor() }
        // ... existing code ...
    }
} 