import Testing
import Foundation
import SwiftParser
import SwiftSyntax
@testable import SwiftProjectLintCore

@Suite("CodeQualityMagicNumberTests")
struct CodeQualityMagicNumberTests {
    
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

    // MARK: - Magic Numbers Tests
    
    @Test mutating func testMagicNumberDetectionInPadding() async throws {
        setupVisitor()
        defer { resetVisitor() }
        
        // Given
        let sourceCode = """
        struct TestView: View {
            var body: some View {
                Text("Hello")
                    .padding(16)
                    .padding(20.0)
            }
        }
        """
        
        // When
        let sourceFile = Parser.parse(source: sourceCode)
        visitor.walk(sourceFile)
        
        // Then
        #expect(visitor.detectedIssues.count == 2)
        
        let magicNumberIssues = visitor.detectedIssues.filter { $0.message.contains("magic number") }
        #expect(magicNumberIssues.count == 2)
        
        let issue16 = magicNumberIssues.first { $0.message.contains("16") }
        #expect(issue16 != nil)
        #expect(issue16?.severity == .info)
        
        let issue20 = magicNumberIssues.first { $0.message.contains("20") }
        #expect(issue20 != nil)
        #expect(issue20?.severity == .info)
    }
    
    @Test mutating func testMagicNumberDetectionInVariableInitialization() async throws {
        setupVisitor()
        defer { resetVisitor() }
        
        // Given
        let sourceCode = """
        struct TestView: View {
            let spacing: CGFloat = 16
            let cornerRadius: CGFloat = 12.0
            
            var body: some View {
                Text("Hello")
            }
        }
        """
        
        // When
        let sourceFile = Parser.parse(source: sourceCode)
        visitor.walk(sourceFile)
        
        // Then
        #expect(visitor.detectedIssues.count == 2)
        
        let magicNumberIssues = visitor.detectedIssues.filter { $0.message.contains("magic number") }
        #expect(magicNumberIssues.count == 2)
        
        let issue16 = magicNumberIssues.first { $0.message.contains("16") }
        #expect(issue16 != nil)
        
        let issue12 = magicNumberIssues.first { $0.message.contains("12") }
        #expect(issue12 != nil)
    }
    
    @Test mutating func testMagicNumberDetectionInFrame() async throws {
        setupVisitor()
        defer { resetVisitor() }
        
        // Given
        let sourceCode = """
        struct TestView: View {
            var body: some View {
                Text("Hello")
                    .frame(width: 300, height: 200)
            }
        }
        """
        
        // When
        let sourceFile = Parser.parse(source: sourceCode)
        visitor.walk(sourceFile)
        
        // Then
        #expect(visitor.detectedIssues.count == 2)
        
        let magicNumberIssues = visitor.detectedIssues.filter { $0.message.contains("magic number") }
        #expect(magicNumberIssues.count == 2)
        
        let issue300 = magicNumberIssues.first { $0.message.contains("300") }
        #expect(issue300 != nil)
        
        let issue200 = magicNumberIssues.first { $0.message.contains("200") }
        #expect(issue200 != nil)
    }
    
    @Test mutating func testMagicNumberThreshold() async throws {
        setupVisitor()
        defer { resetVisitor() }
        
        // Given
        let sourceCode = """
        struct TestView: View {
            var body: some View {
                Text("Hello")
                    .padding(5)  // Should not trigger (below threshold)
                    .padding(15) // Should trigger (above threshold)
            }
        }
        """
        
        // When
        let sourceFile = Parser.parse(source: sourceCode)
        visitor.walk(sourceFile)
        
        // Then
        #expect(visitor.detectedIssues.count == 1)
        
        let magicNumberIssues = visitor.detectedIssues.filter { $0.message.contains("magic number") }
        #expect(magicNumberIssues.count == 1)
        
        let issue15 = magicNumberIssues.first { $0.message.contains("15") }
        #expect(issue15 != nil)
    }
    
    @Test mutating func testMagicNumberDetectionCharacterization() async throws {
        setupVisitor()
        do { resetVisitor() }
        // ... existing code ...
    }
    
    @Test mutating func testStrictMagicNumberDetectionCharacterization() async throws {
        setupStrictVisitor()
        do { resetVisitor() }
        // ... existing code ...
    }
} 
