import SwiftProjectLintModels
import SwiftProjectLintRegistry
import SwiftProjectLintVisitors
import SwiftSyntax

/// Detects functions whose declared effect contract is violated by a call to a
/// more-permissive callee in the same file.
///
/// Two declared-caller effects are analysed:
///
/// - `/// @lint.effect idempotent` — the body must not call a `@lint.effect non_idempotent`
///   callee. Observational and pure callees are acceptable.
/// - `/// @lint.effect observational` — the body must only call observational/pure callees.
///   An idempotent or non_idempotent callee is a violation, because observational claims
///   the body mutates no business state beyond observation sinks.
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
        guard let callerEffect = EffectAnnotationParser.parseEffect(leadingTrivia: node.leadingTrivia),
              callerEffect == .idempotent || callerEffect == .observational,
              let body = node.body else {
            return .visitChildren
        }
        analyzeBody(Syntax(body), callerName: node.name.text, callerEffect: callerEffect)
        return .visitChildren
    }

    private func analyzeBody(_ syntax: Syntax, callerName: String, callerEffect: DeclaredEffect) {
        if syntax.is(FunctionDeclSyntax.self) { return }
        if let closure = syntax.as(ClosureExprSyntax.self), isEscapingClosure(closure) {
            return
        }

        if let call = syntax.as(FunctionCallExprSyntax.self),
           let calleeName = directCalleeName(from: call.calledExpression),
           let calleeEffect = symbolTable.effect(for: calleeName),
           violates(caller: callerEffect, callee: calleeEffect) {
            emitViolation(
                call: call,
                callerName: callerName,
                callerEffect: callerEffect,
                calleeName: calleeName,
                calleeEffect: calleeEffect
            )
        }

        for child in syntax.children(viewMode: .sourceAccurate) {
            analyzeBody(child, callerName: callerName, callerEffect: callerEffect)
        }
    }

    /// Effect-conflict rules for Phase 1. Only direct declared-vs-declared mismatches
    /// fire; unannotated callees stay silent (Phase 1 does not infer).
    private func violates(caller: DeclaredEffect, callee: DeclaredEffect) -> Bool {
        switch (caller, callee) {
        case (.idempotent, .nonIdempotent):
            return true
        case (.observational, .nonIdempotent):
            return true
        case (.observational, .idempotent):
            return true
        default:
            return false
        }
    }

    private func emitViolation(
        call: FunctionCallExprSyntax,
        callerName: String,
        callerEffect: DeclaredEffect,
        calleeName: String,
        calleeEffect: DeclaredEffect
    ) {
        let callerTier = effectLabel(callerEffect)
        let calleeTier = effectLabel(calleeEffect)
        let headline: String
        let suggestion: String
        switch callerEffect {
        case .observational:
            headline = "Observational contract violation: '\(callerName)' is declared "
                + "`@lint.effect observational` but calls '\(calleeName)', which is declared "
                + "`@lint.effect \(calleeTier)`. Observational functions must not mutate "
                + "business state beyond observation sinks."
            suggestion = "Either call only observational/pure helpers from '\(callerName)', "
                + "or weaken its declared effect to `idempotent` / `non_idempotent`."
        case .idempotent:
            headline = "Idempotency violation: '\(callerName)' is declared "
                + "`@lint.effect \(callerTier)` but calls '\(calleeName)', which is declared "
                + "`@lint.effect \(calleeTier)`."
            suggestion = "Either change '\(calleeName)' to an idempotent alternative "
                + "(e.g. upsert, set-status-by-id), or weaken the declared effect of '\(callerName)'."
        default:
            // `nonIdempotent` caller is never analysed.
            return
        }
        addIssue(
            severity: pattern.severity,
            message: headline,
            filePath: getFilePath(for: Syntax(call)),
            lineNumber: getLineNumber(for: Syntax(call)),
            suggestion: suggestion,
            ruleName: .idempotencyViolation
        )
    }

    private func effectLabel(_ effect: DeclaredEffect) -> String {
        switch effect {
        case .idempotent: return "idempotent"
        case .observational: return "observational"
        case .nonIdempotent: return "non_idempotent"
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
