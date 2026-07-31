import SwiftEffectInference
import SwiftProjectLintModels
import SwiftProjectLintVisitors
import SwiftSyntax

/// Detects direct call sites of `/// @lint.context once` callees that
/// appear in retry-prone positions: inside a `for` / `while` / `repeat`
/// loop body, or inside a function declared `/// @lint.context replayable`
/// or `/// @lint.context retry_safe`.
///
/// ## Cross-file dispatch
/// Conforms to `CrossFilePatternVisitorProtocol`. The walk phase
/// accumulates the symbol table and the list of analysis sites (every
/// function body in the project). Emission happens in `finalizeAnalysis()`
/// once the table is complete.
///
/// ## Closure traversal policy
/// Mirrors the other idempotency visitors: stops at escaping closures
/// (`Task { }`, `withTaskGroup`, `Task.detached`, SwiftUI `.task { }`).
/// A `@context once` call inside a `Task { }` that's spawned in a loop
/// is a known false-negative for this slice — the outer loop re-spawns
/// the Task, so the inner call DOES re-fire, but the boundary detection
/// would require additional cross-construct reasoning that the other
/// idempotency rules also defer.
///
/// ## Loop-ancestry test
/// A call site is "inside a loop" when, walking from the call up the
/// parent chain *without crossing a function-decl boundary*, we find a
/// node that is the body of an enclosing `ForStmtSyntax`,
/// `WhileStmtSyntax`, or `RepeatWhileStmtSyntax`. The iteration source
/// of a `for` loop and the condition of a `while` / `repeat` loop are
/// NOT counted as in-loop — they evaluate once per loop entry, so
/// flagging them would be a false positive.
///
/// ## Multi-hop scope
/// Phase 1 catches direct call sites only. A `@context replayable` body
/// calling an un-annotated helper that calls a `@context once` function
/// is not flagged here; the upward-inference infrastructure could be
/// extended to track context propagation in a follow-up.
final class OnceContractViolationVisitor: CrossFileVisitorBase, CrossFilePatternVisitorProtocol {

    /// This rule reads only the execution-context axis — never an effect — so it holds a
    /// context table, not the effect table.
    private var contextTable = ContextSymbolTable()
    private var analysisSites: [AnalysisSite] = []

    private struct AnalysisSite {
        let function: FunctionDeclSyntax
        /// Caller's own `@lint.context` annotation, if any. Used to surface
        /// the replayable / retry_safe trigger separately from the loop one.
        let callerContext: ContextEffect?
        let location: CapturedSiteLocation
    }

    override func visit(_ node: SourceFileSyntax) -> SyntaxVisitorContinueKind {
        contextTable.merge(source: node)
        return .visitChildren
    }

    override func visit(_ node: FunctionDeclSyntax) -> SyntaxVisitorContinueKind {
        guard node.body != nil else { return .visitChildren }
        analysisSites.append(
            AnalysisSite(
                function: node,
                callerContext: ContextAnnotationParser.parseContext(declaration: node),
                location: captureSiteLocation(rootedAt: node)
            )
        )
        return .visitChildren
    }

    func finalizeAnalysis() {
        // Run transitive once-reach inference across the whole project so
        // that calls to un-annotated helpers that themselves reach a
        // `@lint.context once` callee can be flagged. Direct call sites
        // are still detected by `analyzeCall` regardless of whether the
        // reach map has an entry — reach inference is purely additive.
        let allSources = Array(fileCache.values)
        contextTable.applyOnceReachInference(to: allSources)

        for site in analysisSites {
            guard let body = site.function.body else { continue }
            analyzeBody(Syntax(body), site: site)
        }
    }

    private func analyzeBody(_ syntax: Syntax, site: AnalysisSite) {
        // Don't re-enter nested function declarations — they are their own
        // analysis site in `analysisSites`.
        if syntax.is(FunctionDeclSyntax.self),
           syntax.positionAfterSkippingLeadingTrivia
                != site.function.positionAfterSkippingLeadingTrivia {
            return
        }
        if let closure = syntax.as(ClosureExprSyntax.self), EscapingClosurePolicy.isEscaping(closure) {
            return
        }

        if let call = syntax.as(FunctionCallExprSyntax.self),
           let signature = FunctionSignature.from(call: call) {
            // Direct callee declared `@lint.context once` is the Phase-1
            // trigger. Transitive reach via un-annotated intermediates is
            // the Phase-2 follow-up and only fires when the direct check
            // didn't (declared `.once` always wins).
            // By call shape: a `@lint.context once` migration declared `migrate(schema:dryRun:)`
            // and written `migrate(schema: s)` is unreachable by bare signature.
            let callSite = CallSiteShape.from(call: call) ?? CallSiteShape(signature: signature)
            if contextTable.context(for: callSite) == .once {
                analyzeCall(call, signature: signature, site: site, transitiveDepth: nil)
            } else if let reach = contextTable.onceReach(for: signature) {
                analyzeCall(call, signature: signature, site: site, transitiveDepth: reach.depth)
            }
        }

        for child in syntax.children(viewMode: .sourceAccurate) {
            analyzeBody(child, site: site)
        }
    }

