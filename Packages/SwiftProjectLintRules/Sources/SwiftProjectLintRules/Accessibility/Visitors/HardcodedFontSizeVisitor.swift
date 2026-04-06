import SwiftProjectLintModels
import SwiftProjectLintRegistry
import SwiftProjectLintVisitors
import SwiftSyntax

/// A SwiftSyntax visitor that detects hardcoded font sizes in `.font(.system(size:))` calls.
///
/// Hardcoded sizes bypass Dynamic Type, making text inaccessible to users who adjust
/// their preferred font size. Use semantic text styles like `.font(.largeTitle)` instead.
final class HardcodedFontSizeVisitor: BasePatternVisitor {

    required init(pattern: SyntaxPattern, viewMode: SyntaxTreeViewMode = .sourceAccurate) {
        super.init(pattern: pattern, viewMode: viewMode)
    }

    override func visit(_ node: FunctionCallExprSyntax) -> SyntaxVisitorContinueKind {
        if isTestOrFixtureFile() { return .visitChildren }
        detectHardcodedFontSize(node)
        return .visitChildren
    }

    private func detectHardcodedFontSize(_ node: FunctionCallExprSyntax) {
        // Check for .font(...) call
        guard let outerMember = node.calledExpression.as(MemberAccessExprSyntax.self),
              outerMember.declName.baseName.text == "font" else { return }

        // Get the first argument — should be a .system(...) call
        guard let firstArg = node.arguments.first,
              let systemCall = firstArg.expression.as(FunctionCallExprSyntax.self),
              let systemMember = systemCall.calledExpression.as(MemberAccessExprSyntax.self),
              systemMember.declName.baseName.text == "system" else { return }

        // Look for a `size:` argument with a numeric literal
        for argument in systemCall.arguments {
            guard let label = argument.label?.text, label == "size" else { continue }

            let isLiteral = argument.expression.is(IntegerLiteralExprSyntax.self)
                || argument.expression.is(FloatLiteralExprSyntax.self)

            guard isLiteral else { continue }

            let value = argument.expression.trimmedDescription
            addIssue(
                severity: .warning,
                message: "Hardcoded font size: .font(.system(size: \(value))). "
                    + "Literal sizes bypass Dynamic Type, making text inaccessible to users "
                    + "who adjust their preferred font size.",
                filePath: getFilePath(for: Syntax(node)),
                lineNumber: getLineNumber(for: Syntax(node)),
                suggestion: "Use a semantic text style instead, e.g., .font(.title) or .font(.body). "
                    + "If a custom size is necessary, use @ScaledMetric to scale with Dynamic Type.",
                ruleName: .hardcodedFontSize
            )
        }
    }
}
