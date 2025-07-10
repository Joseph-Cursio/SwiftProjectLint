import Testing
import Foundation
import SwiftParser
import SwiftSyntax
@testable import SwiftProjectLintCore

struct CodeQualityVisitorTests {
    
    var visitor: CodeQualityVisitor!
    
    // MARK: - Test Helper Methods
    
    private mutating func setupVisitor() {
        visitor = CodeQualityVisitor(patternCategory: .codeQuality)
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
    
    // MARK: - Integration Tests
    
    @Test mutating func testMultipleCodeQualityIssues() async throws {
        setupVisitor()
        defer { resetVisitor() }
        
        // Given
        let sourceCode = """
        public struct TestView: View {
            let spacing: CGFloat = 16
            
            func longFunction() {
                let a = "This is a very long function that contains many lines of code and should be broken down into smaller functions for better maintainability and readability. The function is intentionally made long to test the detection mechanism."
                let b = "More code here to make the function longer and trigger the detection threshold."
                let c = "Even more code to ensure we exceed the character limit for function length detection."
            }
            
            var body: some View {
                Text("This is a very long hardcoded string that should be localized")
                    .padding(20)
            }
        }
        """
        
        // When
        let sourceFile = Parser.parse(source: sourceCode)
        visitor.walk(sourceFile)
        
        // Then
        #expect(visitor.detectedIssues.count == 5)
        
        // Magic numbers
        let magicNumberIssues = visitor.detectedIssues.filter { $0.message.contains("magic number") }
        #expect(magicNumberIssues.count == 2)
        
        // Hardcoded strings
        let hardcodedIssues = visitor.detectedIssues.filter { $0.message.contains("hardcoded text") }
        #expect(hardcodedIssues.count == 1)
        
        // Long functions
        let longFunctionIssues = visitor.detectedIssues.filter { $0.message.contains("quite long") }
        #expect(longFunctionIssues.count == 1)
        
        // Missing documentation
        let documentationIssues = visitor.detectedIssues.filter { $0.message.contains("documentation") }
        #expect(documentationIssues.count == 1)
    }
    
    // MARK: - Configuration Tests
    
    @Test func testConfigurationDefault() async throws {
        // Given
        let config = CodeQualityVisitor.Configuration.default
        
        // Then
        #expect(config.maxFunctionLength == 200)
        #expect(config.minStringLengthForLocalization == 10)
        #expect(config.magicNumberThreshold == 10)
        #expect(config.checkPublicAPIsOnly == true)
    }
    
    @Test func testConfigurationStrict() async throws {
        // Given
        let config = CodeQualityVisitor.Configuration.strict
        
        // Then
        #expect(config.maxFunctionLength == 150)
        #expect(config.minStringLengthForLocalization == 5)
        #expect(config.magicNumberThreshold == 5)
        #expect(config.checkPublicAPIsOnly == false)
    }
} 