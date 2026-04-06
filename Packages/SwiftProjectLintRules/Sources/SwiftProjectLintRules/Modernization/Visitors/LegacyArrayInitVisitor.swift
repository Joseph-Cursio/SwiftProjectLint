import SwiftProjectLintModels
import SwiftProjectLintRegistry
import SwiftProjectLintVisitors
import SwiftSyntax

/// Detects verbose collection initializers that can use Swift's shorthand syntax.
///
/// `Array<String>()` → `[String]()`, `Dictionary<String, Int>()` → `[String: Int]()`,
/// `Optional<T>.none` → `nil`. Opt-in style rule.
final class LegacyArrayInitVisitor: BasePatternVisitor {

    private static let verboseTypes: Set<String> = ["Array", "Dictionary"]

    required init(pattern: SyntaxPattern, viewMode: SyntaxTreeViewMode = .sourceAccurate) {
        super.init(pattern: pattern, viewMode: viewMode)
    }

    // MARK: - Detect Array<T>() and Dictionary<K,V>()

    override func visit(_ node: FunctionCallExprSyntax) -> SyntaxVisitorContinueKind {
        guard let callee = node.calledExpression.as(GenericSpecializationExprSyntax.self),
              let declRef = callee.expression.as(DeclReferenceExprSyntax.self),
              Self.verboseTypes.contains(declRef.baseName.text),
              node.arguments.isEmpty else {
            return .visitChildren
        }

        let typeName = declRef.baseName.text
        let genericArgs = callee.genericArgumentClause.arguments
            .map { $0.trimmedDescription }
            .joined(separator: ", ")

        let shortForm: String
        if typeName == "Array" {
            shortForm = "[\(genericArgs)]()"
        } else {
            shortForm = "[\(genericArgs)]()"
        }

        addIssue(
            severity: .info,
            message: "\(typeName)<\(genericArgs)>() can be simplified "
                + "to \(shortForm)",
            filePath: getFilePath(for: Syntax(node)),
            lineNumber: getLineNumber(for: Syntax(node)),
            suggestion: "Use Swift's shorthand syntax: \(shortForm)",
            ruleName: .legacyArrayInit
        )
        return .visitChildren
    }

    // MARK: - Detect Optional<T>.none

    override func visit(_ node: MemberAccessExprSyntax) -> SyntaxVisitorContinueKind {
        guard node.declName.baseName.text == "none",
              let base = node.base?.as(GenericSpecializationExprSyntax.self),
              let declRef = base.expression.as(DeclReferenceExprSyntax.self),
              declRef.baseName.text == "Optional" else {
            return .visitChildren
        }

        let wrappedType = base.genericArgumentClause.arguments
            .map { $0.trimmedDescription }
            .joined(separator: ", ")

        addIssue(
            severity: .info,
            message: "Optional<\(wrappedType)>.none can be simplified to nil",
            filePath: getFilePath(for: Syntax(node)),
            lineNumber: getLineNumber(for: Syntax(node)),
            suggestion: "Use nil instead of Optional<\(wrappedType)>.none",
            ruleName: .legacyArrayInit
        )
        return .visitChildren
    }
}
