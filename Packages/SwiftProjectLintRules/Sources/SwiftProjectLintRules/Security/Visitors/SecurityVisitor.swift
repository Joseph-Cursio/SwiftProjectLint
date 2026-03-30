import SwiftProjectLintModels
import SwiftProjectLintRegistry
import SwiftProjectLintVisitors
import Foundation
import SwiftSyntax

// MARK: - Security Visitor

/// A SwiftSyntax visitor that detects security issues in Swift code.
///
/// - Hardcoded secrets (apiKey, secret, password, token)
/// - Unsafe URL construction with string interpolation
class SecurityVisitor: BasePatternVisitor {
    private var currentFilePath: String = ""

    required init(pattern: SyntaxPattern, viewMode: SyntaxTreeViewMode = .sourceAccurate) {
        super.init(pattern: pattern, viewMode: viewMode)
    }

    /// Sets the current file path for issue reporting.
    override func setFilePath(_ filePath: String) {
        self.currentFilePath = filePath
    }

    override func visit(_ node: VariableDeclSyntax) -> SyntaxVisitorContinueKind {
        for binding in node.bindings {
            if let pattern = binding.pattern.as(IdentifierPatternSyntax.self) {
                let variableName = pattern.identifier.text

                // Check for hardcoded secrets.
                // Match specific compound keywords rather than bare "key", which
                // false-positives on UserDefaults keys, dictionary keys, sort keys, etc.
                let secretKeywords = [
                    "apiKey", "apiSecret",
                    "secretKey", "secret",
                    "password", "passwd",
                    "token",
                    "authKey", "privateKey", "encryptionKey", "signingKey",
                    "clientSecret", "accessKey", "secretAccessKey",
                    "credential"
                ]
                if secretKeywords.contains(where: { variableName.localizedCaseInsensitiveContains($0) }) {
                    if let initializer = binding.initializer,
                       initializer.value.is(StringLiteralExprSyntax.self) {
                        addIssue(
                            severity: .error,
                            message: "Hardcoded secret detected in '\(variableName)'",
                            filePath: currentFilePath,
                            lineNumber: getLineNumber(for: Syntax(node)),
                            suggestion: "Use secure key storage like Keychain or environment variables",
                            ruleName: .hardcodedSecret
                        )
                    }
                }
            }
        }
        return .visitChildren
    }

    override func visit(_ node: FunctionCallExprSyntax) -> SyntaxVisitorContinueKind {
        // Check for unsafe URL construction
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
}
