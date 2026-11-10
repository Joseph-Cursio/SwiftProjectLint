import Foundation
import SwiftProjectLintModels
import SwiftProjectLintVisitors
import SwiftSyntax

extension UIVisitor {
    func analyzeAccessorBlock(_ accessorBlock: AccessorBlockSyntax?, for node: VariableDeclSyntax) -> Bool {
        guard let accessorBlock else { return false }
        for child in accessorBlock.accessors.children(viewMode: .all) {
            if let accessor = child.as(AccessorDeclSyntax.self), let body = accessor.body {
                analyzeBodyTextForErrorHandling(body.description, node: node)
                return true
            }
        }
        return false
    }

    func analyzeInitializer(_ initializer: InitializerClauseSyntax?, for node: VariableDeclSyntax) -> Bool {
        guard let initializer else { return false }
        if let closure = initializer.value.as(ClosureExprSyntax.self) {
            analyzeBodyTextForErrorHandling(closure.statements.description, node: node)
            return true
        }
        return false
    }

    func analyzeBindingFallback(_ binding: PatternBindingSyntax, for node: VariableDeclSyntax) {
        analyzeBodyTextForErrorHandling(binding.description, node: node)
    }

    private func analyzeBodyTextForErrorHandling(_ bodyText: String, node: VariableDeclSyntax) {
        let hasErrorHandling = bodyText.contains("if let error") || bodyText.contains("Text(\"Error")
        let hasProperUI = bodyText.contains(".alert(") || bodyText.contains(".sheet(") || bodyText.contains("Alert(")
        if hasErrorHandling, !hasProperUI {
            addIssue(
                severity: .info,
                message: "Consider using proper error handling UI patterns",
                filePath: currentFilePath,
                lineNumber: getLineNumber(for: Syntax(node)),
                suggestion: "Use .alert() or .sheet() modifiers for displaying errors",
                ruleName: .basicErrorHandling
            )
        }
    }
}
