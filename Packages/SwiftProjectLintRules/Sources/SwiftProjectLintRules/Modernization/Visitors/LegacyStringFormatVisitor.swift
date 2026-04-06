import SwiftProjectLintModels
import SwiftProjectLintRegistry
import SwiftProjectLintVisitors
import SwiftSyntax

/// A SwiftSyntax visitor that detects C-style `String(format:)` usage.
///
/// `String(format: "%.2f", value)` is a C-style API inherited from Objective-C.
/// The modern Swift alternative uses `FormatStyle`, which is type-safe, localisation-aware,
/// and composes naturally with SwiftUI's `Text` and `formatted()`.
final class LegacyStringFormatVisitor: BasePatternVisitor {

    required init(pattern: SyntaxPattern, viewMode: SyntaxTreeViewMode = .sourceAccurate) {
        super.init(pattern: pattern, viewMode: viewMode)
    }

    override func visit(_ node: FunctionCallExprSyntax) -> SyntaxVisitorContinueKind {
        detectLegacyStringFormat(node)
        return .visitChildren
    }

    private func detectLegacyStringFormat(_ node: FunctionCallExprSyntax) {
        guard let declRef = node.calledExpression.as(DeclReferenceExprSyntax.self),
              declRef.baseName.text == "String" else { return }

        let hasFormatLabel = node.arguments.contains { $0.label?.text == "format" }
        guard hasFormatLabel else { return }

        addIssue(
            severity: .info,
            message: "String(format:) is a C-style formatting API",
            filePath: getFilePath(for: Syntax(node)),
            lineNumber: getLineNumber(for: Syntax(node)),
            suggestion: "Prefer FormatStyle: e.g. value.formatted(.number.precision(.fractionLength(2))) "
                + "or string interpolation with format specifiers.",
            ruleName: .legacyStringFormat
        )
    }
}
