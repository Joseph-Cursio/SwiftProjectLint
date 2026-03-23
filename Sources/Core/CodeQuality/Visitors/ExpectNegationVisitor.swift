import Foundation
import SwiftSyntax

/// Detects `#expect(!expression)` in Swift Testing code.
///
/// Negating inside `#expect` defeats the macro's sub-expression capture,
/// producing a plain `false` on failure with no diagnostic context.
/// `#expect(expression == false)` gives the same semantics with full
/// captured values shown in the test report.
class ExpectNegationVisitor: BasePatternVisitor {
    private var currentFilePath: String = ""

    required init(pattern: SyntaxPattern, viewMode: SyntaxTreeViewMode = .sourceAccurate) {
        super.init(pattern: pattern, viewMode: viewMode)
    }

    override func setFilePath(_ filePath: String) {
        self.currentFilePath = filePath
    }

    override func visit(_ node: MacroExpansionExprSyntax) -> SyntaxVisitorContinueKind {
        guard node.macroName.text == "expect",
              let firstArg = node.arguments.first,
              firstArg.label == nil,
              firstArg.expression.is(PrefixOperatorExprSyntax.self),
              let prefix = firstArg.expression.as(PrefixOperatorExprSyntax.self),
              prefix.operator.text == "!" else {
            return .visitChildren
        }

        let negatedExpr = prefix.expression.trimmedDescription
        addIssue(
            severity: .warning,
            message: "#expect(!\(negatedExpr)) negates inside the macro — " +
                "use #expect(\(negatedExpr) == false) for better failure diagnostics",
            filePath: currentFilePath,
            lineNumber: getLineNumber(for: Syntax(node)),
            suggestion: "Replace #expect(!\(negatedExpr)) with #expect(\(negatedExpr) == false)",
            ruleName: .expectNegation
        )
        return .visitChildren
    }
}
