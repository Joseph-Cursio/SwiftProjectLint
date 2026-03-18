import Testing
import Foundation
import SwiftParser
import SwiftSyntax
@testable import SwiftProjectLintCore

struct CodeQualityHardcodedStringTests {

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

    // MARK: - Hardcoded Strings Tests

    @Test func testHardcodedStringDetection() throws {
        let visitor = createVisitor()

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

    @Test func testHardcodedStringSkipPatterns() throws {
        let visitor = createVisitor()

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

    @Test func testHardcodedStringDetectionCharacterization() throws {
        let visitor = createVisitor()

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

    @Test func testStrictHardcodedStringDetectionCharacterization() throws {
        let visitor = createStrictVisitor()

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
        // May detect multiple issues (e.g., hardcoded string in Text, and potentially struct documentation)
        #expect(visitor.detectedIssues.count >= 1)

        let hardcodedIssues = visitor.detectedIssues.filter { $0.message.contains("hardcoded text") }
        // At least one hardcoded string should be detected
        #expect(hardcodedIssues.count >= 1)

        let issue = hardcodedIssues.first
        #expect(issue != nil)
        #expect(issue?.severity == .info)
        #expect(issue?.message.contains("This is a very long hardcoded string") == true)
    }
}
