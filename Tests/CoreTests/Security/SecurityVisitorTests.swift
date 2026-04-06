import Testing
import Foundation
import SwiftParser
import SwiftSyntax
@testable import Core
@testable import SwiftProjectLintRules

struct SecurityVisitorTests {

    private func analyzeSource(
        _ source: String,
        filePath: String = "TestFile.swift"
    ) -> [LintIssue] {
        let sourceFile = Parser.parse(source: source)
        let visitor = SecurityVisitor(patternCategory: .security)
        visitor.setFilePath(filePath)
        visitor.walk(sourceFile)
        return visitor.detectedIssues
    }

    private func secretIssues(_ source: String, filePath: String = "TestFile.swift") -> [LintIssue] {
        analyzeSource(source, filePath: filePath).filter { $0.ruleName == .hardcodedSecret }
    }

    // MARK: - Original keyword-based detection

    @Test func testHardcodedSecretDetection() throws {
        let source = """
        let apiKey = "12345"
        let secret = "topsecret"
        let password = "hunter2"
        let token = "abcdef"
        let notASecret = 42
        """
        let issues = secretIssues(source)
        #expect(issues.count == 4)
        #expect(issues.allSatisfy { $0.severity == .error })
    }

    @Test func testDoesNotFlagNonSecretKeySuffixVariables() throws {
        let source = """
        let onboardingKey = "com.myapp.hasCompletedOnboarding"
        let recentWorkspacesKey = "MyApp.recentWorkspaces"
        let sortKey = "name"
        let cacheKey = "user_profile"
        let primaryKey = "id"
        """
        let issues = secretIssues(source)
        #expect(issues.isEmpty)
    }

    @Test func testStillFlagsCompoundSecretKeyVariables() throws {
        let source = """
        let apiKey = "sk-12345"
        let secretKey = "abc123"
        let authKey = "bearer-token"
        let privateKey = "-----BEGIN RSA-----"
        let encryptionKey = "aes256key"
        let clientSecret = "cs_live_xyz"
        let credential = "user:pass"
        """
        let issues = secretIssues(source)
        #expect(issues.count == 7)
    }

    // MARK: - JWT detection

    @Test func testFlagsJWTToken() throws {
        let source = """
        let authHeader = "eyJhbGciOiJIUzI1NiJ9.eyJzdWIiOiIxMjM0NTY3ODkwIn0.dozjgNryP4J3jVmNHl0w5N_XgL0n3I9PlFUP0THsR8U"
        """
        let issues = secretIssues(source)
        #expect(issues.count == 1)
        #expect(issues.first?.message.contains("JWT") == true)
    }

    // MARK: - Known API key prefix detection

    @Test func testFlagsOpenAIKey() throws {
        let source = """
        let config = "sk-proj-abc123def456ghi789"
        """
        let issues = secretIssues(source)
        #expect(issues.count == 1)
        #expect(issues.first?.message.contains("sk-") == true)
    }

    @Test func testFlagsGitHubToken() throws {
        let source = """
        let ghToken = "ghp_1234567890abcdef1234567890abcdef12345678"
        """
        let issues = secretIssues(source)
        // Flagged by keyword ("token") AND prefix ("ghp_")
        #expect(issues.count >= 1)
    }

    @Test func testFlagsAWSAccessKey() throws {
        let source = """
        let awsKey = "AKIAIOSFODNN7EXAMPLE"
        """
        let issues = secretIssues(source)
        #expect(issues.count >= 1)
    }

    @Test func testFlagsSlackToken() throws {
        let source = "let webhook = \"xoxb-fake\""
        let issues = secretIssues(source)
        #expect(issues.count == 1)
        #expect(issues.first?.message.contains("xoxb-") == true)
    }

    // MARK: - Entropy-based detection

    @Test func testFlagsHighEntropySecretKey() throws {
        let source = """
        let signingKey = "aB3cD4eF5gH6iJ7kL8mN9oP0qR1sT2u"
        """
        let issues = secretIssues(source)
        #expect(issues.count >= 1)
    }

    @Test func testNoFlagForLowEntropyKey() throws {
        let source = """
        let cacheKey = "aaaaaaaaaaaaaaaaaaaaa"
        """
        let issues = secretIssues(source)
        #expect(issues.isEmpty)
    }

    // MARK: - Suppression

    @Test func testSuppressesPlaceholderValues() throws {
        let source = """
        let apiKey = "YOUR_API_KEY_HERE"
        let token = "REPLACE_ME"
        """
        let issues = secretIssues(source)
        #expect(issues.isEmpty)
    }

    @Test func testSuppressesInsideIfDebug() throws {
        let source = """
        #if DEBUG
        let apiKey = "test-key-12345"
        #endif
        """
        let issues = secretIssues(source)
        #expect(issues.isEmpty)
    }

    @Test func testSuppressesShortValuesInTestFiles() throws {
        let source = """
        let token = "mock-token"
        """
        let issues = secretIssues(source, filePath: "Tests/SecurityTests.swift")
        #expect(issues.isEmpty)
    }

    // MARK: - Unsafe URL construction (unchanged)

    @Test func testUnsafeURLConstruction() throws {
        let source = """
        let token = "abc123"
        let userId = "user456"
        let unsafeURL1 = URL(string: "https://example.com/api?token=\\(token)")
        let unsafeURL2 = URL(string: "https://example.com/api?user=\\(userId)")
        let safeURL = URL(string: "https://example.com/api")
        """
        let allIssues = analyzeSource(source)
        let urlIssues = allIssues.filter {
            $0.message.localizedCaseInsensitiveContains("string interpolation")
                && $0.severity == .warning
        }
        #expect(urlIssues.count == 2)

        let secretIss = allIssues.filter { $0.ruleName == .hardcodedSecret }
        #expect(secretIss.count == 1) // "token" keyword match
    }
}
