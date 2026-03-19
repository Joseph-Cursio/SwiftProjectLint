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

    // MARK: - Repeated Magic Numbers (should fire)

    @Test func testRepeatedMagicNumberDetected() throws {
        let visitor = createVisitor()

        let sourceCode = """
        struct TestView: View {
            var body: some View {
                Text("Hello")
                    .padding(16)
                    .frame(width: 16)
            }
        }
        """

        let sourceFile = Parser.parse(source: sourceCode)
        visitor.walk(sourceFile)

        let magicIssues = visitor.detectedIssues.filter { $0.ruleName == .magicNumber }
        #expect(magicIssues.count == 2)
        #expect(magicIssues.allSatisfy { $0.message.contains("16") })
    }

    @Test func testRepeatedFloatMagicNumberDetected() throws {
        let visitor = createVisitor()

        let sourceCode = """
        struct TestView: View {
            let cornerRadius: CGFloat = 12.0
            var body: some View {
                Text("Hello")
                    .cornerRadius(12.0)
            }
        }
        """

        let sourceFile = Parser.parse(source: sourceCode)
        visitor.walk(sourceFile)

        let magicIssues = visitor.detectedIssues.filter { $0.ruleName == .magicNumber }
        #expect(magicIssues.count == 2)
        #expect(magicIssues.allSatisfy { $0.message.contains("12.0") })
    }

    // MARK: - Single-use numbers (should NOT fire)

    @Test func testSingleUseMagicNumberNotDetected() throws {
        let visitor = createVisitor()

        let sourceCode = """
        struct TestView: View {
            var body: some View {
                Text("Hello")
                    .padding(16)
                    .frame(width: 300, height: 200)
            }
        }
        """

        let sourceFile = Parser.parse(source: sourceCode)
        visitor.walk(sourceFile)

        let magicIssues = visitor.detectedIssues.filter { $0.ruleName == .magicNumber }
        #expect(magicIssues.isEmpty)
    }

    @Test func testSingleUseInVariableNotDetected() throws {
        let visitor = createVisitor()

        let sourceCode = """
        struct TestView: View {
            let spacing: CGFloat = 16
            let cornerRadius: CGFloat = 12.0
            var body: some View {
                EmptyView()
            }
        }
        """

        let sourceFile = Parser.parse(source: sourceCode)
        visitor.walk(sourceFile)

        let magicIssues = visitor.detectedIssues.filter { $0.ruleName == .magicNumber }
        #expect(magicIssues.isEmpty)
    }

    // MARK: - Threshold

    @Test func testBelowThresholdNotDetected() throws {
        let visitor = createVisitor()

        let sourceCode = """
        struct TestView: View {
            var body: some View {
                Text("Hello")
                    .padding(5)
                    .padding(5)
            }
        }
        """

        let sourceFile = Parser.parse(source: sourceCode)
        visitor.walk(sourceFile)

        // 5 is below the default threshold of 10
        let magicIssues = visitor.detectedIssues.filter { $0.ruleName == .magicNumber }
        #expect(magicIssues.isEmpty)
    }

    @Test func testStrictThresholdDetectsSmallRepeatedNumbers() throws {
        let visitor = createStrictVisitor()

        let sourceCode = """
        struct TestView: View {
            var body: some View {
                Text("Hello")
                    .padding(5)
                    .padding(5)
            }
        }
        """

        let sourceFile = Parser.parse(source: sourceCode)
        visitor.walk(sourceFile)

        // 5 meets the strict threshold of 5, and it's repeated
        let magicIssues = visitor.detectedIssues.filter { $0.ruleName == .magicNumber }
        #expect(magicIssues.count == 2)
    }

    // MARK: - Characterization

    @Test func testMagicNumberDetectionCharacterization() throws {
        let visitor = createVisitor()
        let sourceCode = """
        struct TestView: View {
            var body: some View { Text("Hello").padding(16) }
        }
        """
        let sourceFile = Parser.parse(source: sourceCode)
        visitor.walk(sourceFile)
        // Single-use 16 should not fire
        let magicIssues = visitor.detectedIssues.filter { $0.ruleName == .magicNumber }
        #expect(magicIssues.isEmpty)
    }
}
