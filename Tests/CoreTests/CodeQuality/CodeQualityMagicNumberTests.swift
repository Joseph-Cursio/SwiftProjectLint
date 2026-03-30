import Testing
import Foundation
import SwiftParser
import SwiftSyntax
@testable import Core
@testable import SwiftProjectLintRules

struct CodeQualityMagicNumberTests {

    // MARK: - Test Helper Methods

    private func createVisitor() -> MagicNumberVisitor {
        let visitor = MagicNumberVisitor(patternCategory: .codeQuality)
        visitor.setFilePath("TestFile.swift")
        return visitor
    }

    private func createStrictVisitor() -> MagicNumberVisitor {
        let visitor = MagicNumberVisitor(patternCategory: .codeQuality, configuration: .strict)
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
                    .tag(16)
                    .onAppear { process(count: 16) }
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
            let threshold: CGFloat = 12.0
            var body: some View {
                Text("Hello")
                    .tag(12.0)
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
                    .tag(16)
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
                    .tag(5)
                    .onAppear { process(count: 5) }
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
                    .tag(5)
                    .onAppear { process(count: 5) }
            }
        }
        """

        let sourceFile = Parser.parse(source: sourceCode)
        visitor.walk(sourceFile)

        // 5 meets the strict threshold of 5, and it's repeated
        let magicIssues = visitor.detectedIssues.filter { $0.ruleName == .magicNumber }
        #expect(magicIssues.count == 2)
    }

    // MARK: - Layout Modifier Exclusion

    @Test func testLayoutModifierNumbersNotDetected() throws {
        let visitor = createVisitor()

        let sourceCode = """
        struct TestView: View {
            var body: some View {
                Text("Hello")
                    .padding(16)
                    .frame(width: 16, height: 16)
                    .cornerRadius(16)
                    .opacity(0.5)
            }
        }
        """

        let sourceFile = Parser.parse(source: sourceCode)
        visitor.walk(sourceFile)

        let magicIssues = visitor.detectedIssues.filter { $0.ruleName == .magicNumber }
        #expect(magicIssues.isEmpty)
    }

    @Test func testLayoutArgLabelsNotDetected() throws {
        let visitor = createVisitor()

        let sourceCode = """
        struct TestView: View {
            var body: some View {
                Text("Hello")
                    .customModifier(width: 100, height: 100)
            }
        }
        """

        let sourceFile = Parser.parse(source: sourceCode)
        visitor.walk(sourceFile)

        let magicIssues = visitor.detectedIssues.filter { $0.ruleName == .magicNumber }
        #expect(magicIssues.isEmpty)
    }

    @Test func testNonLayoutRepeatedNumberStillDetected() throws {
        let visitor = createVisitor()

        let sourceCode = """
        struct TestView: View {
            let limit = 100
            var body: some View {
                Text("Hello")
                    .tag(100)
            }
        }
        """

        let sourceFile = Parser.parse(source: sourceCode)
        visitor.walk(sourceFile)

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
        // Single-use 16 in layout context should not fire
        let magicIssues = visitor.detectedIssues.filter { $0.ruleName == .magicNumber }
        #expect(magicIssues.isEmpty)
    }
}
