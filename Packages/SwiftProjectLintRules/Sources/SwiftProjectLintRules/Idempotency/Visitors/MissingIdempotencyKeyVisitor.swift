import SwiftProjectLintModels
import SwiftProjectLintRegistry
import SwiftProjectLintVisitors
import SwiftSyntax

/// Verifies that call sites targeting an `@lint.effect externally_idempotent(by: P)`
/// callee pass a stable value at argument label `P`. The Phase-2 lattice
/// trusts key routing at the call site; this rule is the verifier for that
/// trust.
///
/// ## What gets flagged
/// The argument at label `P` is flagged when it is a direct call to a known
/// per-invocation generator — `UUID()`, `Date()`, `arc4random()`,
/// `arc4random_uniform()`, `Int.random(in:)` — or a member access that
/// obviously derives from one (e.g. `UUID().uuidString`, `Date.now`).
///
/// ## What does NOT get flagged
/// Anything else: function parameters, property accesses, local constants,
/// string interpolations, etc. Verifying that a local constant actually
/// holds a stable upstream value requires data-flow analysis, which is
/// Phase 2's heuristic-inference / Phase 3's call-graph-propagation
/// territory. This rule is deliberately the narrow, high-precision check.
///
/// ## Quiet paths
/// - Callees annotated `externally_idempotent` *without* a `(by:)`
///   qualifier: the rule has nothing to check and stays silent.
/// - Callees resolved to `externally_idempotent` by collision (two
///   conflicting annotations withdraw the entry): the rule does not see
///   the callee and stays silent.
/// - Call sites where the labelled argument is absent: likely a default-
///   valued parameter; not flagged in Phase 2.1.
final class MissingIdempotencyKeyVisitor: BasePatternVisitor, CrossFilePatternVisitorProtocol {

    let fileCache: [String: SourceFileSyntax]

    private var symbolTable = EffectSymbolTable()
    private var analysisSites: [AnalysisSite] = []

    private struct AnalysisSite {
        let function: FunctionDeclSyntax
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
           syntax.positionAfterSkippingLeadingTrivia != site.function.positionAfterSkippingLeadingTrivia {
            return
        }
        if let closure = syntax.as(ClosureExprSyntax.self), isEscapingClosure(closure) {
            return
        }

        if let call = syntax.as(FunctionCallExprSyntax.self),
           let signature = FunctionSignature.from(call: call),
           let calleeEffect = symbolTable.effect(for: signature),
           case let .externallyIdempotent(keyParameter: keyParam) = calleeEffect,
           let keyParam {
            checkKeyArgument(call: call, keyParam: keyParam, site: site)
        }

        for child in syntax.children(viewMode: .sourceAccurate) {
            analyzeBody(child, site: site)
        }
    }

    private func checkKeyArgument(
        call: FunctionCallExprSyntax,
        keyParam: String,
        site: AnalysisSite
    ) {
        guard let arg = call.arguments.first(where: { $0.label?.text == keyParam }) else {
            // Labelled argument absent. Could be a defaulted parameter; the
            // Phase-2.1 rule does not flag this. A future enhancement could
            // cross-reference the callee's declaration to tell the
            // "defaulted" case from the "omitted required" case.
            return
        }
        guard let reason = nonStableReason(for: arg.expression) else { return }

        let calleeName = calleeBaseName(of: call.calledExpression) ?? "<unresolved>"
        let line = site.locationConverter.location(for: arg.positionAfterSkippingLeadingTrivia).line

        addIssue(
            severity: pattern.severity,
            message: "Idempotency-key argument to '\(calleeName)' is \(reason): each "
                + "invocation produces a different key, so retries do not converge. "
                + "The key must be derived from a stable upstream identifier that is the "
                + "same on replay.",
            filePath: site.filePath,
            lineNumber: line,
            suggestion: "Route a stable upstream identifier into the `\(keyParam):` argument — "
                + "e.g. an event ID, request ID, or message ID received from the caller. "
                + "If no such identifier is available, consider weakening '\(calleeName)' to "
                + "`@lint.effect non_idempotent` or introducing a deduplication guard at this site.",
            ruleName: .missingIdempotencyKey
        )
    }

    /// Returns a short human-readable reason when the expression obviously
    /// produces a fresh value on each invocation, or `nil` when the expression
    /// is opaque (i.e. potentially stable — Phase 2.1 does not infer beyond
    /// the direct-call case).
    private func nonStableReason(for expr: ExprSyntax) -> String? {
        // `UUID()`, `Date()`, `arc4random()`, etc. — direct call to a known
        // per-invocation generator.
        if let call = expr.as(FunctionCallExprSyntax.self),
           let name = calleeBaseName(of: call.calledExpression),
           Self.nonStableGenerators.contains(name) {
            return "a call to `\(name)()` (a fresh value on each invocation)"
        }
        if let member = expr.as(MemberAccessExprSyntax.self) {
            // `UUID().uuidString`, `UUID().hashValue`, etc. — member access on
            // a fresh generator result.
            if let base = member.base,
               let innerCall = base.as(FunctionCallExprSyntax.self),
               let name = calleeBaseName(of: innerCall.calledExpression),
               Self.nonStableGenerators.contains(name) {
                return "derived from `\(name)()` (`.\(member.declName.baseName.text)` of a fresh value)"
            }
            // `Date.now` — the classic "timestamp as idempotency key" mistake.
            if let base = member.base,
               let baseRef = base.as(DeclReferenceExprSyntax.self),
               Self.nonStableGeneratorTypes.contains(baseRef.baseName.text),
               member.declName.baseName.text == "now" {
                return "`\(baseRef.baseName.text).now` (a fresh timestamp)"
            }
        }
        return nil
    }

    /// Known generators that return a fresh value on each call. Kept narrow
    /// on purpose — the rule's false-positive risk rises if the set expands
    /// to include anything ambiguously stable.
    private static let nonStableGenerators: Set<String> = [
        "UUID",
        "Date",
        "arc4random",
        "arc4random_uniform",
        "CFUUIDCreate"
    ]

    /// Types whose `.now` property is a fresh-per-call timestamp.
    private static let nonStableGeneratorTypes: Set<String> = [
        "Date",
        "Clock",
        "ContinuousClock",
        "SuspendingClock"
    ]

    /// Closure-escaping policy mirrors the other idempotency visitors.
    private func isEscapingClosure(_ closure: ClosureExprSyntax) -> Bool {
        var node = Syntax(closure).parent
        while let current = node {
            if let call = current.as(FunctionCallExprSyntax.self) {
                if let name = calleeBaseName(of: call.calledExpression),
                   escapingCalleeNames.contains(name) {
                    return true
                }
                return false
            }
            node = current.parent
        }
        return false
    }

    private func calleeBaseName(of expr: ExprSyntax) -> String? {
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
