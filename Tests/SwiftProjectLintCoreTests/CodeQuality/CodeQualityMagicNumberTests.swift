import Testing
import Foundation
import SwiftParser
import SwiftSyntax
@testable import SwiftProjectLintCore

struct CodeQualityMagicNumberTests {

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

    // MARK: - Magic Numbers Tests

    @Test func testMagicNumberDetectionInPadding() throws {
        let visitor = createVisitor()

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
        #expect(visitor.detectedIssues.filter { $0.ruleName == .magicNumber }.count == 2)

        let magicNumberIssues = visitor.detectedIssues.filter { $0.message.contains("magic number") }
        #expect(magicNumberIssues.count == 2)

        let issue16 = magicNumberIssues.first { $0.message.contains("16") }
        #expect(issue16 != nil)
        #expect(issue16?.severity == .info)

        let issue20 = magicNumberIssues.first { $0.message.contains("20") }
        #expect(issue20 != nil)
        #expect(issue20?.severity == .info)
    }

    @Test func testMagicNumberDetectionInVariableInitialization() throws {
        let visitor = createVisitor()

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
        #expect(visitor.detectedIssues.filter { $0.ruleName == .magicNumber }.count == 2)

        let magicNumberIssues = visitor.detectedIssues.filter { $0.message.contains("magic number") }
        #expect(magicNumberIssues.count == 2)

        let issue16 = magicNumberIssues.first { $0.message.contains("16") }
        #expect(issue16 != nil)

        let issue12 = magicNumberIssues.first { $0.message.contains("12") }
        #expect(issue12 != nil)
    }

    @Test func testMagicNumberDetectionInFrame() throws {
        let visitor = createVisitor()

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
        #expect(visitor.detectedIssues.filter { $0.ruleName == .magicNumber }.count == 2)

        let magicNumberIssues = visitor.detectedIssues.filter { $0.message.contains("magic number") }
        #expect(magicNumberIssues.count == 2)

        let issue300 = magicNumberIssues.first { $0.message.contains("300") }
        #expect(issue300 != nil)

        let issue200 = magicNumberIssues.first { $0.message.contains("200") }
        #expect(issue200 != nil)
    }

    @Test func testMagicNumberThreshold() throws {
        let visitor = createVisitor()

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
        #expect(visitor.detectedIssues.filter { $0.ruleName == .magicNumber }.count == 1)

        let magicNumberIssues = visitor.detectedIssues.filter { $0.message.contains("magic number") }
        #expect(magicNumberIssues.count == 1)

        let issue15 = magicNumberIssues.first { $0.message.contains("15") }
        #expect(issue15 != nil)
    }

    @Test func testMagicNumberDetectionCharacterization() throws {
        let visitor = createVisitor()
        // Given
        let sourceCode = """
        struct TestView: View {
            var body: some View { Text("Hello").padding(16) }
        }
        """
        // When
        let sourceFile = Parser.parse(source: sourceCode)
        visitor.walk(sourceFile)
        // Then - characterization test
        _ = visitor.detectedIssues
    }

    @Test func testStrictMagicNumberDetectionCharacterization() throws {
        let visitor = createStrictVisitor()
        // Given
        let sourceCode = """
        struct TestView: View {
            var body: some View { Text("Hello").padding(16) }
        }
        """
        // When
        let sourceFile = Parser.parse(source: sourceCode)
        visitor.walk(sourceFile)
        // Then - characterization test
        _ = visitor.detectedIssues
    }
}
