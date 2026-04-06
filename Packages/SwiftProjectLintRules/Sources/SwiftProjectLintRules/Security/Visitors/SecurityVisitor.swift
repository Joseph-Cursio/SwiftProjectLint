import SwiftProjectLintModels
import SwiftProjectLintRegistry
import SwiftProjectLintVisitors
import Foundation
import SwiftSyntax

// MARK: - Security Visitor

/// A SwiftSyntax visitor that detects security issues in Swift code.
///
/// - Hardcoded secrets (apiKey, secret, password, token)
/// - JWT tokens (eyJ... pattern)
/// - Known API key prefixes (sk-, ghp_, AKIA, AIza, etc.)
/// - High-entropy strings assigned to sensitive variables
/// - Unsafe URL construction with string interpolation
class SecurityVisitor: BasePatternVisitor {
    private var currentFilePath: String = ""
    private var insideIfDebug = false

    // MARK: - Secret detection config

    private static let secretKeywords = [
        "apiKey", "apiSecret",
        "secretKey", "secret",
        "password", "passwd",
        "token",
        "authKey", "privateKey", "encryptionKey", "signingKey",
        "clientSecret", "accessKey", "secretAccessKey",
        "credential", "bearer", "passphrase"
    ]

    /// Known API key prefixes from common services.
    private static let knownKeyPrefixes = [
        "sk-",       // OpenAI, Stripe secret keys
        "pk_live_",  // Stripe publishable keys
        "pk_test_",
        "sk_live_",  // Stripe secret keys
        "sk_test_",
        "ghp_",      // GitHub personal access tokens
        "gho_",      // GitHub OAuth tokens
        "ghs_",      // GitHub server tokens
        "xoxb-",     // Slack bot tokens
        "xoxp-",     // Slack user tokens
        "AKIA",      // AWS access keys
        "AIza",      // Google API keys
        "SG."        // SendGrid
    ]

    /// Placeholder values that should not be flagged.
    private static let placeholderValues: Set<String> = [
        "YOUR_API_KEY_HERE", "REPLACE_ME", "TODO", "CHANGEME",
        "your-api-key", "your_api_key", "xxx", "placeholder",
        "INSERT_KEY_HERE", "API_KEY_HERE"
    ]

    /// Minimum entropy (bits per char) to consider a string a potential secret.
    private static let entropyThreshold: Double = 4.0

    /// Minimum string length for entropy-based detection.
    private static let minEntropyLength = 20

    required init(pattern: SyntaxPattern, viewMode: SyntaxTreeViewMode = .sourceAccurate) {
        super.init(pattern: pattern, viewMode: viewMode)
    }

    override func setFilePath(_ filePath: String) {
        super.setFilePath(filePath)
        self.currentFilePath = filePath
    }

    // MARK: - Track #if DEBUG

    override func visit(_ node: IfConfigDeclSyntax) -> SyntaxVisitorContinueKind {
        for clause in node.clauses {
            if let condition = clause.condition,
               condition.trimmedDescription == "DEBUG" {
                insideIfDebug = true
            }
        }
        return .visitChildren
    }

    override func visitPost(_ node: IfConfigDeclSyntax) {
        insideIfDebug = false
    }

    // MARK: - Variable declarations

    override func visit(_ node: VariableDeclSyntax) -> SyntaxVisitorContinueKind {
        guard insideIfDebug == false else { return .visitChildren }

        for binding in node.bindings {
            guard let pattern = binding.pattern.as(IdentifierPatternSyntax.self),
                  let initializer = binding.initializer,
                  let stringLiteral = initializer.value.as(StringLiteralExprSyntax.self) else {
                continue
            }

            let variableName = pattern.identifier.text
            let stringValue = extractStringValue(stringLiteral)

            // Skip placeholders
            if isPlaceholder(stringValue) { continue }

            // Skip test files with short mock-looking values
            if isTestFile() && stringValue.count < 20 { continue }

            // Check 1: Known keyword match (original behavior)
            if Self.secretKeywords.contains(where: {
                variableName.localizedCaseInsensitiveContains($0)
            }) {
                reportHardcodedSecret(variableName: variableName, node: node)
                continue
            }

            // Check 2: JWT token
            if looksLikeJWT(stringValue) {
                reportHardcodedSecret(
                    variableName: variableName,
                    detail: "JWT token",
                    node: node
                )
                continue
            }

            // Check 3: Known API key prefix
            if let prefix = matchesKnownKeyPrefix(stringValue) {
                reportHardcodedSecret(
                    variableName: variableName,
                    detail: "matches known key prefix '\(prefix)'",
                    node: node
                )
                continue
            }

            // Check 4: High-entropy string with sensitive variable name
            if isSensitiveVariableName(variableName),
               stringValue.count >= Self.minEntropyLength,
               shannonEntropy(stringValue) > Self.entropyThreshold {
                reportHardcodedSecret(
                    variableName: variableName,
                    detail: "high-entropy value",
                    node: node
                )
            }
        }
        return .visitChildren
    }

