import SwiftProjectLintModels
import SwiftProjectLintRegistry
import SwiftProjectLintVisitors
import Foundation
import SwiftSyntax

/// Detects `#expect(!expression)` and `#require(!expression)` in Swift Testing code.
///
/// Negating inside these macros defeats the sub-expression capture,
/// producing a plain `false` on failure with no diagnostic context.
/// `#expect(expression == false)` / `#require(expression == false)` gives
/// the same semantics with full captured values shown in the test report.
class ExpectNegationVisitor: BasePatternVisitor {
    private static let targetMacros: Set<String> = ["expect", "require"]
    private var currentFilePath: String = ""

    required init(pattern: SyntaxPattern, viewMode: SyntaxTreeViewMode = .sourceAccurate) {
        super.init(pattern: pattern, viewMode: viewMode)
    }

    override func setFilePath(_ filePath: String) {
        self.currentFilePath = filePath
    }

    override func visit(_ node: MacroExpansionExprSyntax) -> SyntaxVisitorContinueKind {
        let macroName = node.macroName.text
        guard Self.targetMacros.contains(macroName),
              let firstArg = node.arguments.first,
              firstArg.label == nil,
              let prefix = firstArg.expression.as(PrefixOperatorExprSyntax.self),
              prefix.operator.text == "!" else {
            return .visitChildren
        }

        let negatedExpr = prefix.expression.trimmedDescription
        addIssue(
            severity: .warning,
            message: "#\(macroName)(!\(negatedExpr)) negates inside the macro — " +
                "use #\(macroName)(\(negatedExpr) == false) for better failure diagnostics",
            filePath: currentFilePath,
            lineNumber: getLineNumber(for: Syntax(node)),
            suggestion: "Replace #\(macroName)(!\(negatedExpr)) with #\(macroName)(\(negatedExpr) == false)",
            ruleName: .macroNegation
        )
        return .visitChildren
    }
}
