import SwiftSyntax

/// A SwiftSyntax visitor that detects misuse of `matchedGeometryEffect`.
///
/// Detects `.matchedGeometryEffectMisuse` when:
/// - The namespace passed to `in:` is not declared with `@Namespace` in the same file
/// - The same `id:` is used more than once within the same namespace
final class MatchedGeometryVisitor: BasePatternVisitor {

    private var declaredNamespaces: Set<String> = []
    private var usedIds: [String: Set<String>] = [:]

    required init(pattern: SyntaxPattern, viewMode: SyntaxTreeViewMode = .sourceAccurate) {
        super.init(pattern: pattern, viewMode: viewMode)
    }

    override func visit(_ node: VariableDeclSyntax) -> SyntaxVisitorContinueKind {
        // Collect @Namespace variable declarations
        for attribute in node.attributes {
            if let attr = attribute.as(AttributeSyntax.self),
               attr.attributeName.trimmedDescription == "Namespace" {
                // Extract the variable name(s)
                for binding in node.bindings {
                    if let identPattern = binding.pattern.as(IdentifierPatternSyntax.self) {
                        declaredNamespaces.insert(identPattern.identifier.text)
                    }
                }
            }
        }
        return .visitChildren
    }

    override func visit(_ node: FunctionCallExprSyntax) -> SyntaxVisitorContinueKind {
        guard pattern.name == .matchedGeometryEffectMisuse else { return .visitChildren }
        detectMatchedGeometryEffectMisuse(node)
        return .visitChildren
    }

    private func detectMatchedGeometryEffectMisuse(_ node: FunctionCallExprSyntax) {
        guard let memberAccess = node.calledExpression.as(MemberAccessExprSyntax.self),
              memberAccess.declName.baseName.text == "matchedGeometryEffect" else { return }

        let namespaceName = node.arguments.first(where: { $0.label?.text == "in" })?.expression.trimmedDescription
        let idValue = node.arguments.first(where: { $0.label?.text == "id" })?.expression.trimmedDescription

        guard let namespace = namespaceName, let id = idValue else { return }

        if !declaredNamespaces.contains(namespace) {
            addIssue(
                severity: .warning,
                message: "matchedGeometryEffect uses namespace '\(namespace)' " +
                    "which is not declared with @Namespace in this file.",
                filePath: getFilePath(for: Syntax(node)),
                lineNumber: getLineNumber(for: Syntax(node)),
                suggestion: "Declare a @Namespace variable " +
                    "(e.g., @Namespace private var \(namespace)) in the enclosing view struct.",
                ruleName: .matchedGeometryEffectMisuse
            )
        } else if usedIds[namespace]?.contains(id) == true {
            addIssue(
                severity: .warning,
                message: "matchedGeometryEffect ID \(id) is used more than once in namespace '\(namespace)'. " +
                    "Duplicate IDs within the same namespace cause undefined animation behavior.",
                filePath: getFilePath(for: Syntax(node)),
                lineNumber: getLineNumber(for: Syntax(node)),
                suggestion: "Use a unique ID for each matchedGeometryEffect within the same namespace.",
                ruleName: .matchedGeometryEffectMisuse
            )
        } else {
            usedIds[namespace, default: []].insert(id)
        }
    }
}
