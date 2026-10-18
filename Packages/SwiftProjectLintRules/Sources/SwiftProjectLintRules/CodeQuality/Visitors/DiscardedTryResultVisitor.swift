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
///   value on, so best-effort cleanup is all it can do.
/// - `func data() -> Data? { try? load() }` — the sole expression of a function, getter or
///   subscript with a non-`Void` result is its implicit return value. The same holds for a
///   closure that spells out a non-`Void` return type, and for `Task { try? work() }.value`,
///   whose result is read. (A closure with no signature is left alone: whether its value is
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

    /// True when `item` is a statement of a `defer` block.
    func isDeferredCleanup(_ item: CodeBlockItemSyntax) -> Bool {
        item.parent?.as(CodeBlockItemListSyntax.self)?
            .parent?.as(CodeBlockSyntax.self)?
            .parent?.is(DeferStmtSyntax.self) == true
    }

    /// True when `item` is the only statement of a body whose value is returned implicitly:
    /// a function, getter or subscript with a non-`Void` result, a closure that spells out a
    /// non-`Void` return type, or a `Task { … }` whose `.value` is read.
    func isImplicitReturnValue(_ item: CodeBlockItemSyntax) -> Bool {
        guard let list = item.parent?.as(CodeBlockItemListSyntax.self), list.count == 1,
              let owner = list.parent
        else {
            return false
        }
        if let closure = owner.as(ClosureExprSyntax.self) {
            if let returnType = closure.signature?.returnClause?.type {
                return Self.isValueType(returnType)
            }
            return isReadTaskValue(closure)
        }
        // `var x: T { try? … }` — the getter shorthand, whose statements sit in the accessor block.
        if let accessorBlock = owner.as(AccessorBlockSyntax.self) {
            return Self.isValueType(Self.declaredType(of: accessorBlock))
        }
        guard let block = owner.as(CodeBlockSyntax.self) else { return false }
        if let function = block.parent?.as(FunctionDeclSyntax.self) {
            return Self.isValueType(function.signature.returnClause?.type)
        }
        if let accessor = block.parent?.as(AccessorDeclSyntax.self),
           accessor.accessorSpecifier.tokenKind == .keyword(.get),
           let accessorBlock = accessor.parent?.as(AccessorDeclListSyntax.self)?.parent?.as(AccessorBlockSyntax.self) {
            return Self.isValueType(Self.declaredType(of: accessorBlock))
        }
        return false
    }

    /// The type a property or subscript declares for the accessor block it owns.
    private static func declaredType(of accessorBlock: AccessorBlockSyntax) -> TypeSyntax? {
        if let binding = accessorBlock.parent?.as(PatternBindingSyntax.self) {
            return binding.typeAnnotation?.type
        }
        return accessorBlock.parent?.as(SubscriptDeclSyntax.self)?.returnClause.type
    }

    /// True for a written type other than `Void` or `()`.
    private static func isValueType(_ type: TypeSyntax?) -> Bool {
        guard let type else { return false }
        if type.as(IdentifierTypeSyntax.self)?.name.text == "Void" { return false }
        if let tuple = type.as(TupleTypeSyntax.self), tuple.elements.isEmpty { return false }
        return true
    }

    /// True for the closure of `Task { … }.value` or `Task.detached { … }.value`.
    private func isReadTaskValue(_ closure: ClosureExprSyntax) -> Bool {
        guard let call = closure.parent?.as(FunctionCallExprSyntax.self)
                ?? closure.parent?.as(LabeledExprSyntax.self)?
                    .parent?.as(LabeledExprListSyntax.self)?
                    .parent?.as(FunctionCallExprSyntax.self),
              let read = call.parent?.as(MemberAccessExprSyntax.self),
              read.declName.baseName.text == "value"
        else {
            return false
        }
        let callee = call.calledExpression
        if callee.as(DeclReferenceExprSyntax.self)?.baseName.text == "Task" {
            return true
        }
        if let member = callee.as(MemberAccessExprSyntax.self),
           member.base?.as(DeclReferenceExprSyntax.self)?.baseName.text == "Task" {
            return member.declName.baseName.text == "detached"
        }
        return false
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
