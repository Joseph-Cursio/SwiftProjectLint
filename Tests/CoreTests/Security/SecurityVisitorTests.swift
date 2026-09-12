@testable import Core
import Foundation
import SwiftParser
@testable import SwiftProjectLintRules
import SwiftSyntax
import Testing

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

    @Test func testHardcodedSecretDetection() {
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

    @Test func testDoesNotFlagNonSecretKeySuffixVariables() {
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

    @Test func testStillFlagsCompoundSecretKeyVariables() {
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

    @Test func testFlagsJWTToken() {
        let source = """
        let authHeader = "eyJhbGciOiJIUzI1NiJ9.eyJzdWIiOiIxMjM0NTY3ODkwIn0.dozjgNryP4J3jVmNHl0w5N_XgL0n3I9PlFUP0THsR8U"
        """
        let issues = secretIssues(source)
        #expect(issues.count == 1)
        #expect(issues.first?.message.contains("JWT") == true)
    }

    // MARK: - Known API key prefix detection

    @Test func testFlagsOpenAIKey() {
        let source = """
        let config = "sk-proj-abc123def456ghi789"
        """
        let issues = secretIssues(source)
        #expect(issues.count == 1)
        #expect(issues.first?.message.contains("sk-") == true)
    }

    @Test func testFlagsGitHubToken() {
        let source = """
        let ghToken = "ghp_1234567890abcdef1234567890abcdef12345678"
        """
        let issues = secretIssues(source)
        // Flagged by keyword ("token") AND prefix ("ghp_")
        #expect(issues.count >= 1)
    }

    @Test func testFlagsAWSAccessKey() {
        let source = """
        let awsKey = "AKIAIOSFODNN7EXAMPLE"
        """
        let issues = secretIssues(source)
        #expect(issues.count >= 1)
    }

    @Test func testFlagsSlackToken() {
        let source = "let webhook = \"xoxb-fake\""
        let issues = secretIssues(source)
        #expect(issues.count == 1)
        #expect(issues.first?.message.contains("xoxb-") == true)
    }

    // MARK: - Entropy-based detection

    @Test func testFlagsHighEntropySecretKey() {
        let source = """
        let signingKey = "aB3cD4eF5gH6iJ7kL8mN9oP0qR1sT2u"
        """
        let issues = secretIssues(source)
        #expect(issues.count >= 1)
    }

    @Test func testNoFlagForLowEntropyKey() {
        let source = """
        let cacheKey = "aaaaaaaaaaaaaaaaaaaaa"
        """
        let issues = secretIssues(source)
        #expect(issues.isEmpty)
    }

    // MARK: - Suppression

    @Test func testSuppressesPlaceholderValues() {
        let source = """
        let apiKey = "YOUR_API_KEY_HERE"
        let token = "REPLACE_ME"
        """
        let issues = secretIssues(source)
        #expect(issues.isEmpty)
    }

    @Test func testSuppressesInsideIfDebug() {
        let source = """
        #if DEBUG
        let apiKey = "test-key-12345"
        #endif
        """
        let issues = secretIssues(source)
        #expect(issues.isEmpty)
    }

    @Test func testSuppressesShortValuesInTestFiles() {
        let source = """
        let token = "mock-token"
        """
        let issues = secretIssues(source, filePath: "Tests/SecurityTests.swift")
        #expect(issues.isEmpty)
    }

    // MARK: - Unsafe URL construction (unchanged)

    @Test func testUnsafeURLConstruction() {
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

    // MARK: - Interpolation is not a secret (#111)

    /// **A literal with interpolation has no fixed value, and a secret is a fixed value.**
    ///
    /// `let token = "<<<\\(tokens.count)>>>"` is a glob placeholder in a brace-expansion parser —
    /// `<<<0>>>`, `<<<1>>>` — and `token` is the parser's vocabulary, not a credential. It was the
    /// **only error** in a 2,880-finding run, so under `--threshold error` this single false
    /// positive decided the exit code: 2 before, 0 after.
    @Test
    func ignoresInterpolatedValue() {
        let issues = secretIssues("""
        func expand(_ paths: inout String) {
            let token = "<<<\\(tokens.count)>>>"
            tokens[token] = "x"
        }
        """)
        #expect(issues.isEmpty)
    }

    /// The name-keyword arm reports without consulting the value at all, so the interpolation
    /// check has to come before it — and before `extractStringValue`, which drops interpolated
    /// segments and would hand the later heuristics `"<<<>>>"`, a string that was never written.
    @Test
    func ignoresInterpolationEvenWhenTheNameIsASecretKeyword() {
        for name in ["apiKey", "password", "secretKey", "accessToken"] {
            let issues = secretIssues("""
            func make(_ count: Int) -> String {
                let \(name) = "prefix-\\(count)"
                return \(name)
            }
            """)
            #expect(issues.isEmpty, "\(name) holds an interpolated value")
        }
    }

    @Test
    func ignoresEmptyStringValue() {
        let issues = secretIssues("""
        struct Config {
            let secret = ""
        }
        """)
        #expect(issues.isEmpty)
    }

    /// **The reason there is no minimum-length guard**, which the issue also proposed. A real
    /// hardcoded password can be short: `"hunter2"` is 7 characters and so is `"<<<0>>>"`, so
    /// length cannot separate them. Interpolation can.
    @Test
    func stillFlagsAShortLiteralPassword() {
        let issues = secretIssues("""
        struct Config {
            let password = "hunter2"
        }
        """)
        #expect(issues.count == 1)
    }

    /// The value is a made-up token rather than a real-shaped provider key. An earlier draft used
    /// Stripe's documentation example, and **GitHub Push Protection rejected the push of this very
    /// file** — a hardcoded-secret test tripping a hardcoded-secret scanner. The name-keyword arm
    /// fires on `apiKey` alone, so the prefix was never needed to exercise it.
    @Test
    func stillFlagsAFixedCredential() {
        let issues = secretIssues("""
        struct Config {
            let apiKey = "Zm9vYmFyLWJheg1234567890"
        }
        """)
        #expect(issues.count == 1)
    }

    /// **A credential is never a substring of the name that holds it.** `token`, `key`, `secret`
    /// and `auth` are ordinary words in a parser or a lexer, and the name-keyword arm reports
    /// without consulting the value at all — so `hashToken = "hash"`, the token identifying a hash
    /// function, was an `error` in SwiftInferProperties.
    @Test
    func ignoresAValueThatEchoesItsOwnName() {
        for (name, value) in [("hashToken", "hash"), ("authToken", "auth"), ("secretKey", "key")] {
            let issues = secretIssues("""
            struct Config {
                let \(name) = "\(value)"
            }
            """)
            #expect(issues.isEmpty, "\(name) = \"\(value)\" is vocabulary, not a credential")
        }
    }

    /// The guard is narrow on purpose: `hunter2` appears nowhere in `password`, so it is still
    /// reported. That is the discrimination a length or wordiness test could not make.
    @Test
    func stillFlagsAValueUnrelatedToItsName() {
        let issues = secretIssues("""
        struct Config {
            let password = "hunter2"
            let apiKey = "Zm9vYmFyLWJheg1234567890"
        }
        """)
        #expect(issues.count == 2)
    }
}
