import SwiftProjectLintModels
import SwiftProjectLintRegistry
import SwiftProjectLintVisitors
import SwiftSyntax

/// Detects `DateFormatter()`, `NumberFormatter()`, and `MeasurementFormatter()`
/// instantiation anywhere in source code.
///
/// These Foundation formatters are expensive to create — they allocate internal
/// caches and parse locale data on initialization. The modern `FormatStyle` API
/// (`.formatted()`) is preferred, or formatters should be cached as static
/// properties.
///
/// This rule skips the `body` computed property of View-conforming structs,
/// which is already covered by `formatterInViewBody` at `.warning` severity.
final class LegacyFormatterVisitor: BasePatternVisitor {

    private static let legacyFormatterTypes: Set<String> = [
        "DateFormatter",
        "NumberFormatter",
        "MeasurementFormatter"
    ]

    private var insideViewBody = false

    required init(pattern: SyntaxPattern, viewMode: SyntaxTreeViewMode = .sourceAccurate) {
        super.init(pattern: pattern, viewMode: viewMode)
    }

    // MARK: - Track view body to avoid double-flagging

    override func visit(_ node: StructDeclSyntax) -> SyntaxVisitorContinueKind {
        return .visitChildren
    }

    override func visit(_ node: VariableDeclSyntax) -> SyntaxVisitorContinueKind {
        for binding in node.bindings {
            guard let name = binding.pattern.as(IdentifierPatternSyntax.self)?.identifier.text,
                  name == "body",
                  isInsideViewStruct(node) else {
                continue
            }
            insideViewBody = true
        }
        return .visitChildren
    }

    override func visitPost(_ node: VariableDeclSyntax) {
        for binding in node.bindings {
            guard let name = binding.pattern.as(IdentifierPatternSyntax.self)?.identifier.text,
                  name == "body" else {
                continue
            }
            insideViewBody = false
        }
    }

    // MARK: - Detect formatter instantiation

    override func visit(_ node: FunctionCallExprSyntax) -> SyntaxVisitorContinueKind {
        guard insideViewBody == false,
              let declRef = node.calledExpression.as(DeclReferenceExprSyntax.self),
              Self.legacyFormatterTypes.contains(declRef.baseName.text) else {
            return .visitChildren
        }

        let typeName = declRef.baseName.text
        addIssue(
            severity: .info,
            message: "\(typeName)() is the legacy Foundation formatting API",
            filePath: getFilePath(for: Syntax(node)),
            lineNumber: getLineNumber(for: Syntax(node)),
            suggestion: "Use .formatted() with FormatStyle instead, "
                + "or cache the formatter as a static property.",
            ruleName: .legacyFormatter
        )
        return .visitChildren
    }

    // MARK: - Helpers

    private func isInsideViewStruct(_ node: VariableDeclSyntax) -> Bool {
        var current: Syntax? = Syntax(node)
        while let parent = current?.parent {
            if let structDecl = parent.as(StructDeclSyntax.self) {
                return conformsToView(structDecl.inheritanceClause)
            }
            current = parent
        }
        return false
    }

    private func conformsToView(_ clause: InheritanceClauseSyntax?) -> Bool {
        guard let clause else { return false }
        return clause.inheritedTypes.contains { inherited in
            inherited.type.trimmedDescription == "View"
        }
    }
}