    /// - Parameter transitiveDepth: `nil` when the callee is declared
    ///   `@lint.context once` directly. Non-nil when the callee transitively
    ///   reaches a once-callee — the value is the SHORTEST-path hop count
    ///   from the callee to the nearest once function (1 = the callee
    ///   directly calls a once function; N = N-1 un-annotated intermediates
    ///   between the callee and the once function).
    private func analyzeCall(
        _ call: FunctionCallExprSyntax,
        signature: FunctionSignature,
        site: AnalysisSite,
        transitiveDepth: Int?
    ) {
        let inLoop = isInsideLoopBody(call: call, withinFunctionBody: site.function.body)
        let callerContext = site.callerContext
        let isReplayableCaller = callerContext == .replayable
            || callerContext == .retrySafe
            || callerContext == .strictReplayable

        guard inLoop || isReplayableCaller else { return }

        let callerName = site.function.name.text
        let calleeName = signature.name
        let line = site.location.line(of: call)

        let calleeDescription: String
        if let depth = transitiveDepth {
            calleeDescription = "transitively reaches a `@lint.context once` callee "
                + "via a \(depth)-hop chain of un-annotated callees"
        } else {
            calleeDescription = "is declared `@lint.context once` and must run at most once"
        }

        let trigger: String
        let detail: String
        if inLoop, isReplayableCaller {
            trigger = "inside a loop within a `\(contextLabel(for: callerContext))` body"
            detail = "the loop will re-invoke '\(calleeName)' on every iteration, and "
                + "every replay/retry of '\(callerName)' compounds that re-invocation."
        } else if inLoop {
            trigger = "inside a loop"
            detail = "the loop will re-invoke '\(calleeName)' on every iteration."
        } else {
            trigger = "from a `\(contextLabel(for: callerContext))` body"
            detail = "every replay/retry of '\(callerName)' will re-invoke '\(calleeName)'."
        }

        addIssue(
            severity: pattern.severity,
            message: "Once-contract violation: '\(callerName)' calls '\(calleeName)' \(trigger). "
                + "'\(calleeName)' \(calleeDescription) — \(detail)",
            filePath: site.location.filePath,
            lineNumber: line,
            suggestion: "Either move '\(calleeName)' to a position guaranteed to execute at most "
                + "once (e.g. one-time init, idempotency-key-guarded path, or pre-loop hoist), "
                + "or weaken '\(calleeName)'s annotation if the once-contract is incorrect.",
            ruleName: .onceContractViolation
        )
    }

    /// Diagnostic label for a replayable/retry-safe context. Defaults to
    /// `retry_safe` for any context not explicitly named — analyzeCall
    /// only calls this when the caller is already known to be one of the
    /// three replayable kinds, so the default acts as a typed fallback.
    private func contextLabel(for context: ContextEffect?) -> String {
        switch context {
        case .replayable: return "replayable"
        case .strictReplayable: return "strict_replayable"
        default: return "retry_safe"
        }
    }

    /// Walks the parent chain from `call` up to (but not including) the
    /// enclosing function body. Returns `true` if any ancestor is the
    /// body of a `ForStmtSyntax`, `WhileStmtSyntax`, or
    /// `RepeatWhileStmtSyntax`. Iteration sources / loop conditions are
    /// not counted — they evaluate once per loop entry, not once per
    /// iteration.
    private func isInsideLoopBody(
        call: FunctionCallExprSyntax,
        withinFunctionBody body: CodeBlockSyntax?
    ) -> Bool {
        let bodyId = body.map { Syntax($0).id }
        var current: Syntax? = Syntax(call).parent
        while let node = current {
            if let bodyId, node.id == bodyId { return false }
            if isLoopBody(node) { return true }
            current = node.parent
        }
        return false
    }

    /// `true` if `node` is the `body` member of an enclosing loop statement.
    private func isLoopBody(_ node: Syntax) -> Bool {
        guard let parent = node.parent else { return false }
        if let forStmt = parent.as(ForStmtSyntax.self),
           node.id == Syntax(forStmt.body).id {
            return true
        }
        if let whileStmt = parent.as(WhileStmtSyntax.self),
           node.id == Syntax(whileStmt.body).id {
            return true
        }
        if let repeatStmt = parent.as(RepeatWhileStmtSyntax.self),
           node.id == Syntax(repeatStmt.body).id {
            return true
        }
        return false
    }
}
