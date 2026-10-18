import SwiftProjectLintModels
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
/// - `defer { try? handle.close() }` — a `defer` block can neither throw nor hand a
///   value on, so best-effort cleanup is all it can do. That holds for a `try?` nested
///   in an `if`/`for`/`do` inside it too, but not in a closure the defer creates.
/// - `func data() -> Data? { try? load() }` — the sole expression of a function, getter or
///   subscript with a non-`Void` result is its implicit return value. The same holds for a
///   closure that spells out a non-`Void` return type, for `Task { try? work() }.value`,
///   whose result is read, and for a `Task<Data?, Never> { … }`, whose result is a value. A
///   branch of an `if`/`switch` expression in such a body, or one whose value is assigned or
///   returned, counts too. (A closure with no signature is left alone: whether its value is
///   used depends on a type the syntax does not show.)
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
        guard isTransformClosureResult(codeBlockItem) == false,
              isDeferredCleanup(codeBlockItem) == false,
              isImplicitReturnValue(codeBlockItem) == false
        else {
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
    func isTransformClosureResult(_ item: CodeBlockItemSyntax) -> Bool {
        guard let itemList = item.parent?.as(CodeBlockItemListSyntax.self),
              let closure = itemList.parent?.as(ClosureExprSyntax.self),
              itemList.last?.id == item.id
        else {
            return false
        }
        return enclosingCallMethodName(of: closure)
            .map(Self.transformMethods.contains) ?? false
    }

    // MARK: - Defer and implicit-return detection

    /// True when `item` runs as part of a `defer` block — one of its statements, or nested in
    /// an `if`/`for`/`do` inside it. A closure or declaration in between ends the search: its
    /// body can run after the defer, and may throw or return.
    func isDeferredCleanup(_ item: CodeBlockItemSyntax) -> Bool {
        var ancestor = item.parent
        while let node = ancestor {
            if node.is(DeferStmtSyntax.self) { return true }
            if node.is(ClosureExprSyntax.self) || node.is(DeclSyntax.self) { return false }
            ancestor = node.parent
        }
        return false
    }

    /// True when `item` is the only statement of a body whose value is returned implicitly:
    /// a function, getter or subscript with a non-`Void` result, a closure that spells out a
    /// non-`Void` return type, or a `Task { … }` whose `.value` is read or whose generic `Success`
    /// is a value. A branch of an `if` or `switch` expression counts when that expression's own
    /// value is used or returned this way.
    func isImplicitReturnValue(_ item: CodeBlockItemSyntax) -> Bool {
        guard let list = item.parent?.as(CodeBlockItemListSyntax.self), list.count == 1,
              let owner = list.parent
        else {
            return false
        }
        if let expression = Self.branchingExpression(owning: owner) {
            // `return if …`, `let x = switch …`: anywhere but statement position, the value is used.
            guard let statement = expression.parent?.as(ExpressionStmtSyntax.self) else { return true }
            return statement.parent?.as(CodeBlockItemSyntax.self).map(isImplicitReturnValue) ?? false
        }
        if let closure = owner.as(ClosureExprSyntax.self) {
            if let returnType = closure.signature?.returnClause?.type {
                return Self.isValueType(returnType)
            }
            return isKeptTaskResult(closure)
        }
        return Self.isValueType(Self.declaredResultType(ofBody: owner))
    }

    /// The result type a function, getter or subscript declares for `body`, its statements' owner.
    private static func declaredResultType(ofBody body: Syntax) -> TypeSyntax? {
        // `var x: T { try? … }` — the getter shorthand, whose statements sit in the accessor block.
        if let accessorBlock = body.as(AccessorBlockSyntax.self) {
            return declaredType(of: accessorBlock)
        }
        guard let block = body.as(CodeBlockSyntax.self) else { return nil }
        if let function = block.parent?.as(FunctionDeclSyntax.self) {
            return function.signature.returnClause?.type
        }
        if let accessor = block.parent?.as(AccessorDeclSyntax.self),
           accessor.accessorSpecifier.tokenKind == .keyword(.get),
           let accessorBlock = accessor.parent?.as(AccessorDeclListSyntax.self)?.parent?.as(AccessorBlockSyntax.self) {
            return declaredType(of: accessorBlock)
        }
        return nil
    }

    /// The `if` or `switch` expression whose branch `owner` is — for an `else if` chain, its
    /// outermost `if`, and only when the chain ends in a plain `else`, as an `if` expression must.
    private static func branchingExpression(owning owner: Syntax) -> ExprSyntax? {
        if let switchCase = owner.as(SwitchCaseSyntax.self) {
            return switchCase.parent?.as(SwitchCaseListSyntax.self)?
                .parent?.as(SwitchExprSyntax.self).map(ExprSyntax.init)
        }
        guard var outermost = owner.as(CodeBlockSyntax.self)?.parent?.as(IfExprSyntax.self) else { return nil }
        while let outer = outermost.parent?.as(IfExprSyntax.self) { outermost = outer }
        var last = outermost
        while let next = last.elseBody?.as(IfExprSyntax.self) { last = next }
        return last.elseBody?.is(CodeBlockSyntax.self) == true ? ExprSyntax(outermost) : nil
    }

    /// The type a property or subscript declares for the accessor block it owns.
    private static func declaredType(of accessorBlock: AccessorBlockSyntax) -> TypeSyntax? {
        if let binding = accessorBlock.parent?.as(PatternBindingSyntax.self) {
            return binding.typeAnnotation?.type
        }
        return accessorBlock.parent?.as(SubscriptDeclSyntax.self)?.returnClause.type
    }

    /// True for a written type other than `Void`, `Swift.Void` or `()`, in any parentheses.
    private static func isValueType(_ type: TypeSyntax?) -> Bool {
        guard let type else { return false }
        if type.as(IdentifierTypeSyntax.self)?.name.text == "Void" { return false }
        if let member = type.as(MemberTypeSyntax.self), member.name.text == "Void",
           member.baseType.as(IdentifierTypeSyntax.self)?.name.text == "Swift" {
            return false
        }
        if let tuple = type.as(TupleTypeSyntax.self) {
            if tuple.elements.isEmpty { return false }
            // `(Void)` and `(())` are the type in parentheses, not a one-element tuple.
            if tuple.elements.count == 1, let only = tuple.elements.first, only.firstName == nil {
                return isValueType(only.type)
            }
        }
        return true
    }

    /// True for the closure of a `Task` whose result is kept: `Task { … }.value` or
    /// `Task.detached { … }.value`, or a `Task<Success, Failure>` that spells out a non-`Void`
    /// `Success`, whether or not its `.value` is read right there.
    private func isKeptTaskResult(_ closure: ClosureExprSyntax) -> Bool {
        guard let call = closure.parent?.as(FunctionCallExprSyntax.self)
                ?? closure.parent?.as(LabeledExprSyntax.self)?
                    .parent?.as(LabeledExprListSyntax.self)?
                    .parent?.as(FunctionCallExprSyntax.self)
        else {
            return false
        }
        var task = call.calledExpression
        if let member = task.as(MemberAccessExprSyntax.self), let base = member.base,
           member.declName.baseName.text == "detached" {
            task = base
        }
        if let specialized = task.as(GenericSpecializationExprSyntax.self),
           specialized.expression.as(DeclReferenceExprSyntax.self)?.baseName.text == "Task" {
            return Self.isValueType(specialized.genericArgumentClause.arguments.first?.argument.as(TypeSyntax.self))
        }
        return task.as(DeclReferenceExprSyntax.self)?.baseName.text == "Task"
            && call.parent?.as(MemberAccessExprSyntax.self)?.declName.baseName.text == "value"
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
