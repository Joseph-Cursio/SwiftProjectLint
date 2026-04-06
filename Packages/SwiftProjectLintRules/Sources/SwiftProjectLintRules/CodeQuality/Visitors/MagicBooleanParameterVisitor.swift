import SwiftProjectLintModels
import SwiftProjectLintRegistry
import SwiftProjectLintVisitors
import SwiftSyntax

/// Detects boolean literal arguments passed without argument labels.
///
/// `configureView(true, false, true)` is hard to read — what do the booleans
/// mean? Labeled arguments (`animated: true, recursive: false`) are self-documenting.
final class MagicBooleanParameterVisitor: BasePatternVisitor {

    /// Functions where unlabeled booleans are standard and expected.
    private static let suppressedFunctions: Set<String> = [
        "print", "debugPrint", "dump",
        "XCTAssert", "XCTAssertTrue", "XCTAssertFalse",
        "XCTAssertEqual", "XCTAssertNotEqual",
        "XCTAssertNil", "XCTAssertNotNil",
        "min", "max", "assert", "precondition",
        "fatalError"
    ]

    /// Macro names where booleans are standard.
    private static let suppressedMacros: Set<String> = [
        "#expect", "#require"
    ]

    required init(pattern: SyntaxPattern, viewMode: SyntaxTreeViewMode = .sourceAccurate) {
        super.init(pattern: pattern, viewMode: viewMode)
    }

    override func visit(_ node: FunctionCallExprSyntax) -> SyntaxVisitorContinueKind {
        // Get function name for suppression check
        let funcName = extractFunctionName(node)
        if let funcName, Self.suppressedFunctions.contains(funcName) {
            return .visitChildren
        }

        // Count unlabeled boolean arguments
        var unlabeledBoolCount = 0
        for arg in node.arguments {
            if arg.label == nil, isBooleanLiteral(arg.expression) {
                unlabeledBoolCount += 1
            }
        }

        // Flag if there are unlabeled boolean literals
        // For single-arg functions, only flag if there are 2+ total args
        // (single bool arg is often fine: toggle(true), setEnabled(false))
        let totalArgs = node.arguments.count
        let shouldFlag = unlabeledBoolCount >= 2
            || (unlabeledBoolCount >= 1 && totalArgs >= 2)

        if shouldFlag {
            let plural = unlabeledBoolCount > 1 ? "s" : ""
            addIssue(
                severity: .info,
                message: "Function call has \(unlabeledBoolCount) unlabeled "
                    + "boolean parameter\(plural) — meaning is unclear",
                filePath: getFilePath(for: Syntax(node)),
                lineNumber: getLineNumber(for: Syntax(node)),
                suggestion: "Add argument labels to boolean parameters "
                    + "for self-documenting code.",
                ruleName: .magicBooleanParameter
            )
        }

        return .visitChildren
    }

    // MARK: - Helpers

    private func isBooleanLiteral(_ expr: ExprSyntax) -> Bool {
        guard let boolExpr = expr.as(BooleanLiteralExprSyntax.self) else {
            return false
        }
        return boolExpr.literal.text == "true" || boolExpr.literal.text == "false"
    }

    private func extractFunctionName(_ node: FunctionCallExprSyntax) -> String? {
        if let declRef = node.calledExpression.as(DeclReferenceExprSyntax.self) {
            return declRef.baseName.text
        }
        if let memberAccess = node.calledExpression.as(MemberAccessExprSyntax.self) {
            return memberAccess.declName.baseName.text
        }
        return nil
    }
}
