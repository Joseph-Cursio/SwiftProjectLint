import SwiftProjectLintModels
import SwiftProjectLintRegistry
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
final class OnceContractViolationVisitor: BasePatternVisitor, CrossFilePatternVisitorProtocol {

    let fileCache: [String: SourceFileSyntax]

    private var symbolTable = EffectSymbolTable()
    private var analysisSites: [AnalysisSite] = []

    private struct AnalysisSite {
        let function: FunctionDeclSyntax
        /// Caller's own `@lint.context` annotation, if any. Used to surface
        /// the replayable / retry_safe trigger separately from the loop one.
        let callerContext: ContextEffect?
        let filePath: String
        let locationConverter: SourceLocationConverter
    }

    private var currentFilePath: String = ""
    private var currentLocationConverter: SourceLocationConverter?

    required init(fileCache: [String: SourceFileSyntax]) {
        self.fileCache = fileCache
        super.init(pattern: BasePatternVisitor.placeholderPattern, viewMode: .sourceAccurate)
    }

    required init(pattern: SyntaxPattern, viewMode: SyntaxTreeViewMode = .sourceAccurate) {
        self.fileCache = [:]
        super.init(pattern: pattern, viewMode: viewMode)
    }

    override func setFilePath(_ filePath: String) {
        super.setFilePath(filePath)
        currentFilePath = filePath
    }

    override func setSourceLocationConverter(_ converter: SourceLocationConverter) {
        super.setSourceLocationConverter(converter)
        currentLocationConverter = converter
    }

    override func visit(_ node: SourceFileSyntax) -> SyntaxVisitorContinueKind {
        symbolTable.merge(source: node)
        return .visitChildren
    }

    override func visit(_ node: FunctionDeclSyntax) -> SyntaxVisitorContinueKind {
        guard node.body != nil else { return .visitChildren }
        let converter = currentLocationConverter
            ?? SourceLocationConverter(fileName: currentFilePath, tree: node.root)
        analysisSites.append(
            AnalysisSite(
                function: node,
                callerContext: EffectAnnotationParser.parseContext(declaration: node),
                filePath: currentFilePath,
                locationConverter: converter
            )
        )
        return .visitChildren
    }

    func finalizeAnalysis() {
        for site in analysisSites {
            guard let body = site.function.body else { continue }
            analyzeBody(Syntax(body), site: site)
        }
    }

    func analyze() {
        finalizeAnalysis()
    }

    private func analyzeBody(_ syntax: Syntax, site: AnalysisSite) {
        // Don't re-enter nested function declarations — they are their own
        // analysis site in `analysisSites`.
        if syntax.is(FunctionDeclSyntax.self),
           syntax.positionAfterSkippingLeadingTrivia
                != site.function.positionAfterSkippingLeadingTrivia {
            return
        }
        if let closure = syntax.as(ClosureExprSyntax.self), isEscapingClosure(closure) {
            return
        }

        if let call = syntax.as(FunctionCallExprSyntax.self),
           let signature = FunctionSignature.from(call: call),
           symbolTable.context(for: signature) == .once {
            analyzeCall(call, signature: signature, site: site)
        }

        for child in syntax.children(viewMode: .sourceAccurate) {
            analyzeBody(child, site: site)
        }
    }

    private func analyzeCall(
        _ call: FunctionCallExprSyntax,
        signature: FunctionSignature,
        site: AnalysisSite
    ) {
        let inLoop = isInsideLoopBody(call: call, withinFunctionBody: site.function.body)
        let callerContext = site.callerContext
        let isReplayableCaller = callerContext == .replayable || callerContext == .retrySafe

        guard inLoop || isReplayableCaller else { return }

        let callerName = site.function.name.text
        let calleeName = signature.name
        let line = site.locationConverter.location(
            for: call.positionAfterSkippingLeadingTrivia
        ).line

        let trigger: String
        let detail: String
        if inLoop && isReplayableCaller {
            let contextLabel = callerContext == .replayable ? "replayable" : "retry_safe"
            trigger = "inside a loop within a `\(contextLabel)` body"
            detail = "the loop will re-invoke '\(calleeName)' on every iteration, and "
                + "every replay/retry of '\(callerName)' compounds that re-invocation."
        } else if inLoop {
            trigger = "inside a loop"
            detail = "the loop will re-invoke '\(calleeName)' on every iteration."
        } else {
            let contextLabel = callerContext == .replayable ? "replayable" : "retry_safe"
            trigger = "from a `\(contextLabel)` body"
            detail = "every replay/retry of '\(callerName)' will re-invoke '\(calleeName)'."
        }

        addIssue(
            severity: pattern.severity,
            message: "Once-contract violation: '\(callerName)' calls '\(calleeName)' \(trigger). "
                + "'\(calleeName)' is declared `@lint.context once` and must run at most once — "
                + detail,
            filePath: site.filePath,
            lineNumber: line,
            suggestion: "Either move '\(calleeName)' to a position guaranteed to execute at most "
                + "once (e.g. one-time init, idempotency-key-guarded path, or pre-loop hoist), "
                + "or weaken '\(calleeName)'s annotation if the once-contract is incorrect.",
            ruleName: .onceContractViolation
        )
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

    /// See `IdempotencyViolationVisitor.isEscapingClosure` for the shared policy.
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
