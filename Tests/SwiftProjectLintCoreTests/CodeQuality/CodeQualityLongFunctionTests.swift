import Testing
import Foundation
import SwiftParser
import SwiftSyntax
@testable import SwiftProjectLintCore

@Suite("CodeQualityLongFunctionTests")
struct CodeQualityLongFunctionTests {

    // MARK: - Test Helper Methods

    private func createVisitor() -> CodeQualityVisitor {
        let visitor = CodeQualityVisitor(patternCategory: .codeQuality)
        visitor.setFilePath("TestFile.swift")
        return visitor
    }

    private func createStrictVisitor() -> CodeQualityVisitor {
        let visitor = CodeQualityVisitor(patternCategory: .codeQuality, configuration: .strict)
        visitor.setFilePath("TestFile.swift")
        return visitor
    }

    // MARK: - Long Functions Tests

    @Test func testLongFunctionDetection() throws {
        let visitor = createVisitor()

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

    @Test func testShortFunctionNoDetection() throws {
        let visitor = createVisitor()

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
        #expect(visitor.detectedIssues.isEmpty)
    }

    @Test func testFunctionLengthDetectionCharacterization() throws {
        let visitor = createVisitor()
        // Given
        let sourceCode = """
        struct TestView: View {
            func longFunction() {
                let a = "This is a very long function"
            }
            var body: some View { Text("Hello") }
        }
        """
        // When
        let sourceFile = Parser.parse(source: sourceCode)
        visitor.walk(sourceFile)
        // Then - characterization test, just verify it runs
        _ = visitor.detectedIssues
    }

    @Test func testStrictFunctionLengthDetectionCharacterization() throws {
        let visitor = createStrictVisitor()
        // Given
        let sourceCode = """
        struct TestView: View {
            func longFunction() {
                let a = "This is a very long function"
            }
            var body: some View { Text("Hello") }
        }
        """
        // When
        let sourceFile = Parser.parse(source: sourceCode)
        visitor.walk(sourceFile)
        // Then - characterization test, just verify it runs
        _ = visitor.detectedIssues
    }
}
