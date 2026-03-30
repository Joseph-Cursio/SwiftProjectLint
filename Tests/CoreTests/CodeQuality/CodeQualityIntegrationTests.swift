import Testing
import Foundation
import SwiftParser
import SwiftSyntax
@testable import Core
@testable import SwiftProjectLintRules

struct CodeQualityIntegrationTests {

    // MARK: - Test Helper Methods

    /// Runs all three code quality visitors over the given source and returns combined issues.
    private func detect(_ sourceCode: String, filePath: String = "TestFile.swift") -> [LintIssue] {
        let magicVisitor = MagicNumberVisitor(patternCategory: .codeQuality)
        magicVisitor.setFilePath(filePath)
        let stringVisitor = HardcodedStringVisitor(patternCategory: .codeQuality)
        stringVisitor.setFilePath(filePath)
        let docVisitor = DocumentationVisitor(patternCategory: .codeQuality)
        docVisitor.setFilePath(filePath)
        let sourceFile = Parser.parse(source: sourceCode)
        magicVisitor.walk(sourceFile)
        stringVisitor.walk(sourceFile)
        docVisitor.walk(sourceFile)
        return magicVisitor.detectedIssues + stringVisitor.detectedIssues + docVisitor.detectedIssues
    }

    // MARK: - Integration Tests

    @Test func testMultipleCodeQualityIssues() throws {
        let sourceCode = """
        public struct TestView: View {
            let retryCount: Int = 16
            let maxAttempts: Int = 16

            var body: some View {
                Text("This is a hardcoded string that should be localized")
            }
        }
        """

        let issues = detect(sourceCode)

        let magicNumberIssues = issues.filter { $0.ruleName == .magicNumber }
        #expect(magicNumberIssues.count == 2)

        let hardcodedIssues = issues.filter { $0.ruleName == .hardcodedStrings }
        #expect(hardcodedIssues.count == 1)

        let documentationIssues = issues.filter { $0.ruleName == .missingDocumentation }
        #expect(documentationIssues.count == 1)
    }

    @Test func testConfigurationCharacterization() throws {
        let magicVisitor = MagicNumberVisitor(patternCategory: .codeQuality, configuration: .strict)
        magicVisitor.setFilePath("TestFile.swift")
        let stringVisitor = HardcodedStringVisitor(patternCategory: .codeQuality)
        stringVisitor.setFilePath("TestFile.swift")
        let docVisitor = DocumentationVisitor(patternCategory: .codeQuality, configuration: .strict)
        docVisitor.setFilePath("TestFile.swift")

        let sourceCode = """
        public struct TestView: View {
            let retryCount: Int = 16
            let maxAttempts: Int = 16

            var body: some View {
                Text("This is a hardcoded string that should be localized")
            }
        }
        """

        let sourceFile = Parser.parse(source: sourceCode)
        magicVisitor.walk(sourceFile)
        stringVisitor.walk(sourceFile)
        docVisitor.walk(sourceFile)
        let issues = magicVisitor.detectedIssues + stringVisitor.detectedIssues + docVisitor.detectedIssues

        #expect(issues.filter { $0.ruleName == .magicNumber }.count >= 2)
        #expect(issues.filter { $0.ruleName == .hardcodedStrings }.count >= 1)
        #expect(issues.filter { $0.ruleName == .missingDocumentation }.count >= 1)
    }

    // MARK: - Configuration Tests

    @Test func testMagicNumberConfigurationDefault() {
        let config = MagicNumberVisitor.Configuration.default
        #expect(config.magicNumberThreshold == 10)
    }

    @Test func testMagicNumberConfigurationStrict() {
        let config = MagicNumberVisitor.Configuration.strict
        #expect(config.magicNumberThreshold == 5)
    }

    @Test func testDocumentationConfigurationDefault() {
        let config = DocumentationVisitor.Configuration.default
        #expect(config.checkPublicAPIsOnly)
    }

    @Test func testDocumentationConfigurationStrict() {
        let config = DocumentationVisitor.Configuration.strict
        #expect(config.checkPublicAPIsOnly == false)
    }

    // MARK: - Documentation Tests

    @Test func testMissingDocumentationDetection() throws {
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

        let issues = detect(sourceCode)
        let docIssues = issues.filter { $0.ruleName == .missingDocumentation }
        #expect(docIssues.count == 4)
    }

    @Test func testDocumentedAPIsNoDetection() throws {
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

        let issues = detect(sourceCode)
        let docIssues = issues.filter { $0.ruleName == .missingDocumentation }
        #expect(docIssues.isEmpty)
    }

    @Test func testPrivateAPIsNoDetection() throws {
        let sourceCode = """
        struct InternalView: View {
            func doSomething() {}
            var body: some View {
                EmptyView()
            }
        }
        """

        let issues = detect(sourceCode)
        let docIssues = issues.filter { $0.ruleName == .missingDocumentation }
        #expect(docIssues.isEmpty)
    }
}
