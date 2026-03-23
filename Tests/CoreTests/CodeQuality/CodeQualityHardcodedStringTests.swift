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
                Text("This is a hardcoded string that should be localized")
                Image("icon")  // Not user-facing text — should not trigger
            }
        }
        """

        // When
        let sourceFile = Parser.parse(source: sourceCode)
        visitor.walk(sourceFile)

        // Then
        let hardcodedIssues = visitor.detectedIssues.filter { $0.ruleName == .hardcodedStrings }
        #expect(hardcodedIssues.count == 1)

        let issue = hardcodedIssues.first
        #expect(issue != nil)
        #expect(issue?.severity == .info)
        #expect(issue?.message.contains("hardcoded string") == true)
    }

    @Test func testShortStringInTextIsDetected() throws {
        let visitor = createVisitor()

        let sourceCode = """
        struct TestView: View {
            var body: some View {
                Text("Save")
            }
        }
        """

        let sourceFile = Parser.parse(source: sourceCode)
        visitor.walk(sourceFile)

        let hardcodedIssues = visitor.detectedIssues.filter { $0.ruleName == .hardcodedStrings }
        #expect(hardcodedIssues.count == 1)
    }

    @Test func testStringOutsideSwiftUINotDetected() throws {
        let visitor = createVisitor()

        let sourceCode = """
        struct MyModel {
            let name = "This is a long string not in any view"
            func doWork() {
                print("Processing completed successfully")
            }
        }
        """

        let sourceFile = Parser.parse(source: sourceCode)
        visitor.walk(sourceFile)

        let hardcodedIssues = visitor.detectedIssues.filter { $0.ruleName == .hardcodedStrings }
        #expect(hardcodedIssues.isEmpty)
    }

    @Test func testHardcodedStringSkipPatterns() throws {
        let visitor = createVisitor()

        // Given — URLs in Text() are skipped; strings outside SwiftUI views are not flagged
        let sourceCode = """
        struct TestView: View {
            var body: some View {
                Text("https://example.com")  // Should skip (URL)
                Text("This is a user-facing message that should be localized")  // Should trigger
            }
            let errorMessage = "Something went wrong, please try again"  // Not in UI — should NOT trigger
        }
        """

        // When
        let sourceFile = Parser.parse(source: sourceCode)
        visitor.walk(sourceFile)

        // Then
        let hardcodedIssues = visitor.detectedIssues.filter { $0.message.contains("hardcoded text") }
        #expect(hardcodedIssues.count == 1)

        let issue = hardcodedIssues.first
        #expect(issue?.message.contains("user-facing message") == true)
    }

    @Test func testHardcodedStringDetectionCharacterization() throws {
        let visitor = createVisitor()

        let sourceCode = """
        struct TestView: View {
            var body: some View {
                Text("This is a hardcoded string that should be localized")
                Image("icon")
            }
        }
        """

        let sourceFile = Parser.parse(source: sourceCode)
        visitor.walk(sourceFile)

        let hardcodedIssues = visitor.detectedIssues.filter { $0.ruleName == .hardcodedStrings }
        #expect(hardcodedIssues.count == 1)
        #expect(hardcodedIssues.first?.severity == .info)
    }

    @Test func testShortStringsNotDetected() throws {
        let visitor = createVisitor()

        let sourceCode = """
        struct TestView: View {
            var body: some View {
                Text("•")
                Text("OK")
                Text("Go")
            }
        }
        """

        let sourceFile = Parser.parse(source: sourceCode)
        visitor.walk(sourceFile)

        let hardcodedIssues = visitor.detectedIssues.filter { $0.ruleName == .hardcodedStrings }
        #expect(hardcodedIssues.isEmpty)
    }

    @Test func testTestFileStringsNotDetected() throws {
        let visitor = createVisitor()
        visitor.setFilePath("MyAppTests/ViewTests.swift")

        let sourceCode = """
        struct TestHelperView: View {
            var body: some View {
                Text("Hello World")
            }
        }
        """

        let sourceFile = Parser.parse(source: sourceCode)
        visitor.walk(sourceFile)

        let hardcodedIssues = visitor.detectedIssues.filter { $0.ruleName == .hardcodedStrings }
        #expect(hardcodedIssues.isEmpty)
    }

    @Test func testThreeCharStringStillDetected() throws {
        let visitor = createVisitor()

        let sourceCode = """
        struct TestView: View {
            var body: some View {
                Text("Yes")
            }
        }
        """

        let sourceFile = Parser.parse(source: sourceCode)
        visitor.walk(sourceFile)

        let hardcodedIssues = visitor.detectedIssues.filter { $0.ruleName == .hardcodedStrings }
        #expect(hardcodedIssues.count == 1)
    }
}
