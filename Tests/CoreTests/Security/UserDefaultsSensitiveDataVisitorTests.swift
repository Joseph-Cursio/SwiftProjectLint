import Testing
import Foundation
import SwiftParser
import SwiftSyntax
@testable import Core
@testable import SwiftProjectLintRules

@Suite
struct UserDefaultsSensitiveDataVisitorTests {

    // MARK: - UserDefaults.standard.set

    @Test func testFlagsPasswordKey() {
        let source = """
        UserDefaults.standard.set(value, forKey: "password")
        """
        let issues = issues(for: source)
        #expect(issues.count == 1)
    }

    @Test func testFlagsTokenKey() {
        let source = """
        UserDefaults.standard.set(token, forKey: "authToken")
        """
        let issues = issues(for: source)
        #expect(issues.count == 1)
    }

    @Test func testFlagsSecretKey() {
        let source = """
        UserDefaults.standard.set(val, forKey: "clientSecret")
        """
        let issues = issues(for: source)
        #expect(issues.count == 1)
    }

    @Test func testFlagsApiKeyExactMatch() {
        let source = """
        UserDefaults.standard.set(key, forKey: "apiKey")
        """
        let issues = issues(for: source)
        #expect(issues.count == 1)
    }

    @Test func testFlagsAccessTokenExactMatch() {
        let source = """
        UserDefaults.standard.set(t, forKey: "accessToken")
        """
        let issues = issues(for: source)
        #expect(issues.count == 1)
    }

    @Test func testFlagsRefreshTokenExactMatch() {
        let source = """
        UserDefaults.standard.set(t, forKey: "refreshToken")
        """
        let issues = issues(for: source)
        #expect(issues.count == 1)
    }

    @Test func testFlagsSnakeCaseApiKey() {
        let source = """
        UserDefaults.standard.set(key, forKey: "api_key")
        """
        let issues = issues(for: source)
        #expect(issues.count == 1)
    }

    @Test func testFlagsUserPassword() {
        let source = """
        UserDefaults.standard.set(pwd, forKey: "userPassword")
        """
        let issues = issues(for: source)
        #expect(issues.count == 1)
    }

    // MARK: - UserDefaults(suiteName:).set

    @Test func testFlagsSuiteNameVariant() {
        let source = """
        UserDefaults(suiteName: "com.example").set(token, forKey: "token")
        """
        let issues = issues(for: source)
        #expect(issues.count == 1)
    }

    // MARK: - @AppStorage

    @Test func testFlagsAppStoragePassword() {
        let source = """
        @AppStorage("userPassword") var password: String = ""
        """
        let issues = issues(for: source)
        #expect(issues.count == 1)
    }

    @Test func testFlagsAppStorageToken() {
        let source = """
        @AppStorage("authToken") var token: String = ""
        """
        let issues = issues(for: source)
        #expect(issues.count == 1)
    }

    @Test func testFlagsAppStorageApiKey() {
        let source = """
        @AppStorage("apiKey") var key: String = ""
        """
        let issues = issues(for: source)
        #expect(issues.count == 1)
    }

    // MARK: - Suppression: boolean/verb prefixes

    @Test func testSuppressesHasPrefix() {
        let source = """
        UserDefaults.standard.set(true, forKey: "hasSeenAuth")
        """
        let issues = issues(for: source)
        #expect(issues.isEmpty)
    }

    @Test func testSuppressesIsPrefix() {
        let source = """
        UserDefaults.standard.set(true, forKey: "isTokenExpired")
        """
        let issues = issues(for: source)
        #expect(issues.isEmpty)
    }

    @Test func testSuppressesShowPrefix() {
        let source = """
        @AppStorage("showOnboardingToken") var show: Bool = false
        """
        let issues = issues(for: source)
        #expect(issues.isEmpty)
    }

    @Test func testSuppressesDidPrefix() {
        let source = """
        UserDefaults.standard.set(true, forKey: "didCompleteAuth")
        """
        let issues = issues(for: source)
        #expect(issues.isEmpty)
    }

    // MARK: - Suppression: non-sensitive qualifiers

    @Test func testSuppressesTokenCount() {
        let source = """
        UserDefaults.standard.set(3, forKey: "tokenCount")
        """
        let issues = issues(for: source)
        #expect(issues.isEmpty)
    }

    @Test func testSuppressesPasswordField() {
        let source = """
        UserDefaults.standard.set("placeholder", forKey: "passwordField")
        """
        let issues = issues(for: source)
        #expect(issues.isEmpty)
    }

    @Test func testSuppressesAuthScreen() {
        let source = """
        UserDefaults.standard.set("login", forKey: "authScreen")
        """
        let issues = issues(for: source)
        #expect(issues.isEmpty)
    }

    // MARK: - Non-sensitive keys: no flag

    @Test func testDoesNotFlagUnrelatedKey() {
        let source = """
        UserDefaults.standard.set("value", forKey: "userName")
        """
        let issues = issues(for: source)
        #expect(issues.isEmpty)
    }

    @Test func testDoesNotFlagOnboardingKey() {
        let source = """
        UserDefaults.standard.set(true, forKey: "hasCompletedOnboarding")
        """
        let issues = issues(for: source)
        #expect(issues.isEmpty)
    }

    @Test func testDoesNotFlagAppStorageNonSensitive() {
        let source = """
        @AppStorage("selectedTheme") var theme: String = "light"
        """
        let issues = issues(for: source)
        #expect(issues.isEmpty)
    }

    @Test func testDoesNotFlagNonUserDefaultsSetCall() {
        let source = """
        myCache.set("value", forKey: "password")
        """
        let issues = issues(for: source)
        #expect(issues.isEmpty)
    }

    // MARK: - Multiple issues in one file

    @Test func testMultipleSensitiveKeys() {
        let source = """
        UserDefaults.standard.set(pwd, forKey: "password")
        UserDefaults.standard.set(tok, forKey: "token")
        UserDefaults.standard.set(3, forKey: "tokenCount")
        @AppStorage("apiKey") var key: String = ""
        """
        let issues = issues(for: source)
        #expect(issues.count == 3)
    }

    // MARK: - Helpers

    private func issues(for source: String) -> [LintIssue] {
        let sourceFile = Parser.parse(source: source)
        let visitor = UserDefaultsSensitiveDataVisitor(patternCategory: .security)
        visitor.setFilePath("TestFile.swift")
        visitor.walk(sourceFile)
        return visitor.detectedIssues
    }
}
