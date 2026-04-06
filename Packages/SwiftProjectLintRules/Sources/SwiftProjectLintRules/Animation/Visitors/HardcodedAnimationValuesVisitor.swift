import SwiftProjectLintModels
import SwiftProjectLintRegistry
import SwiftProjectLintVisitors
import SwiftSyntax

/// A SwiftSyntax visitor that detects hardcoded numeric literals in animation factory calls.
///
/// Detects `.hardcodedAnimationValues` when animation factories like `.easeIn(duration:)`,
/// `.spring(response:dampingFraction:)`, etc., are called with literal numeric values
/// instead of named constants.
final class HardcodedAnimationValuesVisitor: BasePatternVisitor {

    private static let animationFactories: Set<String> = [
        "easeIn", "easeOut", "easeInOut", "linear",
        "spring", "interactiveSpring", "interpolatingSpring"
    ]

    private static let parameterLabels: Set<String> = [
        "duration", "response", "dampingFraction", "bounce",
        "blendDuration", "speed", "repeatCount"
    ]

    required init(pattern: SyntaxPattern, viewMode: SyntaxTreeViewMode = .sourceAccurate) {
        super.init(pattern: pattern, viewMode: viewMode)
    }

    override func visit(_ node: FunctionCallExprSyntax) -> SyntaxVisitorContinueKind {
        detectHardcodedAnimationValues(node)
        return .visitChildren
    }

    private func detectHardcodedAnimationValues(_ node: FunctionCallExprSyntax) {
        guard let memberAccess = node.calledExpression.as(MemberAccessExprSyntax.self) else { return }

        let methodName = memberAccess.declName.baseName.text
        guard Self.animationFactories.contains(methodName) else { return }

        for argument in node.arguments {
            guard let label = argument.label?.text,
                  Self.parameterLabels.contains(label) else { continue }

            let isLiteral = argument.expression.is(FloatLiteralExprSyntax.self)
                || argument.expression.is(IntegerLiteralExprSyntax.self)

            guard isLiteral else { continue }

            let value = argument.expression.trimmedDescription
            addIssue(
                severity: .info,
                message: "Hardcoded animation value: .\(methodName)(\(label): \(value)). " +
                    "Magic numbers make animations hard to maintain and tune consistently.",
                filePath: getFilePath(for: Syntax(node)),
                lineNumber: getLineNumber(for: Syntax(node)),
                suggestion: "Extract the value to a named constant, e.g., " +
                    "let \(label) = \(value), then use .\(methodName)(\(label): \(label)).",
                ruleName: .hardcodedAnimationValues
            )
        }
    }
}
