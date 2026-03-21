// Contains detection helper functions for performance anti-patterns in SwiftUI views.
import SwiftSyntax
import Foundation

extension PerformanceVisitor {
    // MARK: - Detection Methods

    func detectForEachSelfID(_ node: FunctionCallExprSyntax) {
        // Check if this is a ForEach call
        if let calledExpr = node.calledExpression.as(DeclReferenceExprSyntax.self),
           calledExpr.baseName.text == SwiftUIViewType.forEach.rawValue {

            // Check if \.self is used as the id parameter (not the collection)
            for argument in node.arguments where argument.label?.text == "id" {
                let argumentText = argument.expression.description
                if argumentText.contains("\\.self"),
                   !isForEachCollectionSafeForSelfID(node) {
                    addIssue(
                        severity: .warning,
                        message: "Using \\.self as id in ForEach can cause performance issues",
                        filePath: currentFilePath,
                        lineNumber: getLineNumber(for: Syntax(node)),
                        suggestion: "Use a unique identifier property instead of \\.self for better performance",
                        ruleName: .forEachSelfID
                    )
                }
            }
        }
    }
}
