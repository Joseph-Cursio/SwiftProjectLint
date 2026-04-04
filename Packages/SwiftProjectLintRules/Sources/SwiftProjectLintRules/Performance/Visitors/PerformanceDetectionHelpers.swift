// Contains detection helper functions for performance anti-patterns in SwiftUI views.
import SwiftProjectLintModels
import SwiftProjectLintRegistry
import SwiftProjectLintVisitors
import SwiftSyntax
import Foundation

extension PerformanceVisitor {
    // MARK: - Detection Methods

    private static let unsafeIDPatterns: [(pattern: String, message: String)] = [
        ("\\.self", "Using \\.self as id in ForEach can cause performance issues"),
        ("\\.hashValue",
         "ForEach using \\.hashValue as ID — hash values are not unique")
    ]

    func detectForEachSelfID(_ node: FunctionCallExprSyntax) {
        // Check if this is a ForEach call
        if let calledExpr = node.calledExpression.as(DeclReferenceExprSyntax.self),
           calledExpr.baseName.text == SwiftUIViewType.forEach.rawValue {

            // Check if \.self or \.hashValue is used as the id parameter
            for argument in node.arguments where argument.label?.text == "id" {
                let argumentText = argument.expression.description
                for unsafeID in Self.unsafeIDPatterns where argumentText.contains(unsafeID.pattern) {
                    if !isForEachCollectionSafeForSelfID(node) {
                        addIssue(
                            severity: .warning,
                            message: unsafeID.message,
                            filePath: currentFilePath,
                            lineNumber: getLineNumber(for: Syntax(node)),
                            suggestion: "Use a stable, unique identifier like \\.id. "
                                + "Conform the element to Identifiable if possible",
                            ruleName: .forEachSelfID
                        )
                    }
                    break
                }
            }
        }
    }
}
