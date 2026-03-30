import SwiftProjectLintModels
import SwiftProjectLintRegistry
import SwiftProjectLintVisitors
import Foundation
import SwiftSyntax

/// Visitor that detects expensive operations inside custom ViewModifier body implementations.
///
/// Operations like sorted, filter, map, reduce, flatMap, and compactMap inside
/// a ViewModifier's body(content:) method run on every view update and should
/// be precomputed or moved outside the body.
class CustomModifierPerformanceVisitor: BasePatternVisitor {

    private static let expensiveOperations: Set<String> = [
        "sorted", "filter", "map", "reduce", "flatMap", "compactMap"
    ]

    private var isInViewModifier = false
    private var isInModifierBody = false
    private var currentModifierName = ""

    required init(pattern: SyntaxPattern, viewMode: SyntaxTreeViewMode = .sourceAccurate) {
        super.init(pattern: pattern, viewMode: viewMode)
    }

    override func visit(_ node: StructDeclSyntax) -> SyntaxVisitorContinueKind {
        if isViewModifier(node) {
            isInViewModifier = true
            currentModifierName = node.name.text
        }
        return .visitChildren
    }

    override func visitPost(_ node: StructDeclSyntax) {
        if isInViewModifier && node.name.text == currentModifierName {
            isInViewModifier = false
            isInModifierBody = false
            currentModifierName = ""
        }
    }

    override func visit(_ node: FunctionDeclSyntax) -> SyntaxVisitorContinueKind {
        if isInViewModifier && node.name.text == "body" {
            // Verify it has a `content` parameter to confirm it's the ViewModifier body
            let hasContentParam = node.signature.parameterClause.parameters.contains { parameter in
                parameter.firstName.text == "content"
            }
            if hasContentParam {
                isInModifierBody = true
            }
        }
        return .visitChildren
    }

    override func visitPost(_ node: FunctionDeclSyntax) {
        if isInModifierBody && node.name.text == "body" {
            isInModifierBody = false
        }
    }

    override func visit(_ node: FunctionCallExprSyntax) -> SyntaxVisitorContinueKind {
        guard isInModifierBody else { return .visitChildren }

        // Check for method-style calls like array.sorted(), items.filter { ... }
        if let memberAccess = node.calledExpression.as(MemberAccessExprSyntax.self) {
            let methodName = memberAccess.declName.baseName.text
            if Self.expensiveOperations.contains(methodName) {
                addIssue(
                    node: Syntax(node),
                    variables: [
                        "modifierName": currentModifierName,
                        "operation": methodName
                    ]
                )
            }
        }

        // Check for free-function style calls like sorted(array)
        if let declRef = node.calledExpression.as(DeclReferenceExprSyntax.self) {
            let functionName = declRef.baseName.text
            if Self.expensiveOperations.contains(functionName) {
                addIssue(
                    node: Syntax(node),
                    variables: [
                        "modifierName": currentModifierName,
                        "operation": functionName
                    ]
                )
            }
        }

        return .visitChildren
    }

    private func isViewModifier(_ node: StructDeclSyntax) -> Bool {
        guard let inheritanceClause = node.inheritanceClause else { return false }
        for inheritance in inheritanceClause.inheritedTypes {
            if let name = inheritance.type.as(IdentifierTypeSyntax.self)?.name.text,
               name == "ViewModifier" {
                return true
            }
        }
        return false
    }
}
