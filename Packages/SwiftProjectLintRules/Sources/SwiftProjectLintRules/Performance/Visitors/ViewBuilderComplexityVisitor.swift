import SwiftProjectLintModels
import SwiftProjectLintRegistry
import SwiftProjectLintVisitors
import Foundation
import SwiftSyntax

/// Visitor that detects overly complex @ViewBuilder functions and computed properties.
///
/// Flags @ViewBuilder-annotated functions or computed properties that exceed
/// 30 lines or 15 statements, suggesting extraction into smaller subviews.
class ViewBuilderComplexityVisitor: BasePatternVisitor {

    private static let lineThreshold = 30
    private static let statementThreshold = 15

    required init(pattern: SyntaxPattern, viewMode: SyntaxTreeViewMode = .sourceAccurate) {
        super.init(pattern: pattern, viewMode: viewMode)
    }

    override func visit(_ node: FunctionDeclSyntax) -> SyntaxVisitorContinueKind {
        guard hasViewBuilderAttribute(node.attributes) else { return .visitChildren }

        if let body = node.body {
            let functionName = node.name.text
            checkComplexity(body: body, name: functionName, node: Syntax(node))
        }
        return .visitChildren
    }

    override func visit(_ node: VariableDeclSyntax) -> SyntaxVisitorContinueKind {
        guard hasViewBuilderAttribute(node.attributes) else { return .visitChildren }

        for binding in node.bindings {
            guard let accessorBlock = binding.accessorBlock else { continue }

            let propertyName = binding.pattern.description.trimmingCharacters(in: .whitespaces)

            // Skip the standard `body` property — handled by the existing largeViewBody rule
            if propertyName == "body" { continue }

            // Handle both `get { ... }` accessor and direct code block `{ ... }`
            switch accessorBlock.accessors {
            case .getter(let codeBlock):
                checkComplexity(
                    statements: codeBlock,
                    description: codeBlock.description,
                    name: propertyName,
                    node: Syntax(node)
                )
            case .accessors(let accessorList):
                for accessor in accessorList {
                    if accessor.accessorSpecifier.text == "get", let body = accessor.body {
                        checkComplexity(body: body, name: propertyName, node: Syntax(node))
                    }
                }
            }
        }
        return .visitChildren
    }

    private func checkComplexity(body: CodeBlockSyntax, name: String, node: Syntax) {
        checkComplexity(
            statements: body.statements,
            description: body.description,
            name: name,
            node: node
        )
    }

    private func checkComplexity(
        statements: CodeBlockItemListSyntax,
        description: String,
        name: String,
        node: Syntax
    ) {
        let lineCount = description.components(separatedBy: .newlines).count
        let statementCount = statements.count

        if lineCount > Self.lineThreshold || statementCount > Self.statementThreshold {
            addIssue(
                node: node,
                variables: [
                    "name": name,
                    "lineCount": "\(lineCount)",
                    "statementCount": "\(statementCount)"
                ]
            )
        }
    }

    private func hasViewBuilderAttribute(_ attributes: AttributeListSyntax) -> Bool {
        for attribute in attributes {
            if let attributeSyntax = attribute.as(AttributeSyntax.self),
               let attributeName = attributeSyntax.attributeName.as(IdentifierTypeSyntax.self),
               attributeName.name.text == "ViewBuilder" {
                return true
            }
        }
        return false
    }
}
