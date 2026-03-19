import Testing
import Foundation
import SwiftParser
import SwiftSyntax
@testable import SwiftProjectLintCore

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

        let sourceCode = """
        public struct TestView: View {
            let spacing: CGFloat = 16

            var body: some View {
                Text("This is a hardcoded string that should be localized")
                    .padding(16)
            }
        }
        """

        let sourceFile = Parser.parse(source: sourceCode)
        visitor.walk(sourceFile)

        let magicNumberIssues = visitor.detectedIssues.filter { $0.ruleName == .magicNumber }
        #expect(magicNumberIssues.count == 2)

        let hardcodedIssues = visitor.detectedIssues.filter { $0.ruleName == .hardcodedStrings }
        #expect(hardcodedIssues.count == 1)

        let documentationIssues = visitor.detectedIssues.filter { $0.ruleName == .missingDocumentation }
        #expect(documentationIssues.count == 1)
    }

    @Test func testEdgeCaseCharacterization() throws {
        let visitor = createVisitor()

        let sourceCode = """
        public struct TestView: View {
            let spacing: CGFloat = 16

            var body: some View {
                Text("This is a hardcoded string that should be localized")
                    .padding(16)
            }
        }
        """

        let sourceFile = Parser.parse(source: sourceCode)
        visitor.walk(sourceFile)

        let magicNumberIssues = visitor.detectedIssues.filter { $0.ruleName == .magicNumber }
        #expect(magicNumberIssues.count == 2)

        let hardcodedIssues = visitor.detectedIssues.filter { $0.ruleName == .hardcodedStrings }
        #expect(hardcodedIssues.count == 1)

        let documentationIssues = visitor.detectedIssues.filter { $0.ruleName == .missingDocumentation }
        #expect(documentationIssues.count == 1)
    }

    @Test func testConfigurationCharacterization() throws {
        let visitor = createStrictVisitor()

        let sourceCode = """
        public struct TestView: View {
            let spacing: CGFloat = 16

            var body: some View {
                Text("This is a hardcoded string that should be localized")
                    .padding(16)
            }
        }
        """

        let sourceFile = Parser.parse(source: sourceCode)
        visitor.walk(sourceFile)

        let magicNumberIssues = visitor.detectedIssues.filter { $0.ruleName == .magicNumber }
        #expect(magicNumberIssues.count >= 2)

        let hardcodedIssues = visitor.detectedIssues.filter { $0.ruleName == .hardcodedStrings }
        #expect(hardcodedIssues.count >= 1)

        let documentationIssues = visitor.detectedIssues.filter { $0.ruleName == .missingDocumentation }
        #expect(documentationIssues.count >= 1)
    }

    // MARK: - Configuration Tests

    @Test func testConfigurationDefault() throws {
        let config = CodeQualityVisitor.Configuration.default
        #expect(config.magicNumberThreshold == 10)
        #expect(config.checkPublicAPIsOnly)
    }

    @Test func testConfigurationStrict() throws {
        let config = CodeQualityVisitor.Configuration.strict
        #expect(config.magicNumberThreshold == 5)
        #expect(!config.checkPublicAPIsOnly)
    }

    // MARK: - Documentation Tests

    @Test func testMissingDocumentationDetection() throws {
        let visitor = createVisitor()

        let sourceCode = """
        public struct UndocumentedView: View {
            public func doSomething() {}
            public func doAnother() {}
            public var body: some View {
                EmptyView()
            }
            public func doThird() {}
        }
        """

        let sourceFile = Parser.parse(source: sourceCode)
        visitor.walk(sourceFile)

        let docIssues = visitor.detectedIssues.filter { $0.ruleName == .missingDocumentation }
        #expect(docIssues.count == 4)
    }

    @Test func testDocumentedAPIsNoDetection() throws {
        let visitor = createVisitor()

        let sourceCode = """
        /// A documented struct
        public struct DocumentedView: View {
            /// Documented function
            public func doSomething() {}
            public var body: some View {
                EmptyView()
            }
        }
        """

        let sourceFile = Parser.parse(source: sourceCode)
        visitor.walk(sourceFile)

        let docIssues = visitor.detectedIssues.filter { $0.ruleName == .missingDocumentation }
        #expect(docIssues.isEmpty)
    }

    @Test func testPrivateAPIsNoDetection() throws {
        let visitor = createVisitor()

        let sourceCode = """
        struct InternalView: View {
            func doSomething() {}
            var body: some View {
                EmptyView()
            }
        }
        """

        let sourceFile = Parser.parse(source: sourceCode)
        visitor.walk(sourceFile)

        let docIssues = visitor.detectedIssues.filter { $0.ruleName == .missingDocumentation }
        #expect(docIssues.isEmpty)
    }
}
