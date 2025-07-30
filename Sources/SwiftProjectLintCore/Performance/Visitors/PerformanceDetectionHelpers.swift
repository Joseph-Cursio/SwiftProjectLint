// Contains detection helper functions for performance anti-patterns in SwiftUI views.
import SwiftSyntax
import Foundation

extension PerformanceVisitor {
    // MARK: - Detection Methods

    func detectForEachWithoutID(_ node: MemberAccessExprSyntax) {
        // Look for ForEach with .self as id
        if node.declName.baseName.text == "self" {
            // Check if this is part of a ForEach call
            if let parent = node.parent?.as(FunctionCallExprSyntax.self),
               let calledExpr = parent.calledExpression.as(DeclReferenceExprSyntax.self),
               calledExpr.baseName.text == "ForEach" {

                // Check if .self is used as the id parameter
                for argument in parent.arguments {
                    if argument.label?.text == "id" {
                        if let memberAccess = argument.expression.as(MemberAccessExprSyntax.self),
                           memberAccess.declName.baseName.text == "self" {
                            addIssue(
                                severity: .warning,
                                message: "Using .self as id in ForEach can cause performance issues",
                                filePath: currentFilePath,
                                lineNumber: getLineNumber(for: Syntax(node)),
                                suggestion: "Use a unique identifier property instead of .self for better performance",
                                ruleName: nil
                            )
                        }
                    }
                }
            }
        }
    }

    func detectForEachSelfID(_ node: FunctionCallExprSyntax) {
        // Check if this is a ForEach call
        if let calledExpr = node.calledExpression.as(DeclReferenceExprSyntax.self),
           calledExpr.baseName.text == "ForEach" {

            // Check if \.self is used as the id parameter (not the collection)
            for argument in node.arguments {
                if argument.label?.text == "id" {
                    let argumentText = argument.expression.description
                    if argumentText.contains("\\.self") {
                        addIssue(
                            severity: .warning,
                            message: "Using \\.self as id in ForEach can cause performance issues",
                            filePath: currentFilePath,
                            lineNumber: getLineNumber(for: Syntax(node)),
                            suggestion: "Use a unique identifier property instead of \\.self for better performance",
                            ruleName: nil
                        )
                    }
                }
            }
        }
    }
}
