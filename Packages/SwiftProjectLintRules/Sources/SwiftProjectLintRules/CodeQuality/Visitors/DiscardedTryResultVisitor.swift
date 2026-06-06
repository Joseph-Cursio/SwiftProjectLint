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
/// - `items.compactMap { try? f($0) }` — the `try?` is the last expression of a
///   transform closure (`map`/`compactMap`/`flatMap`), so its value IS the
///   closure's result and is collected by the caller, not discarded. (A Void
///   closure such as `Button { try? save() }` still fires — its last expression
///   is genuinely discarded.)
final class DiscardedTryResultVisitor: BasePatternVisitor {

    /// Sequence transforms whose closure returns a value the caller collects.
    private static let transformMethods: Set<String> = ["map", "compactMap", "flatMap"]

    required init(pattern: SyntaxPattern, viewMode: SyntaxTreeViewMode = .sourceAccurate) {
        super.init(pattern: pattern, viewMode: viewMode)
    }

    override func visit(_ node: TryExprSyntax) -> SyntaxVisitorContinueKind {
        // Only try? — not bare try or try!
        guard node.questionOrExclamationMark?.tokenKind == .postfixQuestionMark else {
            return .visitChildren
        }

        // Only when the entire try? expression is a bare statement (result not used)
        guard let codeBlockItem = node.parent?.as(CodeBlockItemSyntax.self) else {
            return .visitChildren
        }

        // Don't flag when the try? is the last expression of a value-transforming
        // closure (map/compactMap/flatMap) — there the value is the closure's
        // result, collected by the caller rather than discarded.
        guard isTransformClosureResult(codeBlockItem) == false else {
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

    // MARK: - Transform-closure detection

    /// True when `item` is the LAST statement of a closure passed to a
    /// value-transforming method (`map`/`compactMap`/`flatMap`), so the
    /// statement's value is the closure's result rather than a discard.
    private func isTransformClosureResult(_ item: CodeBlockItemSyntax) -> Bool {
        guard let itemList = item.parent?.as(CodeBlockItemListSyntax.self),
              let closure = itemList.parent?.as(ClosureExprSyntax.self),
              itemList.last?.id == item.id
        else {
            return false
        }
        return enclosingCallMethodName(of: closure)
            .map(Self.transformMethods.contains) ?? false
    }

    /// The method name of the call this closure is an argument to — whether it
    /// is the trailing closure or a regular closure argument.
    private func enclosingCallMethodName(of closure: ClosureExprSyntax) -> String? {
        if let call = closure.parent?.as(FunctionCallExprSyntax.self) {
            return calledMethodName(call)
        }
        if let labeled = closure.parent?.as(LabeledExprSyntax.self),
           let list = labeled.parent?.as(LabeledExprListSyntax.self),
           let call = list.parent?.as(FunctionCallExprSyntax.self) {
            return calledMethodName(call)
        }
        return nil
    }

    private func calledMethodName(_ call: FunctionCallExprSyntax) -> String? {
        call.calledExpression.as(MemberAccessExprSyntax.self)?.declName.baseName.text
    }
}
