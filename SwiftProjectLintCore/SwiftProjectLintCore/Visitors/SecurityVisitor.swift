import Foundation
import SwiftSyntax

// MARK: - Security Visitor

/// A SwiftSyntax visitor that detects security issues in Swift code.
///
/// - Hardcoded secrets (apiKey, secret, password, token)
/// - Unsafe URL construction with string interpolation
class SecurityVisitor: BasePatternVisitor {
    private var currentFilePath: String = ""
    
    required init(patternCategory: PatternCategory) {
        super.init(patternCategory: patternCategory)
    }
    
    required init(viewMode: SyntaxTreeViewMode) {
        super.init(viewMode: viewMode)
    }
    
    /// Sets the current file path for issue reporting.
    override func setFilePath(_ filePath: String) {
        self.currentFilePath = filePath
    }
    
    override func visit(_ node: VariableDeclSyntax) -> SyntaxVisitorContinueKind {
        let message = "Visiting variable declaration"
        Task { @MainActor in
            DebugLogger.logVisitor(.security, message)
        }
        for binding in node.bindings {
            if let pattern = binding.pattern.as(IdentifierPatternSyntax.self) {
                let variableName = pattern.identifier.text
                
                // Check for hardcoded secrets
                let secretKeywords = ["apiKey", "secret", "password", "token", "key"]
                if secretKeywords.contains(where: { variableName.localizedCaseInsensitiveContains($0) }) {
                    if let initializer = binding.initializer,
                       initializer.value.is(StringLiteralExprSyntax.self) {
                        addIssue(
                            severity: .error,
                            message: "Hardcoded secret detected in variable '\(variableName)'",
                            filePath: currentFilePath,
                            lineNumber: getLineNumber(for: Syntax(node)),
                            suggestion: "Use environment variables or secure key storage",
                            ruleName: nil
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
                            message: "URL construction with string interpolation may be unsafe",
                            filePath: currentFilePath,
                            lineNumber: getLineNumber(for: Syntax(node)),
                            suggestion: "Use URLComponents for safe URL construction",
                            ruleName: nil
                        )
                    }
                }
            }
        }
        return .visitChildren
    }
} 

