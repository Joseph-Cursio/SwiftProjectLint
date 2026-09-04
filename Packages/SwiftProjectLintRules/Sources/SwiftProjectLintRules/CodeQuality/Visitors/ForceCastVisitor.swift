import SwiftProjectLintModels
import SwiftProjectLintVisitors
import SwiftSyntax

/// A SwiftSyntax visitor that detects force cast (`as!`) expressions.
///
/// A force cast traps when the value is not of the target type. Like `try!` and force
/// unwrap, the trap is a fatal signal rather than an error, so a property run that draws
/// one unlucky input loses the whole process — the trial, the shrink, and every property
/// queued behind it.
///
/// `as?` is the same operator with the failure returned instead of raised, which is what
/// makes the fix a one-character change in the common case.
final class ForceCastVisitor: BasePatternVisitor {

    required init(pattern: SyntaxPattern, viewMode: SyntaxTreeViewMode = .sourceAccurate) {
        super.init(pattern: pattern, viewMode: viewMode)
    }

    /// The folded form: `x as! T` once the operator sequence has been resolved.
    override func visit(_ node: AsExprSyntax) -> SyntaxVisitorContinueKind {
        reportIfForced(node.questionOrExclamationMark, at: Syntax(node))
        return .visitChildren
    }

    /// The unfolded form. SwiftParser leaves a cast inside a `SequenceExprSyntax`
    /// unresolved, so a visitor that only handled `AsExprSyntax` would miss every `as!`
    /// written in an ordinary expression — the shape this rule exists to catch.
    override func visit(_ node: UnresolvedAsExprSyntax) -> SyntaxVisitorContinueKind {
        reportIfForced(node.questionOrExclamationMark, at: Syntax(node))
        return .visitChildren
    }

    /// Reports only `as!`. A node carries `nil` for a plain `as` and `?` for `as?`,
    /// neither of which can trap.
    private func reportIfForced(_ mark: TokenSyntax?, at node: Syntax) {
        guard let mark, mark.text == "!" else { return }

        addIssue(
            severity: .warning,
            message: "Force cast (as!) will crash on a type mismatch — use as? and handle the nil case",
            filePath: getFilePath(for: node),
            lineNumber: getLineNumber(for: node),
            suggestion: "Use as? and handle the nil case, or restructure so the type is known statically.",
            ruleName: .forceCast
        )
    }
}
