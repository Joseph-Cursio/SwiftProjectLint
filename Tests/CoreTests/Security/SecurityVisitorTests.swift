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
        // Without a converter every finding reports line 1, and a test cannot tell which call it
        // came from.
        visitor.setSourceLocationConverter(SourceLocationConverter(fileName: filePath, tree: sourceFile))
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

    // MARK: - Unsafe URL construction

    private func unsafeURLIssues(_ source: String) -> [LintIssue] {
        analyzeSource(source).filter { $0.ruleName == .unsafeURL }
    }

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

    /// A file path is not parsed as a URL, so interpolating into one cannot change a scheme,
    /// host or query.
    @Test func testFilePathURLIsNotUnsafe() {
        let source = """
        let scratch = URL(fileURLWithPath: "/tmp/run-\\(UUID().uuidString)")
        let file = URL(filePath: "/tmp/\\(name).swift")
        let joined = URL(fileURLWithPath: base + "/Sources")
        """
        let urlIssues = analyzeSource(source).filter { $0.ruleName == .unsafeURL }
        #expect(urlIssues.isEmpty)
    }

    // MARK: - Unsafe URL: a `+` is an operator, not a character

    /// **A `+` inside a constant is part of the URL.** The rule used to search the literal's
    /// source text for `+` and `\(`, so an international phone number and a form-encoded space
    /// were reported as "string interpolation" — and so was a raw string, whose `\(` is two
    /// characters of text, not an interpolation.
    @Test func testPlusInsideAConstantURLIsNotUnsafe() {
        let source = """
        let phone = URL(string: "tel:+15551234567")
        let search = URL(string: "https://example.com/search?q=swift+ui")
        let raw = URL(string: #"https://example.com/\\(literally)"#)
        """
        #expect(unsafeURLIssues(source).isEmpty)
    }

    /// **Concatenation is a sequence expression, not a literal**, so it was never examined: the
    /// `+` search ran only when the argument was a string literal. A chain of `+` is the
    /// `String` that `URL(string:)` takes, so `base + path` is reported without a literal in it.
    @Test func testConcatenationIsUnsafe() {
        let source = """
        let joined = URL(string: base + path)
        let query = URL(string: "https://example.com/api?q=" + query)
        let several = URL(string: base + "/users/" + userID + "?expand=" + fields)
        """
        let issues = unsafeURLIssues(source)
        #expect(issues.map(\.lineNumber) == [1, 2, 3])
        #expect(issues.allSatisfy { $0.message == "Unsafe URL construction with string concatenation" })
        #expect(issues.allSatisfy { $0.severity == .warning })
    }

    /// The parser leaves a parenthesised operand as a tuple holding its own sequence, and an
    /// interpolated literal inside a chain still makes the chain a concatenation.
    @Test func testParenthesisedConcatenationIsUnsafe() {
        let source = """
        let nested = URL(string: base + ("/" + path))
        let wrapped = URL(string: ("https://example.com/" + path))
        let grouped = URL(string: (scheme + host) + path)
        let segment = URL(string: "https://example.com/" + "\\(path)")
        """
        let issues = unsafeURLIssues(source)
        #expect(issues.map(\.lineNumber) == [1, 2, 3, 4])
        #expect(issues.allSatisfy { $0.message.hasSuffix("string concatenation") })
    }

    /// Each finding names what it found: an interpolated literal is not called a concatenation,
    /// and parentheses around one change nothing.
    @Test func testInterpolationKeepsItsOwnMessage() {
        let source = """
        let interpolated = URL(string: ("https://example.com/\\(path)"))
        """
        let issues = unsafeURLIssues(source)
        #expect(issues.count == 1)
        #expect(issues.first?.message == "Unsafe URL construction with string interpolation")
    }

    /// Literals joined with `+` are one constant split across lines — nothing in them is computed
    /// at run time, so there is nothing to encode.
    @Test func testConcatenatedConstantsAreNotUnsafe() {
        let source = """
        let long = URL(string: "https://example.com/" + "v2/users")
        let split = URL(string: "https://example.com/"
            + "v2/"
            + ("users?page=1"))
        """
        #expect(unsafeURLIssues(source).isEmpty)
    }

    /// **Arithmetic is not concatenation.** A `+` inside a subscript, a call or another argument
    /// is not one of the `string:` argument's own operators, and a `+` mixed with other operators
    /// is concatenation only when a string literal is among its operands — in a ternary's
    /// condition it is arithmetic.
    @Test func testArithmeticIsNotConcatenation() {
        let source = """
        let page = URL(string: pages[index + 1])
        let built = URL(string: path(for: page + 1))
        let relative = URL(string: "https://example.com/", relativeTo: bases[offset + 1])
        let chosen = URL(string: index + 1 < count ? next : last)
        """
        #expect(unsafeURLIssues(source).isEmpty)
    }

    /// A mixed expression whose operands include a string literal is text being joined, whatever
    /// else it does: `??` binds looser than `+`, so the fallback is the concatenation.
    @Test func testMixedOperatorsWithALiteralAreConcatenation() {
        let source = """
        let fallback = URL(string: configured ?? "https://example.com/" + path)
        """
        let issues = unsafeURLIssues(source)
        #expect(issues.count == 1)
        #expect(issues.first?.message == "Unsafe URL construction with string concatenation")
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

    /// **Separators are spelling, not meaning.** A Keychain account is written `encryption_key`
    /// and the property holding it `encryptionKeyAccount`; comparing the two verbatim missed the
    /// pair and left an `error` on MacCloud_client_MacOS — on the *correct* pattern, since the
    /// identifier a secret is stored UNDER is not the secret.
    @Test
    func ignoresASeparatorSpellingOfItsOwnName() {
        let issues = secretIssues("""
        class SecurityManager {
            let encryptionKeyAccount = "encryption_key"
            let keychainAccount = "auth_token"
        }
        """)
        #expect(issues.isEmpty)
    }
}
