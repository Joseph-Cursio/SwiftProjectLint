import SwiftProjectLintModels
import SwiftProjectLintVisitors
import SwiftSyntax

/// A SwiftSyntax visitor that detects hardcoded font sizes in `.font(.system(size:))`
/// and `.font(.custom(_:size:))` calls.
///
/// Hardcoded sizes bypass Dynamic Type, making text inaccessible to users who adjust
/// their preferred font size. Use semantic text styles like `.font(.largeTitle)` instead.
///
/// Custom faces are held to the same standard: `.custom(_:size:relativeTo:)` scales with
/// Dynamic Type, so the bare `.custom(_:size:)` form is a genuine barrier with a concrete
/// fix, not an unavoidable consequence of using a non-system font.
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

        // Get the first argument — should be a .system(...) or .custom(...) call
        guard let firstArg = node.arguments.first,
              let fontCall = firstArg.expression.as(FunctionCallExprSyntax.self),
              let fontMember = fontCall.calledExpression.as(MemberAccessExprSyntax.self) else { return }

        let constructor = fontMember.declName.baseName.text
        guard constructor == "system" || constructor == "custom" else { return }

        // `.custom(_:size:relativeTo:)` scales the custom face against a text style, so it
        // honours Dynamic Type. Only the bare `.custom(_:size:)` form is a violation.
        if constructor == "custom",
           fontCall.arguments.contains(where: { $0.label?.text == "relativeTo" }) {
            return
        }

        // Look for a `size:` argument with a numeric literal
        for argument in fontCall.arguments {
            guard let label = argument.label?.text, label == "size" else { continue }

            let isLiteral = argument.expression.is(IntegerLiteralExprSyntax.self)
                || argument.expression.is(FloatLiteralExprSyntax.self)

            guard isLiteral else { continue }

            let value = argument.expression.trimmedDescription
            addIssue(
                severity: .warning,
                message: "Hardcoded font size: \(callForm(constructor, size: value)). "
                    + "Literal sizes bypass Dynamic Type, making text inaccessible to users "
                    + "who adjust their preferred font size.",
                filePath: getFilePath(for: Syntax(node)),
                lineNumber: getLineNumber(for: Syntax(node)),
                suggestion: suggestion(for: constructor),
                ruleName: .hardcodedFontSize
            )
        }
    }

    /// The offending call, rendered for the message.
    private func callForm(_ constructor: String, size: String) -> String {
        constructor == "custom"
            ? ".font(.custom(_, size: \(size)))"
            : ".font(.system(size: \(size)))"
    }

    /// The fix differs by constructor: a system font can move to a semantic text style,
    /// whereas a custom face keeps its name and gains a `relativeTo:` anchor.
    private func suggestion(for constructor: String) -> String {
        constructor == "custom"
            ? "Add a relativeTo: anchor so the face scales, e.g., "
                + ".font(.custom(\"Avenir\", size: 14, relativeTo: .body)). "
                + "Or drive the size with @ScaledMetric."
            : "Use a semantic text style instead, e.g., .font(.title) or .font(.body). "
                + "If a custom size is necessary, use @ScaledMetric to scale with Dynamic Type."
    }
}
