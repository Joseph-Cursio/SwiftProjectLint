import SwiftProjectLintModels
import SwiftProjectLintRegistry
import SwiftProjectLintVisitors
import SwiftSyntax

/// Detects functions declared `/// @lint.context replayable` or `/// @lint.context retry_safe`
/// whose body calls a function declared `/// @lint.effect non_idempotent` in the same file.
///
/// Phase 1 of the idempotency trial: per-file symbol table only, no inference.
///
/// Closure traversal policy mirrors `IdempotencyViolationVisitor` — non-escaping only.
final class NonIdempotentInRetryContextVisitor: BasePatternVisitor {

    private var symbolTable = EffectSymbolTable()

    required init(pattern: SyntaxPattern, viewMode: SyntaxTreeViewMode = .sourceAccurate) {
        super.init(pattern: pattern, viewMode: viewMode)
    }

    override func visit(_ node: SourceFileSyntax) -> SyntaxVisitorContinueKind {
        symbolTable = EffectSymbolTable.build(from: node)
        return .visitChildren
    }

    override func visit(_ node: FunctionDeclSyntax) -> SyntaxVisitorContinueKind {
        guard let context = EffectAnnotationParser.parseContext(leadingTrivia: node.leadingTrivia),
              let body = node.body else {
            return .visitChildren
        }
        analyzeBody(Syntax(body), callerName: node.name.text, context: context)
        return .visitChildren
    }

    private func analyzeBody(_ syntax: Syntax, callerName: String, context: ContextEffect) {
        if syntax.is(FunctionDeclSyntax.self) { return }
        if let closure = syntax.as(ClosureExprSyntax.self), isEscapingClosure(closure) {
            return
        }

        if let call = syntax.as(FunctionCallExprSyntax.self) {
            if let calleeName = directCalleeName(from: call.calledExpression),
               let calleeEffect = symbolTable.effect(for: calleeName),
               calleeEffect == .nonIdempotent {
                let contextLabel: String = context == .replayable ? "replayable" : "retry_safe"
                addIssue(
                    severity: pattern.severity,
                    message: "Non-idempotent call in \(contextLabel) context: '\(callerName)' is declared "
                        + "`@lint.context \(contextLabel)` but calls '\(calleeName)', which is declared "
                        + "`@lint.effect non_idempotent`.",
                    filePath: getFilePath(for: Syntax(call)),
                    lineNumber: getLineNumber(for: Syntax(call)),
                    suggestion: "Replace '\(calleeName)' with an idempotent alternative, or route the call "
                        + "through a deduplication guard or idempotency-key mechanism.",
                    ruleName: .nonIdempotentInRetryContext
                )
            }
        }

        for child in syntax.children(viewMode: .sourceAccurate) {
            analyzeBody(child, callerName: callerName, context: context)
        }
    }

    /// See `IdempotencyViolationVisitor.isEscapingClosure` for the shared policy —
    /// the closure is escaping when the nearest enclosing `FunctionCallExprSyntax`
    /// has a callee name in `escapingCalleeNames`. `task` is included so SwiftUI's
    /// `.task { … }` modifier boundary is honoured.
    private func isEscapingClosure(_ closure: ClosureExprSyntax) -> Bool {
        var node = Syntax(closure).parent
        while let current = node {
            if let call = current.as(FunctionCallExprSyntax.self) {
                if let name = directCalleeName(from: call.calledExpression),
                   escapingCalleeNames.contains(name) {
                    return true
                }
                return false
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
        "withThrowingDiscardingTaskGroup",
        "task"
    ]
}
