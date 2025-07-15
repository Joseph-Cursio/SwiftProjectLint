import Testing
import Foundation
import SwiftParser
import SwiftSyntax
@testable import SwiftProjectLintCore

@Suite("CodeQualityDocumentationTests")
struct CodeQualityDocumentationTests {
    
    var visitor: CodeQualityVisitor!
    
    // MARK: - Test Helper Methods
    
    private mutating func setupVisitor() {
        visitor = CodeQualityVisitor(patternCategory: .codeQuality)
        visitor.setFilePath("TestFile.swift")
    }
    
    private mutating func resetVisitor() {
        visitor = nil
    }

    // MARK: - Missing Documentation Tests
    
    @Test mutating func testMissingDocumentationDetection() async throws {
        setupVisitor()
        defer { resetVisitor() }
        
        // Given
        let sourceCode = """
        public struct TestView: View {
            public func publicFunction() {
                // No documentation
            }
            
            var body: some View {
                Text("Hello")
            }
        }
        
        public class TestClass {
            public func anotherPublicFunction() {
                // No documentation
            }
        }
        """
        
        // When
        let sourceFile = Parser.parse(source: sourceCode)
        visitor.walk(sourceFile)
        
        // Then
        #expect(visitor.detectedIssues.count == 4)
        
        let documentationIssues = visitor.detectedIssues.filter { $0.message.contains("documentation") }
        #expect(documentationIssues.count == 4)
        
        let structIssue = documentationIssues.first { $0.message.contains("TestView") }
        #expect(structIssue != nil)
        
        let functionIssue = documentationIssues.first { $0.message.contains("publicFunction") }
        #expect(functionIssue != nil)
        
        let classIssue = documentationIssues.first { $0.message.contains("TestClass") }
        #expect(classIssue != nil)
        
        let anotherFunctionIssue = documentationIssues.first { $0.message.contains("anotherPublicFunction") }
        #expect(anotherFunctionIssue != nil)
    }
    
    @Test mutating func testDocumentedAPIsNoDetection() async throws {
        setupVisitor()
        defer { resetVisitor() }
        
        // Given
        let sourceCode = """
        /// A test view for demonstration purposes
        public struct TestView: View {
            /// A public function with documentation
            public func publicFunction() {
                // Has documentation
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
    
    @Test mutating func testPrivateAPIsNoDetection() async throws {
        setupVisitor()
        defer { resetVisitor() }
        
        // Given
        let sourceCode = """
        struct TestView: View {
            func privateFunction() {
                // No documentation but private
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
} 