    // MARK: - Unsafe URL construction

    override func visit(_ node: FunctionCallExprSyntax) -> SyntaxVisitorContinueKind {
        if let calledExpr = node.calledExpression.as(DeclReferenceExprSyntax.self),
           calledExpr.baseName.text == "URL" {
            for argument in node.arguments {
                if let stringLiteral = argument.expression.as(StringLiteralExprSyntax.self) {
                    let urlString = stringLiteral.description
                    if urlString.contains("\\(") || urlString.contains("+") {
                        addIssue(
                            severity: .warning,
                            message: "Unsafe URL construction with string interpolation",
                            filePath: currentFilePath,
                            lineNumber: getLineNumber(for: Syntax(node)),
                            suggestion: "Use URLComponents to build URLs safely",
                            ruleName: .unsafeURL
                        )
                    }
                }
            }
        }
        return .visitChildren
    }

    // MARK: - Helpers

    private func reportHardcodedSecret(
        variableName: String,
        detail: String? = nil,
        node: VariableDeclSyntax
    ) {
        let detailSuffix = detail.map { " (\($0))" } ?? ""
        addIssue(
            severity: .error,
            message: "Hardcoded secret detected in '\(variableName)'\(detailSuffix)",
            filePath: currentFilePath,
            lineNumber: getLineNumber(for: Syntax(node)),
            suggestion: "Use secure key storage like Keychain or environment variables",
            ruleName: .hardcodedSecret
        )
    }

    private func extractStringValue(_ literal: StringLiteralExprSyntax) -> String {
        literal.segments.compactMap { segment -> String? in
            segment.as(StringSegmentSyntax.self)?.content.text
        }.joined()
    }

    private func isPlaceholder(_ value: String) -> Bool {
        let upper = value.uppercased()
        return Self.placeholderValues.contains { upper.contains($0.uppercased()) }
    }

    private func isTestFile() -> Bool {
        isTestOrFixtureFile()
    }

    private func looksLikeJWT(_ value: String) -> Bool {
        value.hasPrefix("eyJ")
            && value.split(separator: ".").count == 3
    }

    private func matchesKnownKeyPrefix(_ value: String) -> String? {
        Self.knownKeyPrefixes.first { value.hasPrefix($0) }
    }

    /// Sensitive name check for entropy-based detection.
    /// Uses compound keywords to avoid false positives on "cacheKey", "sortKey", etc.
    private func isSensitiveVariableName(_ name: String) -> Bool {
        let lower = name.lowercased()
        let compoundTerms = [
            "apikey", "secretkey", "authkey", "privatekey",
            "encryptionkey", "signingkey", "accesskey",
            "secret", "token", "password", "passwd",
            "credential", "bearer", "passphrase"
        ]
        return compoundTerms.contains { lower.contains($0) }
    }

    /// Computes Shannon entropy in bits per character.
    private func shannonEntropy(_ string: String) -> Double {
        guard string.isEmpty == false else { return 0 }
        var frequency: [Character: Int] = [:]
        for char in string {
            frequency[char, default: 0] += 1
        }
        let length = Double(string.count)
        var entropy: Double = 0
        for count in frequency.values {
            let probability = Double(count) / length
            if probability > 0 {
                entropy -= probability * log2(probability)
            }
        }
        return entropy
    }
}
