import SwiftProjectLintModels
import SwiftProjectLintVisitors
import SwiftSyntax

/// A SwiftSyntax visitor that detects `map`, `compactMap`, or `flatMap` used
/// for side effects with the result discarded.
///
/// These higher-order functions return a transformed collection. Using them as
/// bare statements throws the result away, which is almost always a mistake —
/// the developer likely intended `forEach`. This is a common error in AI-
/// generated code and among developers coming from imperative languages.
///
/// Not flagged:
/// - `let results = items.map { … }` — result captured
/// - `return items.map { … }` — result returned
/// - `items.forEach { … }` — correct API for side effects
/// - `func f() -> [T] { items.map { … } }` — **implicit return**
///
/// The implicit-return case is the one this rule got wrong, and it was 8 of 8 findings on one
/// subject (#107). The discard test was `node.parent?.is(CodeBlockItemSyntax.self)`, and a bare
/// statement is a `CodeBlockItem` — but so is the sole expression of a body that returns it.
/// Swift code omitting `return` is the common case, not the exception, so the rule fired on the
/// normal shape and stayed silent about nothing.
final class MapUsedForSideEffectsVisitor: BasePatternVisitor {

    private static let transformMethodNames: Set<String> = ["map", "compactMap", "flatMap"]

    required init(pattern: SyntaxPattern, viewMode: SyntaxTreeViewMode = .sourceAccurate) {
        super.init(pattern: pattern, viewMode: viewMode)
    }

    override func visit(_ node: FunctionCallExprSyntax) -> SyntaxVisitorContinueKind {
        guard let member = node.calledExpression.as(MemberAccessExprSyntax.self),
              Self.transformMethodNames.contains(member.declName.baseName.text) else {
            return .visitChildren
        }

        // Result discarded — the call is a bare statement whose value goes nowhere.
        guard let item = node.parent?.as(CodeBlockItemSyntax.self),
              !Self.valueIsUsed(of: item) else {
            return .visitChildren
        }

        let methodName = member.declName.baseName.text
        addIssue(
            severity: .warning,
            message: "'\(methodName)' result discarded — use 'forEach' for side effects",
            filePath: getFilePath(for: Syntax(node)),
            lineNumber: getLineNumber(for: Syntax(node)),
            suggestion: "Replace '\(methodName)' with 'forEach' when the transformed "
                + "collection is not needed, or assign the result to a variable.",
            ruleName: .mapUsedForSideEffects
        )

        return .visitChildren
    }

    /// Whether the value of `item` is the result of the body that holds it — an implicit return.
    ///
    /// The first question is the cheap one and it settles most cases: **a statement among several
    /// cannot be an implicit return.** Swift admits the implicit form only for a body whose sole
    /// statement is an expression, and that is true of `if`/`switch` expression branches too.
    ///
    /// Where the sole statement *is* the body, the answer depends on what owns it:
    ///
    /// - a **closure** — the value is its result. The expected type is not knowable from syntax
    ///   alone (a `() -> Void` closure really does discard it), so this errs toward silence. That
    ///   is the right side for a rule whose message asserts a mistake.
    /// - a **getter**, in either spelling — the value is the property's.
    /// - a **function** — only when it returns something. `func f() { items.map { … } }` is the
    ///   true positive this rule exists for, and it survives.
    /// - an **`if` / `switch` branch** — undecidable here, so it defers to wherever the
    ///   `if`/`switch` itself sits. That recursion is what stops
    ///   `func f() -> [T] { if c { a.map { … } } else { [] } }` from being the same false positive
    ///   one level down.
    private static func valueIsUsed(of item: CodeBlockItemSyntax) -> Bool {
        guard let list = item.parent?.as(CodeBlockItemListSyntax.self),
              list.count == 1,
              let owner = list.parent else {
            return false
        }

        // A closure body and a shorthand getter hold their statements directly.
        if owner.is(ClosureExprSyntax.self) || owner.is(AccessorBlockSyntax.self) { return true }
        // A `switch` case holds them directly too, and defers to the `switch`.
        if owner.is(SwitchCaseSyntax.self) { return deferToEnclosingExpression(of: owner) }

        guard let block = owner.as(CodeBlockSyntax.self), let holder = block.parent else {
            return false
        }

        if let function = holder.as(FunctionDeclSyntax.self) {
            return function.signature.returnClause != nil
        }
        if let accessor = holder.as(AccessorDeclSyntax.self) {
            return accessor.accessorSpecifier.tokenKind == .keyword(.get)
        }
        if holder.is(IfExprSyntax.self) {
            return deferToEnclosingExpression(of: holder)
        }
        // An initializer, a deinitializer, a `for` body, a `do` block: the value goes nowhere.
        return false
    }

    /// Whether an `if`/`switch` used as a value has its own value used — asked of whatever
    /// encloses it, so a branch inherits the answer rather than guessing one.
    private static func deferToEnclosingExpression(of node: Syntax) -> Bool {
        var current: Syntax? = node
        while let candidate = current {
            if let item = candidate.as(CodeBlockItemSyntax.self) { return valueIsUsed(of: item) }
            // Transparent wrappers on the way out. `ExpressionStmtSyntax` is the one that matters
            // and the one this first missed: a bare `if` STATEMENT is an `IfExprSyntax` wrapped in
            // an `ExpressionStmt`, so treating the wrapper as "somewhere a value is used" silenced
            // `if flag { items.map { … } }` — a genuine discard, and the control fixture caught it.
            guard candidate.is(ExpressionStmtSyntax.self) || candidate.is(SwitchCaseListSyntax.self)
                    || candidate.is(SwitchExprSyntax.self) || candidate.is(IfExprSyntax.self)
                    || candidate.is(CodeBlockItemListSyntax.self)
            else {
                // Anywhere else — an initializer clause, an argument — the value IS used.
                return true
            }
            current = candidate.parent
        }
        return false
    }
}
