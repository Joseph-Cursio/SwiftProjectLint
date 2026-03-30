import SwiftProjectLintModels
import SwiftProjectLintRegistry
import SwiftProjectLintVisitors
import Foundation
import SwiftSyntax

/// Visitor that detects usage of .self or \.self as the id parameter in ForEach
class ForEachSelfIDVisitor: BasePatternVisitor {

    required init(pattern: SyntaxPattern, viewMode: SyntaxTreeViewMode = .sourceAccurate) {
        super.init(pattern: pattern, viewMode: viewMode)
    }

    override func visit(_ node: FunctionCallExprSyntax) -> SyntaxVisitorContinueKind {
        // Check if this is a ForEach call
        if let calledExpr = node.calledExpression.as(DeclReferenceExprSyntax.self),
           calledExpr.baseName.text == SwiftUIViewType.forEach.rawValue {
            // Check if .self or \.self is used as the id parameter
            for argument in node.arguments where argument.label?.text == "id" {
                if let memberAccess = argument.expression.as(MemberAccessExprSyntax.self),
                   memberAccess.declName.baseName.text == "self",
                   !isForEachCollectionSafeForSelfID(node) {
                    addIssue(node: Syntax(node))
                }
            }
        }
        return .visitChildren
    }
} 
