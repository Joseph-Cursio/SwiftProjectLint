import SwiftProjectLintModels
import SwiftProjectLintRegistry
import SwiftProjectLintVisitors
import SwiftSyntax

/// A SwiftSyntax visitor that detects `print()` and `debugPrint()` calls.
///
/// Context-aware severity:
/// - `print()`/`debugPrint()` inside `#if DEBUG` → suppressed (compiled out in release)
/// - `print()` in production code → `.warning`
/// - `debugPrint()` in production code → `.warning` (stronger signal, debug-only tool)
final class PrintStatementVisitor: BasePatternVisitor {

    private var insideIfDebug = false

    required init(pattern: SyntaxPattern, viewMode: SyntaxTreeViewMode = .sourceAccurate) {
        super.init(pattern: pattern, viewMode: viewMode)
    }

    // MARK: - Track #if DEBUG

    override func visit(_ node: IfConfigDeclSyntax) -> SyntaxVisitorContinueKind {
        for clause in node.clauses {
            if let condition = clause.condition,
               condition.trimmedDescription == "DEBUG" {
                insideIfDebug = true
            }
        }
        return .visitChildren
    }

    override func visitPost(_ node: IfConfigDeclSyntax) {
        insideIfDebug = false
    }

    // MARK: - Detect print/debugPrint

    override func visit(_ node: FunctionCallExprSyntax) -> SyntaxVisitorContinueKind {
        guard let declRef = node.calledExpression.as(DeclReferenceExprSyntax.self) else {
            return .visitChildren
        }
        let funcName = declRef.baseName.text
        guard funcName == "print" || funcName == "debugPrint" else {
            return .visitChildren
        }

        // Suppress inside #if DEBUG — compiled out in release
        if insideIfDebug { return .visitChildren }

        let isDebugPrint = funcName == "debugPrint"
        let message: String
        if isDebugPrint {
            message = "debugPrint() outside #if DEBUG "
                + "— likely left over from debugging"
        } else {
            message = "print() in production code "
                + "— use os.Logger for structured logging"
        }

        addIssue(
            severity: .warning,
            message: message,
            filePath: getFilePath(for: Syntax(node)),
            lineNumber: getLineNumber(for: Syntax(node)),
            suggestion: "Use os.Logger for structured logging, "
                + "or wrap in #if DEBUG if needed only during development.",
            ruleName: .printStatement
        )
        return .visitChildren
    }
}
