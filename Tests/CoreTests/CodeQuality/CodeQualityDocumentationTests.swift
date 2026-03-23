import Testing
import Foundation
import SwiftParser
import SwiftSyntax
@testable import Core

struct CodeQualityDocumentationTests {

    // MARK: - Test Helper Methods

    private func createVisitor() -> DocumentationVisitor {
        let visitor = DocumentationVisitor(patternCategory: .codeQuality)
        visitor.setFilePath("TestFile.swift")
        return visitor
    }

    private func createStrictVisitor() -> DocumentationVisitor {
        let visitor = DocumentationVisitor(patternCategory: .codeQuality, configuration: .strict)
        visitor.setFilePath("TestFile.swift")
        return visitor
    }

    // MARK: - Missing Documentation Tests

    @Test func testMissingDocumentationDetection() throws {
        let visitor = createVisitor()

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
        #expect(visitor.detectedIssues.filter { $0.ruleName == .missingDocumentation }.count == 4)

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

    @Test func testDocumentedAPIsNoDetection() throws {
        let visitor = createVisitor()

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
        #expect(visitor.detectedIssues.filter { $0.ruleName == .missingDocumentation }.isEmpty)
    }

    @Test func testPrivateAPIsNoDetection() throws {
        let visitor = createVisitor()

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
        #expect(visitor.detectedIssues.filter { $0.ruleName == .missingDocumentation }.isEmpty)
    }

    @Test func testDocumentationDetectionCharacterization() throws {
        let visitor = createVisitor()
        // Given
        let sourceCode = """
        public struct TestView: View {
            var body: some View { Text("Hello") }
        }
        """
        // When
        let sourceFile = Parser.parse(source: sourceCode)
        visitor.walk(sourceFile)
        // Then - characterization test
        _ = visitor.detectedIssues
    }

    @Test func testStrictDocumentationDetectionCharacterization() throws {
        let visitor = createStrictVisitor()
        // Given
        let sourceCode = """
        public struct TestView: View {
            var body: some View { Text("Hello") }
        }
        """
        // When
        let sourceFile = Parser.parse(source: sourceCode)
        visitor.walk(sourceFile)
        // Then - characterization test
        _ = visitor.detectedIssues
    }
}
