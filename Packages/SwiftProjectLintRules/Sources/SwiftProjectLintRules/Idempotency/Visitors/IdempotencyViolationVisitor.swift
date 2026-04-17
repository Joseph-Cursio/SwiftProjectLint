import SwiftProjectLintModels
import SwiftProjectLintRegistry
import SwiftProjectLintVisitors
import SwiftSyntax

/// Detects functions declared `/// @lint.effect idempotent` whose body calls a function
/// declared `/// @lint.effect non_idempotent` in the same file.
///
/// Phase 1 of the idempotency trial: no inference, per-file symbol table only.
/// A callee defined in another file produces no diagnostic — working as specified.
///
/// ## Closure traversal policy
/// The visitor descends into non-escaping closure bodies (the normal case for
/// synchronous control flow). It does not descend into `ClosureExprSyntax` passed as
/// escaping arguments (`Task { }`, `withTaskGroup { }`, `.task`) because the
/// idempotency contract on those boundaries belongs to a later-phase retry-context
/// check that Phase 1 explicitly excludes.
final class IdempotencyViolationVisitor: BasePatternVisitor {

    private var symbolTable = EffectSymbolTable()

    required init(pattern: SyntaxPattern, viewMode: SyntaxTreeViewMode = .sourceAccurate) {
        super.init(pattern: pattern, viewMode: viewMode)
    }

    override func visit(_ node: SourceFileSyntax) -> SyntaxVisitorContinueKind {
        symbolTable = EffectSymbolTable.build(from: node)
        return .visitChildren
    }

    override func visit(_ node: FunctionDeclSyntax) -> SyntaxVisitorContinueKind {
        guard EffectAnnotationParser.parseEffect(leadingTrivia: node.leadingTrivia) == .idempotent,
              let body = node.body else {
            return .visitChildren
        }
        analyzeBody(Syntax(body), callerName: node.name.text)
        return .visitChildren
    }

    private func analyzeBody(_ syntax: Syntax, callerName: String) {
        if syntax.is(FunctionDeclSyntax.self) { return }
        if let closure = syntax.as(ClosureExprSyntax.self), isEscapingClosure(closure) {
            return
        }

        if let call = syntax.as(FunctionCallExprSyntax.self) {
            if let calleeName = directCalleeName(from: call.calledExpression),
               let calleeEffect = symbolTable.effect(for: calleeName),
               calleeEffect == .nonIdempotent {
                addIssue(
                    severity: pattern.severity,
                    message: "Idempotency violation: '\(callerName)' is declared `@lint.effect idempotent` "
                        + "but calls '\(calleeName)', which is declared `@lint.effect non_idempotent`.",
                    filePath: getFilePath(for: Syntax(call)),
                    lineNumber: getLineNumber(for: Syntax(call)),
                    suggestion: "Either change '\(calleeName)' to an idempotent alternative (e.g. upsert, "
                        + "set-status-by-id), or weaken the declared effect of '\(callerName)'.",
                    ruleName: .idempotencyViolation
                )
            }
        }

        for child in syntax.children(viewMode: .sourceAccurate) {
            analyzeBody(child, callerName: callerName)
        }
    }

    /// A closure is treated as escaping when it appears as an argument to `Task`,
    /// `withTaskGroup`-family, `Task.detached`, or as a trailing-closure `.task` modifier.
    /// The visitor's Phase 1 scope stops at these boundaries.
    private func isEscapingClosure(_ closure: ClosureExprSyntax) -> Bool {
        var node = Syntax(closure).parent
        while let current = node {
            if let call = current.as(FunctionCallExprSyntax.self) {
                if let name = directCalleeName(from: call.calledExpression) {
                    if escapingCalleeNames.contains(name) { return true }
                }
                return false
            }
            if current.is(MemberAccessExprSyntax.self) {
                if let base = current.as(MemberAccessExprSyntax.self),
                   base.declName.baseName.text == "task" {
                    return true
                }
            }
            node = current.parent
        }
        return false
    }

    private func directCalleeName(from expr: ExprSyntax) -> String? {
        if let ref = expr.as(DeclReferenceExprSyntax.self) {
            return ref.baseName.text
        }
        if let member = expr.as(MemberAccessExprSyntax.self) {
            return member.declName.baseName.text
        }
        return nil
    }

    private let escapingCalleeNames: Set<String> = [
        "Task",
        "detached",
        "withTaskGroup",
        "withThrowingTaskGroup",
        "withDiscardingTaskGroup",
        "withThrowingDiscardingTaskGroup"
    ]
}
