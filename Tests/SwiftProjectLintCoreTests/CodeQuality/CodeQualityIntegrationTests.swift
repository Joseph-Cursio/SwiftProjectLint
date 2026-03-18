import Testing
import Foundation
import SwiftParser
import SwiftSyntax
@testable import SwiftProjectLintCore

@Suite("CodeQualityIntegrationTests")
struct CodeQualityIntegrationTests {

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

    // MARK: - Integration Tests

    @Test func testMultipleCodeQualityIssues() throws {
        let visitor = createVisitor()

        // Given
        // swiftlint:disable line_length
        let sourceCode = """
        public struct TestView: View {
            let spacing: CGFloat = 16

            func longFunction() {
                let a =
                    "This is a very long function that contains many lines of code and should be broken down into smaller functions for better maintainability and readability. The function is intentionally made long to test the detection mechanism."
                let b = "More code here to make the function longer and trigger the detection threshold."
                let c = "Even more code to ensure we exceed the character limit for function length detection."
            }

            var body: some View {
                Text("This is a very long hardcoded string that should be localized")
                    .padding(20)
            }
        }
        """
        // swiftlint:enable line_length

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

    @Test func testEdgeCaseCharacterization() throws {
        let visitor = createVisitor()

        // Given
        // swiftlint:disable line_length
        let sourceCode = """
        public struct TestView: View {
            let spacing: CGFloat = 16

            func longFunction() {
                let a =
                    "This is a very long function that contains many lines of code and should be broken down into smaller functions for better maintainability and readability. The function is intentionally made long to test the detection mechanism."
                let b = "More code here to make the function longer and trigger the detection threshold."
                let c = "Even more code to ensure we exceed the character limit for function length detection."
            }

            var body: some View {
                Text("This is a very long hardcoded string that should be localized")
                    .padding(20)
            }
        }
        """
        // swiftlint:enable line_length

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

    @Test func testConfigurationCharacterization() throws {
        let visitor = createStrictVisitor()

        // Given
        // swiftlint:disable line_length
        let sourceCode = """
        public struct TestView: View {
            let spacing: CGFloat = 16

            func longFunction() {
                let a =
                    "This is a very long function that contains many lines of code and should be broken down into smaller functions for better maintainability and readability. The function is intentionally made long to test the detection mechanism."
                let b = "More code here to make the function longer and trigger the detection threshold."
                let c = "Even more code to ensure we exceed the character limit for function length detection."
            }

            var body: some View {
                Text("This is a very long hardcoded string that should be localized")
                    .padding(20)
            }
        }
        """
        // swiftlint:enable line_length

        // When
        let sourceFile = Parser.parse(source: sourceCode)
        visitor.walk(sourceFile)

        // Then
        // May detect more issues than expected (e.g., struct documentation + function documentation)
        #expect(visitor.detectedIssues.count >= 5)

        // Magic numbers
        let magicNumberIssues = visitor.detectedIssues.filter { $0.message.contains("magic number") }
        #expect(magicNumberIssues.count >= 2)

        // Hardcoded strings
        let hardcodedIssues = visitor.detectedIssues.filter { $0.message.contains("hardcoded text") }
        #expect(hardcodedIssues.count >= 1)

        // Long functions
        let longFunctionIssues = visitor.detectedIssues.filter { $0.message.contains("quite long") }
        #expect(longFunctionIssues.count >= 1)

        // Missing documentation (may detect both struct and function documentation)
        let documentationIssues = visitor.detectedIssues.filter { $0.message.contains("documentation") }
        #expect(documentationIssues.count >= 1)
    }

    // MARK: - Configuration Tests

    @Test func testConfigurationDefault() throws {
        // Given
        let config = CodeQualityVisitor.Configuration.default

        // Then
        #expect(config.maxFunctionLength == 200)
        #expect(config.minStringLengthForLocalization == 10)
        #expect(config.magicNumberThreshold == 10)
        #expect(config.checkPublicAPIsOnly)
    }

    @Test func testConfigurationStrict() throws {
        // Given
        let config = CodeQualityVisitor.Configuration.strict

        // Then
        #expect(config.maxFunctionLength == 150)
        #expect(config.minStringLengthForLocalization == 5)
        #expect(config.magicNumberThreshold == 5)
        #expect(!config.checkPublicAPIsOnly)
    }
}
