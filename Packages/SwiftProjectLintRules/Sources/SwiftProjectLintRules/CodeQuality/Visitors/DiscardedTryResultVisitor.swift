import SwiftProjectLintModels
import SwiftProjectLintRegistry
import SwiftProjectLintVisitors
import SwiftSyntax

/// A SwiftSyntax visitor that detects `try?` used as a bare statement.
///
/// `try?` as a standalone expression discards both the return value and the
/// error — it is the maximum-discard form of a call. This is almost always a
/// mistake: either the result matters (use `let x = try? call()`) or the error
/// matters (use `do/catch`). The only legitimate use is deliberate fire-and-
/// forget with error suppression, which should be explicit and annotated.
///
/// Not flagged:
/// - `let x = try? call()` — result captured
/// - `guard let x = try? call() else { … }` — result checked
/// - `_ = try? call()` — explicit discard, developer intent is clear
/// - `try call()` / `try! call()` — different operators
final class DiscardedTryResultVisitor: BasePatternVisitor {

    required init(pattern: SyntaxPattern, viewMode: SyntaxTreeViewMode = .sourceAccurate) {
        super.init(pattern: pattern, viewMode: viewMode)
    }

    override func visit(_ node: TryExprSyntax) -> SyntaxVisitorContinueKind {
        // Only try? — not bare try or try!
        guard node.questionOrExclamationMark?.tokenKind == .postfixQuestionMark else {
            return .visitChildren
        }

        // Only when the entire try? expression is a bare statement (result not used)
        guard node.parent?.is(CodeBlockItemSyntax.self) == true else {
            return .visitChildren
        }

        addIssue(
            severity: .warning,
            message: "'try?' result is discarded — both the return value and the error are silently lost",
            filePath: getFilePath(for: Syntax(node)),
            lineNumber: getLineNumber(for: Syntax(node)),
            suggestion: "Capture the result ('let x = try? call()') or handle the error with do/catch.",
            ruleName: .discardedTryResult
        )

        return .visitChildren
    }
}
