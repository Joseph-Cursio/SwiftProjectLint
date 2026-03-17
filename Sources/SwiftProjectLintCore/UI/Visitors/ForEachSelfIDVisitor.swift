import Foundation
import SwiftSyntax

/// Visitor that detects usage of .self or \.self as the id parameter in ForEach
class ForEachSelfIDVisitor: BasePatternVisitor {
    private var currentFilePath: String = ""

    required init(pattern: SyntaxPattern, viewMode: SyntaxTreeViewMode = .sourceAccurate) {
        super.init(pattern: pattern, viewMode: viewMode)
    }

    /// Sets the current file path for issue reporting.
    override func setFilePath(_ filePath: String) {
        self.currentFilePath = filePath
    }

    override func visit(_ node: FunctionCallExprSyntax) -> SyntaxVisitorContinueKind {
        DebugLogger.logVisitor(.forEachSelfID, "Visiting FunctionCallExprSyntax")
        // Check if this is a ForEach call
        if let calledExpr = node.calledExpression.as(DeclReferenceExprSyntax.self),
           calledExpr.baseName.text == SwiftUIViewType.forEach.rawValue {
            // Check if .self or \.self is used as the id parameter
            for argument in node.arguments where argument.label?.text == "id" {
                if let memberAccess = argument.expression.as(MemberAccessExprSyntax.self),
                   memberAccess.declName.baseName.text == "self" {
                    addIssue(node: Syntax(node))
                }
            }
        }
        return .visitChildren
    }
} 
