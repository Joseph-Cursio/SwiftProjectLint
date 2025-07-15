import Foundation
import SwiftSyntax

/// Visitor that detects usage of .self or \.self as the id parameter in ForEach
class ForEachSelfIDVisitor: BasePatternVisitor {
    private var currentFilePath: String = ""

    required init(patternCategory: PatternCategory = .performance) {
        super.init(patternCategory: patternCategory)
    }

    required init(viewMode: SyntaxTreeViewMode) {
        super.init(viewMode: viewMode)
    }

    /// Sets the current file path for issue reporting.
    override func setFilePath(_ filePath: String) {
        self.currentFilePath = filePath
    }

    override func visit(_ node: FunctionCallExprSyntax) -> SyntaxVisitorContinueKind {
        Task { @MainActor in
            DebugLogger.logVisitor(.forEachSelfID, "Visiting FunctionCallExprSyntax")
        }
        // Check if this is a ForEach call
        if let calledExpr = node.calledExpression.as(DeclReferenceExprSyntax.self),
           calledExpr.baseName.text == "ForEach" {
            // Check if .self or \.self is used as the id parameter
            for argument in node.arguments {
                if argument.label?.text == "id" {
                    if let memberAccess = argument.expression.as(MemberAccessExprSyntax.self),
                       memberAccess.declName.baseName.text == "self" {
                        addIssue(
                            severity: IssueSeverity.warning,
                            message: "Using \\.self as id in ForEach can cause performance issues",
                            filePath: currentFilePath,
                            lineNumber: getLineNumber(for: Syntax(node)),
                            suggestion: "Use a unique identifier property instead of \\.self for better performance",
                            ruleName: currentPattern?.name
                        )
                    }
                }
            }
        }
        return .visitChildren
    }
} 
