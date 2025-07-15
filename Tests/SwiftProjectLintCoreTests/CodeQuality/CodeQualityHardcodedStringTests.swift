import Testing
import Foundation
import SwiftParser
import SwiftSyntax
@testable import SwiftProjectLintCore

@Suite("CodeQualityHardcodedStringTests")
struct CodeQualityHardcodedStringTests {
    
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

    // MARK: - Hardcoded Strings Tests
    
    @Test mutating func testHardcodedStringDetection() async throws {
        setupVisitor()
        defer { resetVisitor() }
        
        // Given
        let sourceCode = """
        struct TestView: View {
            var body: some View {
                Text("This is a very long hardcoded string that should be localized")
                Text("Short")  // Should not trigger (too short)
            }
        }
        """
        
        // When
        let sourceFile = Parser.parse(source: sourceCode)
        visitor.walk(sourceFile)
        
        // Then
        #expect(visitor.detectedIssues.count == 1)
        
        let hardcodedIssues = visitor.detectedIssues.filter { $0.message.contains("hardcoded text") }
        #expect(hardcodedIssues.count == 1)
        
        let issue = hardcodedIssues.first
        #expect(issue != nil)
        #expect(issue?.severity == .info)
        #expect(issue?.message.contains("This is a very long hardcoded string") == true)
    }
    
    @Test mutating func testHardcodedStringSkipPatterns() async throws {
        setupVisitor()
        defer { resetVisitor() }
        
        // Given
        let sourceCode = """
        struct TestView: View {
            var body: some View {
                Text("https://example.com")  // Should skip (contains http)
                Text("private var test")     // Should skip (contains private)
                Text("func doSomething")     // Should skip (contains func)
                Text("This is a user-facing message that should be localized")  // Should trigger
            }
        }
        """
        
        // When
        let sourceFile = Parser.parse(source: sourceCode)
        visitor.walk(sourceFile)
        
        // Then
        #expect(visitor.detectedIssues.count == 1)
        
        let hardcodedIssues = visitor.detectedIssues.filter { $0.message.contains("hardcoded text") }
        #expect(hardcodedIssues.count == 1)
        
        let issue = hardcodedIssues.first
        #expect(issue?.message.contains("user-facing message") == true)
    }
    
    @Test mutating func testHardcodedStringDetectionCharacterization() async throws {
        setupVisitor()
        defer { resetVisitor() }
        
        // Given
        let sourceCode = """
        struct TestView: View {
            var body: some View {
                Text("This is a very long hardcoded string that should be localized")
                Text("Short")  // Should not trigger (too short)
            }
        }
        """
        
        // When
        let sourceFile = Parser.parse(source: sourceCode)
        visitor.walk(sourceFile)
        
        // Then
        #expect(visitor.detectedIssues.count == 1)
        
        let hardcodedIssues = visitor.detectedIssues.filter { $0.message.contains("hardcoded text") }
        #expect(hardcodedIssues.count == 1)
        
        let issue = hardcodedIssues.first
        #expect(issue != nil)
        #expect(issue?.severity == .info)
        #expect(issue?.message.contains("This is a very long hardcoded string") == true)
    }
    
    @Test mutating func testStrictHardcodedStringDetectionCharacterization() async throws {
        setupStrictVisitor()
        defer { resetVisitor() }
        
        // Given
        let sourceCode = """
        struct TestView: View {
            var body: some View {
                Text("This is a very long hardcoded string that should be localized")
                Text("Short")  // Should not trigger (too short)
            }
        }
        """
        
        // When
        let sourceFile = Parser.parse(source: sourceCode)
        visitor.walk(sourceFile)
        
        // Then
        #expect(visitor.detectedIssues.count == 2)
        
        let hardcodedIssues = visitor.detectedIssues.filter { $0.message.contains("hardcoded text") }
        #expect(hardcodedIssues.count == 2)
        
        let issue = hardcodedIssues.first
        #expect(issue != nil)
        #expect(issue?.severity == .info)
        #expect(issue?.message.contains("This is a very long hardcoded string") == true)
    }
} 