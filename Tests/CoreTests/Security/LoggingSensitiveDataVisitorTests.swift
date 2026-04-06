import Testing
import Foundation
import SwiftSyntax
import SwiftParser
@testable import Core
@testable import SwiftProjectLintRules

@Suite
struct LoggingSensitiveDataVisitorTests {

    // MARK: - Helper

    private func analyzeSource(
        _ source: String,
        filePath: String = "TestFile.swift"
    ) -> [LintIssue] {
        let visitor = LoggingSensitiveDataVisitor(patternCategory: .security)
        let syntax = Parser.parse(source: source)
        let converter = SourceLocationConverter(fileName: filePath, tree: syntax)
        visitor.setSourceLocationConverter(converter)
        visitor.setFilePath(filePath)
        visitor.walk(syntax)
        return visitor.detectedIssues
    }

    private func filteredIssues(_ source: String) -> [LintIssue] {
        analyzeSource(source).filter { $0.ruleName == .loggingSensitiveData }
    }

    // MARK: - Positive: flags sensitive data in logging

    @Test func testFlagsPrintWithToken() throws {
        let source = """
        func debug() {
            print("User token: \\(authToken)")
        }
        """
        let issues = filteredIssues(source)
        let issue = try #require(issues.first)
        #expect(issues.count == 1)
        #expect(issue.severity == .warning)
        #expect(issue.message.contains("authToken"))
    }

    @Test func testFlagsDebugPrintWithPassword() throws {
        let source = """
        func debug() {
            debugPrint(userPassword)
        }
        """
        let issues = filteredIssues(source)
        #expect(issues.count == 1)
        #expect(issues.first?.message.contains("userPassword") == true)
    }

    @Test func testFlagsNSLogWithSecret() throws {
        let source = """
        func debug() {
            NSLog("Secret: %@", clientSecret)
        }
        """
        let issues = filteredIssues(source)
        #expect(issues.count == 1)
    }

    @Test func testFlagsLoggerWithApiKey() throws {
        let source = """
        func debug() {
            logger.debug("Key = \\(apiKey)")
        }
        """
        let issues = filteredIssues(source)
        #expect(issues.count == 1)
        #expect(issues.first?.message.contains("apiKey") == true)
    }

    @Test func testFlagsBearerToken() throws {
        let source = """
        func debug() {
            print(bearerToken)
        }
        """
        let issues = filteredIssues(source)
        #expect(issues.count == 1)
    }

    @Test func testFlagsCreditCard() throws {
        let source = """
        func debug() {
            print("Card: \\(creditCardNumber)")
        }
        """
        let issues = filteredIssues(source)
        #expect(issues.count == 1)
    }

    // MARK: - Negative: should NOT flag

    @Test func testNoIssueForNonSensitiveVariable() throws {
        let source = """
        func debug() {
            print("User name: \\(userName)")
        }
        """
        let issues = filteredIssues(source)
        #expect(issues.isEmpty)
    }

    @Test func testNoIssueInsideIfDebug() throws {
        let source = """
        #if DEBUG
        func debug() {
            print("Token: \\(authToken)")
        }
        #endif
        """
        let issues = filteredIssues(source)
        #expect(issues.isEmpty)
    }

    @Test func testNoIssueWithPrivacyRedaction() throws {
        let source = """
        func debug() {
            logger.debug("Token: \\(token, privacy: .private)")
        }
        """
        let issues = filteredIssues(source)
        #expect(issues.isEmpty)
    }

    @Test func testNoIssueForUnrelatedCalls() throws {
        let source = """
        func work() {
            fetchData(from: url)
            process(result)
        }
        """
        let issues = filteredIssues(source)
        #expect(issues.isEmpty)
    }

    @Test func testNoIssueForLoggerWithNonSensitiveData() throws {
        let source = """
        func debug() {
            logger.info("Request count: \\(requestCount)")
        }
        """
        let issues = filteredIssues(source)
        #expect(issues.isEmpty)
    }
}
